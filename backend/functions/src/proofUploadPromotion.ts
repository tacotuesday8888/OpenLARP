import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { type CallableQuotaGuard } from "./callableQuotaGuard.js";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPProofUploadPromotionAuth = {
  uid: string;
};

export type OpenLARPProofUploadPromotionRequest = {
  auth?: OpenLARPProofUploadPromotionAuth | null;
  data: unknown;
};

export type ProofUploadPromotionIntent = {
  schemaVersion: 1;
  proofID: string;
  attachmentID: string;
  fileName: string;
  contentType: string;
  byteCount: number;
  storagePath: string;
  proofDocumentPath: string;
  attachmentDocumentPath: string;
  idempotencyKey: string;
};

export type ProofUploadPromotionStorageObject = {
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

export type ProofUploadPromotionReceipt = {
  schemaVersion: 1;
  proofID: string;
  attachmentID: string;
  storagePath: string;
  contentType: string;
  byteCount: number;
  status: "uploaded";
  uploadedAt?: string;
  storageBucket?: string;
  storageGeneration?: number;
  metadataGeneration?: number;
  md5Hash?: string;
  idempotencyKey: string;
};

export type ProofUploadPromotionSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  promotedAt: string;
  firestoreDocumentPath: string;
  uploadReceipt: ProofUploadPromotionReceipt;
  externalActionTaken: false;
};

export type ProofUploadPromotionResponse =
  | ProofUploadPromotionSuccess
  | OpenLARPFunctionError;

export type ProofUploadPromotionDependencies = {
  readPrivateEvidenceCloudSyncConsent: (userID: string) => Promise<boolean>;
  readStorageObject: (storagePath: string) => Promise<ProofUploadPromotionStorageObject | null>;
  writeProofAttachmentDocument: (
    userID: string,
    attachmentID: string,
    document: Record<string, unknown>
  ) => Promise<void>;
  quotaGuard?: CallableQuotaGuard;
  now?: () => Date;
};

const ALLOWED_CONTENT_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/heic",
  "image/heif",
  "application/pdf",
  "text/plain"
]);
const MAX_PROOF_UPLOAD_BYTES = 10 * 1024 * 1024;
const PRIVATE_EVIDENCE_CONSENT_TEXT_VERSION = "private-evidence-cloud-sync-v1";
const FIREBASE_MANAGED_STORAGE_METADATA_KEYS = new Set([
  "firebaseStorageDownloadTokens"
]);

export async function handleProofUploadPromotionRequest(
  request: OpenLARPProofUploadPromotionRequest,
  dependencies: ProofUploadPromotionDependencies = adminProofUploadPromotionDependencies()
): Promise<ProofUploadPromotionResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before promoting proof upload receipts.");
  }

  const parsed = parsePromotionIntent(userID, request.data);
  if (!parsed.ok) {
    return parsed.error;
  }

  const promotedAtDate = dependencies.now?.() ?? new Date();
  const hasPrivateEvidenceConsent = await dependencies.readPrivateEvidenceCloudSyncConsent(userID);
  if (!hasPrivateEvidenceConsent) {
    return functionError(
      "permission-denied",
      "Private evidence cloud sync consent is required before proof upload receipts can be promoted."
    );
  }

  const quotaDecision = await dependencies.quotaGuard?.checkAndRecord({
    userID,
    callable: "promoteProofUploadReceipt",
    category: "proofUpload",
    units: 1,
    auditKey: parsed.value.idempotencyKey,
    occurredAt: promotedAtDate,
    metadata: {
      contentType: parsed.value.contentType,
      byteCount: parsed.value.byteCount
    }
  });
  if (quotaDecision && !quotaDecision.ok) {
    return quotaDecision.error;
  }

  const storageObject = await dependencies.readStorageObject(parsed.value.storagePath);
  if (!storageObject) {
    return functionError("not-found", "The uploaded proof attachment was not found in Firebase Storage.");
  }

  const storageValidation = validateStorageObject(userID, parsed.value, storageObject);
  if (!storageValidation.ok) {
    return storageValidation.error;
  }

  const promotedAt = promotedAtDate.toISOString();
  const uploadReceipt = receiptFromStorageObject(parsed.value, storageObject);
  const document = proofAttachmentDocument(userID, parsed.value, uploadReceipt, promotedAtDate);
  await dependencies.writeProofAttachmentDocument(userID, parsed.value.attachmentID, document);

  return {
    ok: true,
    schemaVersion: 1,
    userID,
    promotedAt,
    firestoreDocumentPath: parsed.value.attachmentDocumentPath,
    uploadReceipt,
    externalActionTaken: false
  };
}

function parsePromotionIntent(
  userID: string,
  data: unknown
): { ok: true; value: ProofUploadPromotionIntent } | { ok: false; error: OpenLARPFunctionError } {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return {
      ok: false,
      error: functionError("invalid-argument", "Proof upload promotion request must be an object.")
    };
  }

  const record = data as Record<string, unknown>;
  const proofID = parseID(record.proofID, "proofID");
  const attachmentID = parseID(record.attachmentID, "attachmentID");
  const fileName = parseFileName(record.fileName);
  const contentType = parseContentType(record.contentType);
  const byteCount = parseByteCount(record.byteCount);
  const schemaVersion = record.schemaVersion === undefined ? 1 : record.schemaVersion;

  if (schemaVersion !== 1) {
    return invalid("schemaVersion must be 1.");
  }
  if (!proofID.ok) {
    return proofID;
  }
  if (!attachmentID.ok) {
    return attachmentID;
  }
  if (!fileName.ok) {
    return fileName;
  }
  if (!contentType.ok) {
    return contentType;
  }
  if (!byteCount.ok) {
    return byteCount;
  }

  const expectedStoragePath = `users/${userID}/proofAttachments/${attachmentID.value}`;
  const expectedProofDocumentPath = `users/${userID}/proofRecords/${proofID.value}`;
  const expectedAttachmentDocumentPath = expectedStoragePath;
  const expectedIdempotencyKey = `${userID}-${attachmentID.value}`;

  if (record.storagePath !== expectedStoragePath) {
    return invalid("storagePath must match the signed-in user's proof attachment path.");
  }
  if (record.proofDocumentPath !== expectedProofDocumentPath) {
    return invalid("proofDocumentPath must match the signed-in user's proof record path.");
  }
  if (record.attachmentDocumentPath !== expectedAttachmentDocumentPath) {
    return invalid("attachmentDocumentPath must match the signed-in user's proof attachment document path.");
  }
  if (record.idempotencyKey !== expectedIdempotencyKey) {
    return invalid("idempotencyKey must be deterministic for the signed-in user and attachment.");
  }

  return {
    ok: true,
    value: {
      schemaVersion: 1,
      proofID: proofID.value,
      attachmentID: attachmentID.value,
      fileName: fileName.value,
      contentType: contentType.value,
      byteCount: byteCount.value,
      storagePath: expectedStoragePath,
      proofDocumentPath: expectedProofDocumentPath,
      attachmentDocumentPath: expectedAttachmentDocumentPath,
      idempotencyKey: expectedIdempotencyKey
    }
  };
}

function parseID(
  value: unknown,
  fieldName: string
): { ok: true; value: string } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "string") {
    return invalid(`${fieldName} must be a string.`);
  }

  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 128 || trimmed.includes("/")) {
    return invalid(`${fieldName} must be a non-empty ID without path separators.`);
  }

  return { ok: true, value: trimmed };
}

function parseFileName(
  value: unknown
): { ok: true; value: string } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "string") {
    return invalid("fileName must be a string.");
  }

  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 160 || trimmed.includes("/")) {
    return invalid("fileName must be a safe non-empty file name without path separators.");
  }

  return { ok: true, value: trimmed };
}

function parseContentType(
  value: unknown
): { ok: true; value: string } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "string" || !ALLOWED_CONTENT_TYPES.has(value)) {
    return invalid("contentType is not allowed for proof uploads.");
  }

  return { ok: true, value };
}

function parseByteCount(
  value: unknown
): { ok: true; value: number } | { ok: false; error: OpenLARPFunctionError } {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value <= 0 ||
    value >= MAX_PROOF_UPLOAD_BYTES
  ) {
    return invalid(`byteCount must be an integer between 1 and ${MAX_PROOF_UPLOAD_BYTES - 1}.`);
  }

  return { ok: true, value };
}

function validateStorageObject(
  userID: string,
  intent: ProofUploadPromotionIntent,
  storageObject: ProofUploadPromotionStorageObject
): { ok: true } | { ok: false; error: OpenLARPFunctionError } {
  if (storageObject.name !== intent.storagePath) {
    return invalid("Storage object path does not match the promotion request.");
  }
  if (storageObject.contentType !== intent.contentType) {
    return invalid("Storage object content type does not match the promotion request.");
  }
  if (storageObject.size !== intent.byteCount) {
    return invalid("Storage object byte count does not match the promotion request.");
  }

  const metadata = storageObject.metadata ?? {};
  const expectedMetadata: Record<string, string> = {
    ownerUserID: userID,
    proofID: intent.proofID,
    attachmentID: intent.attachmentID,
    idempotencyKey: intent.idempotencyKey
  };
  const metadataKeys = Object.keys(metadata);
  const expectedKeys = Object.keys(expectedMetadata);
  const expectedMetadataKeys = new Set(expectedKeys);
  const unexpectedMetadataKeys = metadataKeys.filter((key) => (
    !expectedMetadataKeys.has(key) && !FIREBASE_MANAGED_STORAGE_METADATA_KEYS.has(key)
  ));
  if (
    unexpectedMetadataKeys.length > 0 ||
    !expectedKeys.every((key) => metadata[key] === expectedMetadata[key])
  ) {
    return invalid("Storage object custom metadata does not match the signed-in user and upload intent.");
  }

  return { ok: true };
}

function receiptFromStorageObject(
  intent: ProofUploadPromotionIntent,
  storageObject: ProofUploadPromotionStorageObject
): ProofUploadPromotionReceipt {
  const receipt: ProofUploadPromotionReceipt = {
    schemaVersion: 1,
    proofID: intent.proofID,
    attachmentID: intent.attachmentID,
    storagePath: intent.storagePath,
    contentType: intent.contentType,
    byteCount: intent.byteCount,
    status: "uploaded",
    idempotencyKey: intent.idempotencyKey
  };
  if (storageObject.updatedAt) {
    receipt.uploadedAt = storageObject.updatedAt;
  }
  if (storageObject.bucket) {
    receipt.storageBucket = storageObject.bucket;
  }
  const storageGeneration = parseIntOrUndefined(storageObject.generation);
  if (storageGeneration !== undefined) {
    receipt.storageGeneration = storageGeneration;
  }
  const metadataGeneration = parseIntOrUndefined(storageObject.metageneration);
  if (metadataGeneration !== undefined) {
    receipt.metadataGeneration = metadataGeneration;
  }
  if (storageObject.md5Hash) {
    receipt.md5Hash = storageObject.md5Hash;
  }
  return receipt;
}

function proofAttachmentDocument(
  userID: string,
  intent: ProofUploadPromotionIntent,
  uploadReceipt: ProofUploadPromotionReceipt,
  promotedAt: Date
): Record<string, unknown> {
  const promotedAtTimestamp = Timestamp.fromDate(promotedAt);
  const uploadedAt = uploadReceipt.uploadedAt ? new Date(uploadReceipt.uploadedAt) : null;
  const receiptDocument: Record<string, unknown> = { ...uploadReceipt };
  if (uploadedAt && Number.isFinite(uploadedAt.getTime())) {
    receiptDocument.uploadedAt = Timestamp.fromDate(uploadedAt);
  }

  return {
    metadata: {
      schemaVersion: 1,
      ownerUserID: userID,
      localID: intent.attachmentID,
      createdAt: promotedAtTimestamp,
      updatedAt: promotedAtTimestamp
    },
    proofID: intent.proofID,
    fileName: intent.fileName,
    originalFileName: intent.fileName,
    contentType: intent.contentType,
    byteCount: intent.byteCount,
    createdAt: promotedAtTimestamp,
    storagePath: intent.storagePath,
    uploadStatus: "uploaded",
    uploadReceipt: receiptDocument,
    collectionPath: `users/${userID}/proofAttachments`,
    documentPath: intent.attachmentDocumentPath
  };
}

function invalid(message: string): { ok: false; error: OpenLARPFunctionError } {
  return {
    ok: false,
    error: functionError("invalid-argument", message)
  };
}

export function adminProofUploadPromotionDependencies(
  quotaGuard?: CallableQuotaGuard
): ProofUploadPromotionDependencies {
  return {
    readPrivateEvidenceCloudSyncConsent,
    readStorageObject,
    async writeProofAttachmentDocument(userID, attachmentID, document) {
      await getFirestore()
        .doc(`users/${userID}/proofAttachments/${attachmentID}`)
        .set(document, { merge: false });
    },
    ...(quotaGuard ? { quotaGuard } : {})
  };
}

async function readPrivateEvidenceCloudSyncConsent(userID: string): Promise<boolean> {
  const snapshot = await getFirestore()
    .doc(`users/${userID}/consents/privateEvidenceCloudSync`)
    .get();
  if (!snapshot.exists) {
    return false;
  }

  return isAcceptedPrivateEvidenceCloudSyncConsentDocument(userID, snapshot.data());
}

export function isAcceptedPrivateEvidenceCloudSyncConsentDocument(
  userID: string,
  data: Record<string, unknown> | undefined
): boolean {
  return data?.schemaVersion === 1
    && data?.ownerUserID === userID
    && data?.status === "accepted"
    && data?.allowsPrivateEvidenceCloudSync === true
    && data?.consentTextVersion === PRIVATE_EVIDENCE_CONSENT_TEXT_VERSION;
}

async function readStorageObject(storagePath: string): Promise<ProofUploadPromotionStorageObject | null> {
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

  if (value instanceof Date) {
    return value.toISOString();
  }

  return undefined;
}

function parseIntOrUndefined(value: string | undefined): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}
