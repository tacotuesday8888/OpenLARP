import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPProofUploadReconciliationAuth = {
  uid: string;
};

export type OpenLARPProofUploadReconciliationRequest = {
  auth?: OpenLARPProofUploadReconciliationAuth | null;
  data: unknown;
};

export type OpenLARPProofUploadReconciliationMode = "reportOnly" | "deleteOrphans";

export type ProofUploadStorageObject = {
  name: string;
  contentType: string | undefined;
  size: number | undefined;
  updatedAt: string | undefined;
  bucket: string | undefined;
  generation: string | undefined;
  metageneration: string | undefined;
  md5Hash: string | undefined;
  metadata: Record<string, string | undefined> | undefined;
};

export type ProofUploadFirestoreAttachment =
  | { exists: true; data: Record<string, unknown> }
  | { exists: false };

export type ProofUploadReconciliationCandidate = {
  attachmentID: string;
  storagePath: string;
  proofID: string | undefined;
  status:
    | "linked"
    | "orphanedStorageObject"
    | "metadataMismatch"
    | "firestoreReceiptMismatch"
    | "deleted";
  canDelete: boolean;
  deleted: boolean;
  reason: string;
};

export type ProofUploadReconciliationSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  mode: OpenLARPProofUploadReconciliationMode;
  evaluatedAt: string;
  scannedCount: number;
  orphanedCount: number;
  deletedCount: number;
  candidates: ProofUploadReconciliationCandidate[];
  externalActionTaken: boolean;
};

export type ProofUploadReconciliationResponse =
  | ProofUploadReconciliationSuccess
  | OpenLARPFunctionError;

export type ProofUploadReconciliationDependencies = {
  listStorageObjects: (
    userID: string,
    attachmentIDs: string[] | undefined,
    maxAttachments: number
  ) => Promise<ProofUploadStorageObject[]>;
  readFirestoreAttachment: (
    userID: string,
    attachmentID: string
  ) => Promise<ProofUploadFirestoreAttachment>;
  deleteStorageObjectGeneration: (
    storagePath: string,
    generation: string | undefined
  ) => Promise<boolean>;
  now?: () => Date;
};

type ParsedRequest = {
  mode: OpenLARPProofUploadReconciliationMode;
  attachmentIDs: string[] | undefined;
  maxAttachments: number;
  minimumAgeMinutes: number;
  confirmDeletion: boolean;
};

const DEFAULT_MAX_ATTACHMENTS = 50;
const HARD_MAX_ATTACHMENTS = 100;
const DEFAULT_MINIMUM_AGE_MINUTES = 15;
const HARD_MAXIMUM_AGE_MINUTES = 24 * 60;

export async function handleProofUploadReconciliationRequest(
  request: OpenLARPProofUploadReconciliationRequest,
  dependencies: ProofUploadReconciliationDependencies = adminProofUploadReconciliationDependencies()
): Promise<ProofUploadReconciliationResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before reconciling proof uploads.");
  }

  const parsed = parseReconciliationRequest(request.data);
  if (!parsed.ok) {
    return parsed.error;
  }

  if (parsed.value.mode === "deleteOrphans" && !parsed.value.confirmDeletion) {
    return functionError(
      "failed-precondition",
      "Deleting orphaned proof uploads requires confirmDeletion=true."
    );
  }

  const storageObjects = await dependencies.listStorageObjects(
    userID,
    parsed.value.attachmentIDs,
    parsed.value.maxAttachments
  );

  const candidates: ProofUploadReconciliationCandidate[] = [];
  for (const storageObject of storageObjects) {
    const candidate = await evaluateStorageObject(
      userID,
      storageObject,
      dependencies,
      parsed.value.minimumAgeMinutes
    );
    if (
      parsed.value.mode === "deleteOrphans" &&
      candidate.status === "orphanedStorageObject" &&
      candidate.canDelete
    ) {
      const refreshedCandidate = await evaluateStorageObject(
        userID,
        storageObject,
        dependencies,
        parsed.value.minimumAgeMinutes
      );
      if (refreshedCandidate.status !== "orphanedStorageObject" || !refreshedCandidate.canDelete) {
        candidates.push(refreshedCandidate);
        continue;
      }

      const didDelete = await dependencies.deleteStorageObjectGeneration(
        refreshedCandidate.storagePath,
        storageObject.generation
      );
      if (!didDelete) {
        candidates.push({
          ...refreshedCandidate,
          canDelete: false,
          reason: "Storage object changed before deletion, so cleanup was skipped."
        });
        continue;
      }

      candidates.push({
        ...refreshedCandidate,
        status: "deleted",
        deleted: true,
        reason: "Deleted safe orphaned proof upload with matching owner metadata and no Firestore attachment document."
      });
    } else {
      candidates.push(candidate);
    }
  }

  const orphanedCount = candidates.filter((candidate) =>
    candidate.status === "orphanedStorageObject" || candidate.status === "deleted"
  ).length;
  const deletedCount = candidates.filter((candidate) => candidate.deleted).length;

  return {
    ok: true,
    schemaVersion: 1,
    userID,
    mode: parsed.value.mode,
    evaluatedAt: (dependencies.now?.() ?? new Date()).toISOString(),
    scannedCount: candidates.length,
    orphanedCount,
    deletedCount,
    candidates,
    externalActionTaken: deletedCount > 0
  };
}

async function evaluateStorageObject(
  userID: string,
  storageObject: ProofUploadStorageObject,
  dependencies: ProofUploadReconciliationDependencies,
  minimumAgeMinutes: number
): Promise<ProofUploadReconciliationCandidate> {
  const attachmentID = attachmentIDFromPath(userID, storageObject.name);
  const proofID = storageObject.metadata?.proofID;
  const baseCandidate = {
    attachmentID: attachmentID ?? "",
    storagePath: storageObject.name,
    proofID,
    canDelete: false,
    deleted: false
  };

  if (!attachmentID || !hasSafeOwnerMetadata(userID, attachmentID, storageObject)) {
    return {
      ...baseCandidate,
      status: "metadataMismatch",
      reason: "Storage object path or custom metadata does not match the signed-in owner and attachment ID."
    };
  }

  const firestoreAttachment = await dependencies.readFirestoreAttachment(userID, attachmentID);
  if (!firestoreAttachment.exists) {
    const now = dependencies.now?.() ?? new Date();
    const isOldEnough = isStorageObjectOldEnough(storageObject.updatedAt, now, minimumAgeMinutes);
    return {
      ...baseCandidate,
      attachmentID,
      status: "orphanedStorageObject",
      canDelete: isOldEnough,
      reason: isOldEnough
        ? "Storage upload exists, but the matching Firestore proof attachment document is missing."
        : "Storage upload is too recent to delete safely because the Firestore metadata write may still retry."
    };
  }

  if (!firestoreReceiptMatches(userID, attachmentID, storageObject, firestoreAttachment.data)) {
    return {
      ...baseCandidate,
      attachmentID,
      status: "firestoreReceiptMismatch",
      reason: "Firestore proof attachment exists, but its upload receipt does not match the Storage object."
    };
  }

  return {
    ...baseCandidate,
    attachmentID,
    status: "linked",
    reason: "Storage upload and Firestore proof attachment receipt match."
  };
}

function parseReconciliationRequest(data: unknown):
  | { ok: true; value: ParsedRequest }
  | { ok: false; error: OpenLARPFunctionError } {
  if (data !== undefined && data !== null && (typeof data !== "object" || Array.isArray(data))) {
    return {
      ok: false,
      error: functionError("invalid-argument", "Proof upload reconciliation request must be an object.")
    };
  }

  const record = (data ?? {}) as Record<string, unknown>;
  const mode = parseMode(record.mode);
  if (!mode) {
    return {
      ok: false,
      error: functionError("invalid-argument", "mode must be reportOnly or deleteOrphans.")
    };
  }

  const attachmentIDs = parseAttachmentIDs(record.attachmentIDs);
  if (attachmentIDs === null) {
    return {
      ok: false,
      error: functionError("invalid-argument", "attachmentIDs must be an array of proof attachment IDs.")
    };
  }

  const maxAttachments = parseMaxAttachments(record.maxAttachments);
  if (maxAttachments === null) {
    return {
      ok: false,
      error: functionError(
        "invalid-argument",
        `maxAttachments must be an integer between 1 and ${HARD_MAX_ATTACHMENTS}.`
      )
    };
  }

  const minimumAgeMinutes = parseMinimumAgeMinutes(record.minimumAgeMinutes);
  if (minimumAgeMinutes === null) {
    return {
      ok: false,
      error: functionError(
        "invalid-argument",
        `minimumAgeMinutes must be an integer between ${DEFAULT_MINIMUM_AGE_MINUTES} and ${HARD_MAXIMUM_AGE_MINUTES}.`
      )
    };
  }

  return {
    ok: true,
    value: {
      mode,
      attachmentIDs,
      maxAttachments,
      minimumAgeMinutes,
      confirmDeletion: record.confirmDeletion === true
    }
  };
}

function parseMode(value: unknown): OpenLARPProofUploadReconciliationMode | null {
  if (value === undefined) {
    return "reportOnly";
  }

  return value === "reportOnly" || value === "deleteOrphans" ? value : null;
}

function parseAttachmentIDs(value: unknown): string[] | undefined | null {
  if (value === undefined) {
    return undefined;
  }

  if (!Array.isArray(value)) {
    return null;
  }

  const ids = value
    .map((item) => typeof item === "string" ? item.trim() : "")
    .filter((item) => item.length > 0 && !item.includes("/"));
  if (ids.length !== value.length) {
    return null;
  }

  const uniqueIDs = [...new Set(ids)].slice(0, HARD_MAX_ATTACHMENTS);
  return uniqueIDs.length > 0 ? uniqueIDs : null;
}

function parseMaxAttachments(value: unknown): number | null {
  if (value === undefined) {
    return DEFAULT_MAX_ATTACHMENTS;
  }

  if (typeof value !== "number") {
    return null;
  }

  if (!Number.isInteger(value) || value < 1 || value > HARD_MAX_ATTACHMENTS) {
    return null;
  }

  return value;
}

function parseMinimumAgeMinutes(value: unknown): number | null {
  if (value === undefined) {
    return DEFAULT_MINIMUM_AGE_MINUTES;
  }

  if (typeof value !== "number") {
    return null;
  }

  if (
    !Number.isInteger(value) ||
    value < DEFAULT_MINIMUM_AGE_MINUTES ||
    value > HARD_MAXIMUM_AGE_MINUTES
  ) {
    return null;
  }

  return value;
}

function attachmentIDFromPath(userID: string, storagePath: string): string | null {
  const prefix = `users/${userID}/proofAttachments/`;
  if (!storagePath.startsWith(prefix)) {
    return null;
  }

  const attachmentID = storagePath.slice(prefix.length);
  return attachmentID.length > 0 && !attachmentID.includes("/") ? attachmentID : null;
}

function hasSafeOwnerMetadata(
  userID: string,
  attachmentID: string,
  storageObject: ProofUploadStorageObject
): boolean {
  const metadata = storageObject.metadata ?? {};
  return metadata.ownerUserID === userID &&
    metadata.attachmentID === attachmentID &&
    metadata.idempotencyKey === `${userID}-${attachmentID}` &&
    typeof metadata.proofID === "string" &&
    metadata.proofID.length > 0;
}

function firestoreReceiptMatches(
  userID: string,
  attachmentID: string,
  storageObject: ProofUploadStorageObject,
  firestoreData: Record<string, unknown> | undefined
): boolean {
  if (!firestoreData) {
    return false;
  }

  const receipt = firestoreData.uploadReceipt;
  if (!receipt || typeof receipt !== "object") {
    return false;
  }

  const receiptRecord = receipt as Record<string, unknown>;
  const metadata = storageObject.metadata ?? {};
  const byteCount = typeof storageObject.size === "number"
    ? storageObject.size
    : Number.parseInt(String(storageObject.size ?? ""), 10);

  return firestoreData.uploadStatus === "uploaded" &&
    firestoreData.storagePath === storageObject.name &&
    firestoreData.proofID === metadata.proofID &&
    receiptRecord.status === "uploaded" &&
    receiptRecord.proofID === metadata.proofID &&
    receiptRecord.attachmentID === attachmentID &&
    receiptRecord.storagePath === storageObject.name &&
    receiptRecord.contentType === storageObject.contentType &&
    receiptRecord.byteCount === byteCount &&
    receiptRecord.idempotencyKey === `${userID}-${attachmentID}`;
}

function isStorageObjectOldEnough(
  updatedAt: string | undefined,
  now: Date,
  minimumAgeMinutes: number
): boolean {
  if (!updatedAt) {
    return false;
  }

  const updatedDate = new Date(updatedAt);
  if (!Number.isFinite(updatedDate.getTime())) {
    return false;
  }

  return now.getTime() - updatedDate.getTime() >= minimumAgeMinutes * 60_000;
}

function adminProofUploadReconciliationDependencies(): ProofUploadReconciliationDependencies {
  return {
    async listStorageObjects(userID, attachmentIDs, maxAttachments) {
      if (attachmentIDs && attachmentIDs.length > 0) {
        const objects = await Promise.all(
          attachmentIDs.slice(0, maxAttachments).map((attachmentID) =>
            readStorageObject(`users/${userID}/proofAttachments/${attachmentID}`)
          )
        );
        return objects.filter((object): object is ProofUploadStorageObject => object !== null);
      }

      const [files] = await getStorage().bucket().getFiles({
        prefix: `users/${userID}/proofAttachments/`,
        maxResults: maxAttachments
      });
      const objects = await Promise.all(files.map((file) => readStorageObject(file.name)));
      return objects.filter((object): object is ProofUploadStorageObject => object !== null);
    },
    async readFirestoreAttachment(userID, attachmentID) {
      const snapshot = await getFirestore()
        .doc(`users/${userID}/proofAttachments/${attachmentID}`)
        .get();
      const data = snapshot.data();
      return snapshot.exists && data ? { exists: true, data } : { exists: false };
    },
    async deleteStorageObjectGeneration(storagePath, generation) {
      if (!generation) {
        return false;
      }

      const parsedGeneration = Number.parseInt(generation, 10);
      if (!Number.isFinite(parsedGeneration)) {
        return false;
      }

      try {
        await getStorage().bucket().file(storagePath).delete({
          ignoreNotFound: true,
          ifGenerationMatch: parsedGeneration
        });
        return true;
      } catch {
        return false;
      }
    }
  };
}

async function readStorageObject(storagePath: string): Promise<ProofUploadStorageObject | null> {
  const file = getStorage().bucket().file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    return null;
  }

  const [metadata] = await file.getMetadata();
  const size = typeof metadata.size === "number"
    ? metadata.size
    : Number.parseInt(String(metadata.size ?? ""), 10);
  return {
    name: storagePath,
    contentType: metadata.contentType,
    size: Number.isFinite(size) ? size : undefined,
    updatedAt: timestampToISOString(metadata.updated),
    bucket: metadata.bucket,
    generation: metadata.generation === undefined ? undefined : String(metadata.generation),
    metageneration: metadata.metageneration === undefined ? undefined : String(metadata.metageneration),
    md5Hash: metadata.md5Hash,
    metadata: metadata.metadata as Record<string, string | undefined> | undefined
  };
}

function timestampToISOString(value: unknown): string | undefined {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }

  if (typeof value === "string" && value.length > 0) {
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date.toISOString() : undefined;
  }

  return undefined;
}
