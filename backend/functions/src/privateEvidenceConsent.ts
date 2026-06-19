import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPPrivateEvidenceConsentAuth = {
  uid: string;
};

export type OpenLARPPrivateEvidenceConsentRequest = {
  auth?: OpenLARPPrivateEvidenceConsentAuth | null;
  data: unknown;
};

export type PrivateEvidenceCloudSyncConsentStatus = "accepted" | "revoked";

export type PrivateEvidenceCloudSyncConsentSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  status: PrivateEvidenceCloudSyncConsentStatus;
  allowsPrivateEvidenceCloudSync: boolean;
  consentTextVersion: string;
  firestoreDocumentPath: string;
  updatedAt: string;
  externalActionTaken: false;
};

export type PrivateEvidenceCloudSyncConsentResponse =
  | PrivateEvidenceCloudSyncConsentSuccess
  | OpenLARPFunctionError;

export type PrivateEvidenceCloudSyncConsentDependencies = {
  readConsentDocument?: (userID: string) => Promise<Record<string, unknown> | null>;
  writeConsentDocument: (
    userID: string,
    document: Record<string, unknown>
  ) => Promise<void>;
  now?: () => Date;
};

const CONSENT_TEXT_VERSION = "private-evidence-cloud-sync-v1";

export async function handlePrivateEvidenceCloudSyncConsentRequest(
  request: OpenLARPPrivateEvidenceConsentRequest,
  dependencies: PrivateEvidenceCloudSyncConsentDependencies = adminPrivateEvidenceCloudSyncConsentDependencies()
): Promise<PrivateEvidenceCloudSyncConsentResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before changing private evidence cloud sync consent.");
  }

  const parsed = parseConsentRequest(request.data);
  if (!parsed.ok) {
    return parsed.error;
  }

  const updatedAtDate = dependencies.now?.() ?? new Date();
  const updatedAt = updatedAtDate.toISOString();
  const status: PrivateEvidenceCloudSyncConsentStatus = parsed.enabled ? "accepted" : "revoked";
  const documentPath = `users/${userID}/consents/privateEvidenceCloudSync`;
  const currentDocument = await dependencies.readConsentDocument?.(userID);
  if (isMatchingConsentDocument(userID, currentDocument, status, parsed.enabled)) {
    return {
      ok: true,
      schemaVersion: 1,
      userID,
      status,
      allowsPrivateEvidenceCloudSync: parsed.enabled,
      consentTextVersion: CONSENT_TEXT_VERSION,
      firestoreDocumentPath: documentPath,
      updatedAt,
      externalActionTaken: false
    };
  }

  const timestamp = Timestamp.fromDate(updatedAtDate);
  const document: Record<string, unknown> = {
    schemaVersion: 1,
    ownerUserID: userID,
    status,
    allowsPrivateEvidenceCloudSync: parsed.enabled,
    consentTextVersion: CONSENT_TEXT_VERSION,
    collectionPath: `users/${userID}/consents`,
    documentPath,
    updatedAt: timestamp
  };
  if (parsed.enabled) {
    document.acceptedAt = timestamp;
  } else {
    document.revokedAt = timestamp;
  }

  await dependencies.writeConsentDocument(userID, document);

  return {
    ok: true,
    schemaVersion: 1,
    userID,
    status,
    allowsPrivateEvidenceCloudSync: parsed.enabled,
    consentTextVersion: CONSENT_TEXT_VERSION,
    firestoreDocumentPath: documentPath,
    updatedAt,
    externalActionTaken: false
  };
}

function parseConsentRequest(
  data: unknown
): { ok: true; enabled: boolean; consentTextVersion: string } | { ok: false; error: OpenLARPFunctionError } {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return invalid("Private evidence consent request must be an object.");
  }

  const record = data as Record<string, unknown>;
  const schemaVersion = record.schemaVersion === undefined ? 1 : record.schemaVersion;
  if (schemaVersion !== 1) {
    return invalid("schemaVersion must be 1.");
  }
  if (typeof record.enabled !== "boolean") {
    return invalid("enabled must be a boolean.");
  }

  const consentTextVersion = typeof record.consentTextVersion === "string"
    ? record.consentTextVersion.trim()
    : CONSENT_TEXT_VERSION;
  if (consentTextVersion !== CONSENT_TEXT_VERSION) {
    return invalid("consentTextVersion is not supported.");
  }

  return {
    ok: true,
    enabled: record.enabled,
    consentTextVersion
  };
}

function invalid(message: string): { ok: false; error: OpenLARPFunctionError } {
  return {
    ok: false,
    error: functionError("invalid-argument", message)
  };
}

function isMatchingConsentDocument(
  userID: string,
  document: Record<string, unknown> | null | undefined,
  status: PrivateEvidenceCloudSyncConsentStatus,
  allowsPrivateEvidenceCloudSync: boolean
): boolean {
  return document?.schemaVersion === 1
    && document?.ownerUserID === userID
    && document?.status === status
    && document?.allowsPrivateEvidenceCloudSync === allowsPrivateEvidenceCloudSync
    && document?.consentTextVersion === CONSENT_TEXT_VERSION;
}

export function adminPrivateEvidenceCloudSyncConsentDependencies(): PrivateEvidenceCloudSyncConsentDependencies {
  return {
    async readConsentDocument(userID) {
      const snapshot = await getFirestore()
        .doc(`users/${userID}/consents/privateEvidenceCloudSync`)
        .get();
      return snapshot.exists ? snapshot.data() ?? null : null;
    },
    async writeConsentDocument(userID, document) {
      await getFirestore()
        .doc(`users/${userID}/consents/privateEvidenceCloudSync`)
        .set(document, { merge: false });
    }
  };
}
