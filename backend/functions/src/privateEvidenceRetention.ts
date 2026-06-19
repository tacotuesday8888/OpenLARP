import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { type CallableQuotaGuard } from "./callableQuotaGuard.js";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPPrivateEvidenceRetentionAuth = {
  uid: string;
};

export type OpenLARPPrivateEvidenceRetentionRequest = {
  auth?: OpenLARPPrivateEvidenceRetentionAuth | null;
  data: unknown;
};

export type PrivateEvidenceRetentionMode = "reportOnly" | "deleteSyncedEvidence";

export type PrivateEvidenceRetentionStorageObject = {
  name: string;
  contentType: string | undefined;
  size: number | undefined;
  generation: string | undefined;
  metadata: Record<string, string | undefined> | undefined;
};

export type PrivateEvidenceRetentionAttachmentSnapshot =
  | {
    exists: true;
    attachmentID: string;
    data: Record<string, unknown>;
  }
  | {
    exists: false;
    attachmentID: string;
  };

export type PrivateEvidenceRetentionAttachmentDeletePrecondition = {
  proofID: string;
  storagePath: string;
  contentType: string;
  byteCount: number;
  idempotencyKey: string;
  storageGeneration: string;
};

export type PrivateEvidenceRetentionCandidateStatus =
  | "eligible"
  | "deleted"
  | "missingFirestoreAttachment"
  | "firestoreReceiptMismatch"
  | "storageObjectMissing"
  | "storageMetadataMismatch"
  | "storageDeleteFailed"
  | "firestoreDeleteFailed";

export type PrivateEvidenceRetentionCandidate = {
  attachmentID: string;
  proofID?: string;
  storagePath: string;
  storageGeneration?: string;
  status: PrivateEvidenceRetentionCandidateStatus;
  canDelete: boolean;
  deleted: boolean;
  reason: string;
};

export type PrivateEvidenceRetentionSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  mode: PrivateEvidenceRetentionMode;
  evaluatedAt: string;
  scannedCount: number;
  eligibleCount: number;
  deletedCount: number;
  partialFailureCount: number;
  candidates: PrivateEvidenceRetentionCandidate[];
  externalActionTaken: boolean;
};

export type PrivateEvidenceRetentionResponse =
  | PrivateEvidenceRetentionSuccess
  | OpenLARPFunctionError;

export type PrivateEvidenceRetentionDependencies = {
  readPrivateEvidenceCloudSyncConsent: (userID: string) => Promise<Record<string, unknown> | null>;
  listProofAttachments: (
    userID: string,
    attachmentIDs: string[] | undefined,
    maxAttachments: number
  ) => Promise<PrivateEvidenceRetentionAttachmentSnapshot[]>;
  readStorageObject: (storagePath: string) => Promise<PrivateEvidenceRetentionStorageObject | null>;
  deleteStorageObjectGeneration: (
    storagePath: string,
    generation: string | undefined
  ) => Promise<boolean>;
  deleteProofAttachmentDocument: (
    userID: string,
    attachmentID: string,
    precondition: PrivateEvidenceRetentionAttachmentDeletePrecondition
  ) => Promise<boolean>;
  quotaGuard?: CallableQuotaGuard;
  now?: () => Date;
};

type ParsedRequest = {
  mode: PrivateEvidenceRetentionMode;
  attachmentIDs: string[] | undefined;
  maxAttachments: number;
  confirmDeletion: boolean;
};

type ValidAttachment = {
  attachmentID: string;
  proofID: string;
  storagePath: string;
  contentType: string;
  byteCount: number;
  idempotencyKey: string;
  storageGeneration: string;
};

type EvaluatedRetentionCandidate = PrivateEvidenceRetentionCandidate & {
  deletePrecondition?: PrivateEvidenceRetentionAttachmentDeletePrecondition;
};

const CONSENT_TEXT_VERSION = "private-evidence-cloud-sync-v1";
const DEFAULT_MAX_ATTACHMENTS = 25;
const HARD_MAX_ATTACHMENTS = 100;

export async function handlePrivateEvidenceRetentionRequest(
  request: OpenLARPPrivateEvidenceRetentionRequest,
  dependencies: PrivateEvidenceRetentionDependencies = adminPrivateEvidenceRetentionDependencies()
): Promise<PrivateEvidenceRetentionResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before cleaning up private evidence cloud backups.");
  }

  const parsed = parseRetentionRequest(request.data);
  if (!parsed.ok) {
    return parsed.error;
  }

  if (parsed.value.mode === "deleteSyncedEvidence" && !parsed.value.confirmDeletion) {
    return functionError(
      "failed-precondition",
      "Deleting synced private evidence requires confirmDeletion=true."
    );
  }

  if (parsed.value.mode === "deleteSyncedEvidence" && !parsed.value.attachmentIDs) {
    return functionError(
      "failed-precondition",
      "Deleting synced private evidence requires explicit attachmentIDs."
    );
  }
  if (
    parsed.value.mode === "deleteSyncedEvidence" &&
    parsed.value.attachmentIDs &&
    parsed.value.maxAttachments < parsed.value.attachmentIDs.length
  ) {
    return functionError(
      "invalid-argument",
      "maxAttachments must be at least the number of explicit attachmentIDs when deleting synced evidence."
    );
  }

  const consentDocument = await dependencies.readPrivateEvidenceCloudSyncConsent(userID);
  if (!isRevokedPrivateEvidenceCloudSyncConsentDocument(userID, consentDocument)) {
    return functionError(
      "permission-denied",
      "Turn off private evidence cloud sync before cleaning up synced private evidence."
    );
  }

  const evaluatedAt = dependencies.now?.() ?? new Date();
  const quotaDecision = await dependencies.quotaGuard?.checkAndRecord({
    userID,
    callable: "cleanupRevokedPrivateEvidenceUploads",
    category: "privateEvidenceRetention",
    units: retentionQuotaUnits(parsed.value),
    occurredAt: evaluatedAt,
    metadata: {
      mode: parsed.value.mode,
      maxAttachments: parsed.value.maxAttachments,
      hasAttachmentFilter: parsed.value.attachmentIDs !== undefined
    }
  });
  if (quotaDecision && !quotaDecision.ok) {
    return quotaDecision.error;
  }

  const attachments = await dependencies.listProofAttachments(
    userID,
    parsed.value.attachmentIDs,
    parsed.value.maxAttachments
  );
  const candidates: EvaluatedRetentionCandidate[] = [];

  for (const attachment of attachments) {
    const candidate = await evaluateAttachment(userID, attachment, dependencies);
    if (parsed.value.mode !== "deleteSyncedEvidence" || !candidate.canDelete) {
      candidates.push(candidate);
      continue;
    }

    candidates.push(await deleteCandidate(userID, candidate, dependencies));
  }

  const deletedCount = candidates.filter((candidate) => candidate.deleted).length;
  const partialFailureCount = candidates.filter((candidate) =>
    candidate.status === "storageDeleteFailed" || candidate.status === "firestoreDeleteFailed"
  ).length;
  const externalActionTaken = candidates.some((candidate) =>
    candidate.deleted ||
      candidate.status === "storageDeleteFailed"
  );
  const responseCandidates = candidates.map(publicCandidate);

  return {
    ok: true,
    schemaVersion: 1,
    userID,
    mode: parsed.value.mode,
    evaluatedAt: evaluatedAt.toISOString(),
    scannedCount: responseCandidates.length,
    eligibleCount: candidates.filter(wasEligibleForCleanup).length,
    deletedCount,
    partialFailureCount,
    candidates: responseCandidates,
    externalActionTaken
  };
}

export function isRevokedPrivateEvidenceCloudSyncConsentDocument(
  userID: string,
  data: Record<string, unknown> | null | undefined
): boolean {
  return data?.schemaVersion === 1
    && data?.ownerUserID === userID
    && data?.status === "revoked"
    && data?.allowsPrivateEvidenceCloudSync === false
    && data?.consentTextVersion === CONSENT_TEXT_VERSION;
}

function parseRetentionRequest(data: unknown):
  | { ok: true; value: ParsedRequest }
  | { ok: false; error: OpenLARPFunctionError } {
  if (data !== undefined && data !== null && (typeof data !== "object" || Array.isArray(data))) {
    return {
      ok: false,
      error: functionError("invalid-argument", "Private evidence retention request must be an object.")
    };
  }

  const record = (data ?? {}) as Record<string, unknown>;
  const schemaVersion = record.schemaVersion === undefined ? 1 : record.schemaVersion;
  if (schemaVersion !== 1) {
    return {
      ok: false,
      error: functionError("invalid-argument", "schemaVersion must be 1.")
    };
  }

  const mode = parseMode(record.mode);
  if (!mode) {
    return {
      ok: false,
      error: functionError("invalid-argument", "mode must be reportOnly or deleteSyncedEvidence.")
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

  return {
    ok: true,
    value: {
      mode,
      attachmentIDs,
      maxAttachments,
      confirmDeletion: record.confirmDeletion === true
    }
  };
}

function parseMode(value: unknown): PrivateEvidenceRetentionMode | null {
  if (value === undefined) {
    return "reportOnly";
  }

  return value === "reportOnly" || value === "deleteSyncedEvidence" ? value : null;
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
    .filter((item) => item.length > 0 && item.length <= 128 && !item.includes("/"));
  if (ids.length !== value.length || ids.length > HARD_MAX_ATTACHMENTS) {
    return null;
  }

  const uniqueIDs = [...new Set(ids)];
  return uniqueIDs.length > 0 ? uniqueIDs : null;
}

function parseMaxAttachments(value: unknown): number | null {
  if (value === undefined) {
    return DEFAULT_MAX_ATTACHMENTS;
  }

  if (typeof value !== "number") {
    return null;
  }

  return Number.isInteger(value) && value >= 1 && value <= HARD_MAX_ATTACHMENTS
    ? value
    : null;
}

function retentionQuotaUnits(request: ParsedRequest): number {
  const scanUnits = Math.max(1, Math.ceil(request.maxAttachments / 25));
  return request.mode === "deleteSyncedEvidence" ? scanUnits + 2 : scanUnits;
}

async function evaluateAttachment(
  userID: string,
  attachment: PrivateEvidenceRetentionAttachmentSnapshot,
  dependencies: PrivateEvidenceRetentionDependencies
): Promise<EvaluatedRetentionCandidate> {
  const fallbackStoragePath = `users/${userID}/proofAttachments/${attachment.attachmentID}`;
  if (!attachment.exists) {
    return {
      attachmentID: attachment.attachmentID,
      storagePath: fallbackStoragePath,
      status: "missingFirestoreAttachment",
      canDelete: false,
      deleted: false,
      reason: "No server proof attachment document exists for this attachment ID."
    };
  }

  const validAttachment = parseUploadedAttachmentDocument(userID, attachment.attachmentID, attachment.data);
  if (!validAttachment.ok) {
    return {
      attachmentID: attachment.attachmentID,
      storagePath: fallbackStoragePath,
      status: "firestoreReceiptMismatch",
      canDelete: false,
      deleted: false,
      reason: validAttachment.reason
    };
  }

  const storageObject = await dependencies.readStorageObject(validAttachment.value.storagePath);
  const storageGeneration = storageObject?.generation ?? validAttachment.value.storageGeneration;
  const baseCandidate = baseCandidateForValidAttachment(validAttachment.value, storageGeneration);

  if (!storageObject) {
    return {
      ...baseCandidate,
      status: "storageObjectMissing",
      canDelete: true,
      deletePrecondition: deletePreconditionFromValidAttachment(validAttachment.value),
      reason: "Storage proof file is already missing; the server proof attachment document can be removed."
    };
  }

  const storageValidation = validateStorageObject(userID, validAttachment.value, storageObject);
  if (!storageValidation.ok) {
    return {
      ...baseCandidate,
      status: storageValidation.status,
      canDelete: false,
      reason: storageValidation.reason
    };
  }

  return {
    ...baseCandidate,
    status: "eligible",
    canDelete: true,
    deletePrecondition: deletePreconditionFromValidAttachment(validAttachment.value),
    reason: "Server proof attachment document and Storage proof file match the signed-in user and upload receipt."
  };
}

function baseCandidateForValidAttachment(
  attachment: ValidAttachment,
  storageGeneration: string | undefined
): Pick<
  PrivateEvidenceRetentionCandidate,
  "attachmentID" | "proofID" | "storagePath" | "storageGeneration" | "deleted"
> {
  const candidate: Pick<
    PrivateEvidenceRetentionCandidate,
    "attachmentID" | "proofID" | "storagePath" | "storageGeneration" | "deleted"
  > = {
    attachmentID: attachment.attachmentID,
    proofID: attachment.proofID,
    storagePath: attachment.storagePath,
    deleted: false
  };
  if (storageGeneration !== undefined) {
    candidate.storageGeneration = storageGeneration;
  }

  return candidate;
}

async function deleteCandidate(
  userID: string,
  candidate: EvaluatedRetentionCandidate,
  dependencies: PrivateEvidenceRetentionDependencies
): Promise<EvaluatedRetentionCandidate> {
  if (!candidate.deletePrecondition) {
    return {
      ...candidate,
      status: "firestoreReceiptMismatch",
      canDelete: false,
      deleted: false,
      reason: "Proof attachment cleanup was missing a verified delete precondition."
    };
  }

  const firestoreDeleted = await dependencies.deleteProofAttachmentDocument(
    userID,
    candidate.attachmentID,
    candidate.deletePrecondition
  );
  if (!firestoreDeleted) {
    return {
      ...candidate,
      status: "firestoreDeleteFailed",
      canDelete: false,
      deleted: false,
      reason: "Server proof attachment document changed or could not be deleted, so the Storage proof file was left untouched."
    };
  }

  if (candidate.status !== "storageObjectMissing") {
    const storageDeleted = await dependencies.deleteStorageObjectGeneration(
      candidate.storagePath,
      candidate.storageGeneration
    );
    if (!storageDeleted) {
      return {
        ...candidate,
        status: "storageDeleteFailed",
        canDelete: false,
        deleted: false,
        reason: "Server proof attachment document was removed, but the Storage proof file changed or could not be deleted with generation matching."
      };
    }
  }

  return {
    ...candidate,
    status: "deleted",
    canDelete: false,
    deleted: true,
    reason: candidate.status === "storageObjectMissing"
      ? "Removed the remaining server proof attachment document; Storage proof file was already missing."
      : "Removed the matching server proof attachment document and Storage proof file."
  };
}

function wasEligibleForCleanup(candidate: PrivateEvidenceRetentionCandidate): boolean {
  return candidate.canDelete ||
    candidate.deleted ||
    candidate.status === "storageDeleteFailed" ||
    candidate.status === "firestoreDeleteFailed";
}

function publicCandidate(candidate: EvaluatedRetentionCandidate): PrivateEvidenceRetentionCandidate {
  const { deletePrecondition, ...safeCandidate } = candidate;
  void deletePrecondition;
  return safeCandidate;
}

function parseUploadedAttachmentDocument(
  userID: string,
  attachmentID: string,
  data: Record<string, unknown>
): { ok: true; value: ValidAttachment } | { ok: false; reason: string } {
  const expectedStoragePath = `users/${userID}/proofAttachments/${attachmentID}`;
  const metadata = isRecord(data.metadata) ? data.metadata : {};
  const receipt = isRecord(data.uploadReceipt) ? data.uploadReceipt : null;
  const proofID = typeof data.proofID === "string" ? data.proofID : "";
  const contentType = typeof data.contentType === "string" ? data.contentType : "";
  const byteCount = typeof data.byteCount === "number" && Number.isInteger(data.byteCount)
    ? data.byteCount
    : null;

  if (
    data.uploadStatus !== "uploaded" ||
    data.storagePath !== expectedStoragePath ||
    data.collectionPath !== `users/${userID}/proofAttachments` ||
    data.documentPath !== expectedStoragePath ||
    metadata.ownerUserID !== userID ||
    metadata.localID !== attachmentID ||
    proofID.length === 0 ||
    !receipt ||
    byteCount === null
  ) {
    return { ok: false, reason: "Firestore proof attachment is not a matching uploaded private evidence receipt." };
  }

  const idempotencyKey = `${userID}-${attachmentID}`;
  const receiptGeneration = receipt.storageGeneration;
  if (
    receipt.status !== "uploaded" ||
    receipt.proofID !== proofID ||
    receipt.attachmentID !== attachmentID ||
    receipt.storagePath !== expectedStoragePath ||
    receipt.contentType !== contentType ||
    receipt.byteCount !== byteCount ||
    receipt.idempotencyKey !== idempotencyKey ||
    typeof receiptGeneration !== "number" ||
    !Number.isFinite(receiptGeneration)
  ) {
    return { ok: false, reason: "Firestore upload receipt does not match the expected owner, proof, and file data." };
  }

  return {
    ok: true,
    value: {
      attachmentID,
      proofID,
      storagePath: expectedStoragePath,
      contentType,
      byteCount,
      idempotencyKey,
      storageGeneration: String(receiptGeneration)
    }
  };
}

function validateStorageObject(
  userID: string,
  attachment: ValidAttachment,
  storageObject: PrivateEvidenceRetentionStorageObject
): { ok: true } | { ok: false; status: "storageMetadataMismatch"; reason: string } {
  const size = typeof storageObject.size === "number"
    ? storageObject.size
    : Number.parseInt(String(storageObject.size ?? ""), 10);
  const metadata = storageObject.metadata ?? {};

  if (
    storageObject.name !== attachment.storagePath ||
    storageObject.generation === undefined ||
    storageObject.contentType !== attachment.contentType ||
    size !== attachment.byteCount ||
    metadata.ownerUserID !== userID ||
    metadata.proofID !== attachment.proofID ||
    metadata.attachmentID !== attachment.attachmentID ||
    metadata.idempotencyKey !== attachment.idempotencyKey
  ) {
    return {
      ok: false,
      status: "storageMetadataMismatch",
      reason: "Storage proof file no longer matches the server proof attachment receipt."
    };
  }

  if (attachment.storageGeneration && storageObject.generation !== attachment.storageGeneration) {
    return {
      ok: false,
      status: "storageMetadataMismatch",
      reason: "Storage proof file generation changed after the server upload receipt was written."
    };
  }

  return { ok: true };
}

function deletePreconditionFromValidAttachment(
  attachment: ValidAttachment
): PrivateEvidenceRetentionAttachmentDeletePrecondition {
  return {
    proofID: attachment.proofID,
    storagePath: attachment.storagePath,
    contentType: attachment.contentType,
    byteCount: attachment.byteCount,
    idempotencyKey: attachment.idempotencyKey,
    storageGeneration: attachment.storageGeneration
  };
}

function deletePreconditionsMatch(
  current: ValidAttachment,
  expected: PrivateEvidenceRetentionAttachmentDeletePrecondition
): boolean {
  return current.proofID === expected.proofID &&
    current.storagePath === expected.storagePath &&
    current.contentType === expected.contentType &&
    current.byteCount === expected.byteCount &&
    current.idempotencyKey === expected.idempotencyKey &&
    current.storageGeneration === expected.storageGeneration;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function adminPrivateEvidenceRetentionDependencies(
  quotaGuard?: CallableQuotaGuard
): PrivateEvidenceRetentionDependencies {
  return {
    async readPrivateEvidenceCloudSyncConsent(userID) {
      const snapshot = await getFirestore()
        .doc(`users/${userID}/consents/privateEvidenceCloudSync`)
        .get();
      return snapshot.exists ? snapshot.data() ?? null : null;
    },
    async listProofAttachments(userID, attachmentIDs, maxAttachments) {
      if (attachmentIDs && attachmentIDs.length > 0) {
        const snapshots = await Promise.all(
          attachmentIDs.slice(0, maxAttachments).map(async (attachmentID) => {
            const snapshot = await getFirestore()
              .doc(`users/${userID}/proofAttachments/${attachmentID}`)
              .get();
            const data = snapshot.data();
            return snapshot.exists && data
              ? { exists: true as const, attachmentID, data }
              : { exists: false as const, attachmentID };
          })
        );
        return snapshots;
      }

      const snapshot = await getFirestore()
        .collection(`users/${userID}/proofAttachments`)
        .limit(maxAttachments)
        .get();
      return snapshot.docs.map((document) => ({
        exists: true as const,
        attachmentID: document.id,
        data: document.data()
      }));
    },
    readStorageObject,
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
    },
    async deleteProofAttachmentDocument(userID, attachmentID, precondition) {
      try {
        const firestore = getFirestore();
        const reference = firestore.doc(`users/${userID}/proofAttachments/${attachmentID}`);
        return await firestore.runTransaction(async (transaction) => {
          const snapshot = await transaction.get(reference);
          const data = snapshot.data();
          if (!snapshot.exists || !data) {
            return false;
          }

          const current = parseUploadedAttachmentDocument(userID, attachmentID, data);
          if (!current.ok || !deletePreconditionsMatch(current.value, precondition)) {
            return false;
          }

          transaction.delete(reference);
          return true;
        });
      } catch {
        return false;
      }
    },
    ...(quotaGuard ? { quotaGuard } : {})
  };
}

async function readStorageObject(storagePath: string): Promise<PrivateEvidenceRetentionStorageObject | null> {
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
    generation: metadata.generation === undefined ? undefined : String(metadata.generation),
    metadata: metadata.metadata as Record<string, string | undefined> | undefined
  };
}
