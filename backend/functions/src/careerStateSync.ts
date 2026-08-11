import { createHash } from "node:crypto";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { functionError, type OpenLARPFunctionError } from "./errors.js";
import { type CallableQuotaGuard } from "./callableQuotaGuard.js";
import {
  accountDeletionBlockedError,
  accountDeletionRequestPath,
  isBlockingAccountDeletionRequest
} from "./accountDeletionGuard.js";

type CareerStateSyncAction = "reconcile" | "keepLocal" | "useCloud";
type CareerStateSyncStatus = "noData" | "uploaded" | "restored" | "inSync" | "conflict";

export type CareerStateCloudPayload = {
  schemaVersion: 1;
  includesPrivateEvidence: boolean;
  state: Record<string, unknown>;
};

export type CareerStateSnapshot = {
  schemaVersion: 1;
  ownerUserID: string;
  revision: number;
  payloadHash: string;
  payload: CareerStateCloudPayload;
  createdAt: Date;
  updatedAt: Date;
};

type ParsedCareerStateSyncInput = {
  schemaVersion: 1;
  action: CareerStateSyncAction;
  requestedAt: Date;
  hasMeaningfulLocalData: boolean;
  expectedRevision?: number;
  basePayloadHash?: string;
  payload: CareerStateCloudPayload;
  payloadHash: string;
};

export type CareerStateSyncSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  status: CareerStateSyncStatus;
  revision: number;
  payloadHash?: string;
  cloudPayload?: CareerStateCloudPayload;
  serverUpdatedAt?: string;
  completedAt: string;
  didWrite: boolean;
  externalActionTaken: false;
};

export type CareerStateSyncResponse = CareerStateSyncSuccess | OpenLARPFunctionError;

type CareerStateSyncDecision = {
  response: CareerStateSyncResponse;
  snapshotToWrite?: CareerStateSnapshot;
};

export type CareerStateSyncDependencies = {
  reconcileSnapshot: (
    userID: string,
    input: {
      decide: (existing: CareerStateSnapshot | null, hasPrivateEvidenceConsent: boolean) => CareerStateSyncDecision;
    }
  ) => Promise<CareerStateSyncResponse>;
  quotaGuard?: CallableQuotaGuard;
  now?: () => Date;
};

export type OpenLARPCareerStateSyncRequest = {
  auth?: { uid: string } | null;
  data: unknown;
};

const MAX_PAYLOAD_BYTES = 700_000;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const ACTIONS = new Set<CareerStateSyncAction>(["reconcile", "keepLocal", "useCloud"]);
const REQUEST_KEYS = new Set([
  "schemaVersion",
  "action",
  "requestedAt",
  "hasMeaningfulLocalData",
  "expectedRevision",
  "basePayloadHash",
  "payload"
]);

export async function handleCareerStateSyncRequest(
  request: OpenLARPCareerStateSyncRequest,
  dependencies: CareerStateSyncDependencies = adminCareerStateSyncDependencies()
): Promise<CareerStateSyncResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before syncing OpenLARP career state.");
  }

  const parsed = parseRequest(request.data);
  if (!parsed.ok) {
    return parsed.error;
  }
  const now = dependencies.now?.() ?? new Date();
  const quotaDecision = await dependencies.quotaGuard?.checkAndRecord({
    userID,
    callable: "syncOpenLARPCareerState",
    category: "careerStateSync",
    units: 1,
    occurredAt: now,
    auditKey: parsed.value.payloadHash,
    metadata: {
      action: parsed.value.action,
      hasMeaningfulLocalData: parsed.value.hasMeaningfulLocalData,
      includesPrivateEvidence: parsed.value.payload.includesPrivateEvidence
    }
  });
  if (quotaDecision && !quotaDecision.ok) {
    return quotaDecision.error;
  }

  try {
    return await dependencies.reconcileSnapshot(userID, {
      decide(existing, hasPrivateEvidenceConsent) {
        return decideCareerStateSync(userID, parsed.value, existing, hasPrivateEvidenceConsent, now);
      }
    });
  } catch (error) {
    return functionError("internal", "OpenLARP career state could not be synced safely.", {
      errorMessage: safeErrorMessage(error)
    });
  }
}

function decideCareerStateSync(
  userID: string,
  input: ParsedCareerStateSyncInput,
  existing: CareerStateSnapshot | null,
  hasPrivateEvidenceConsent: boolean,
  now: Date
): CareerStateSyncDecision {
  if (input.payload.includesPrivateEvidence && !hasPrivateEvidenceConsent) {
    return {
      response: functionError(
        "failed-precondition",
        "Turn on private evidence cloud sync before backing up proof receipts or private outcomes."
      )
    };
  }
  if (existing?.payload.includesPrivateEvidence &&
      !hasPrivateEvidenceConsent &&
      (input.action === "useCloud" ||
        !input.hasMeaningfulLocalData ||
        input.expectedRevision !== existing.revision)) {
    return {
      response: functionError(
        "failed-precondition",
        "A private-evidence snapshot cannot be restored after consent is revoked. Sync the device that revoked consent to replace it with a redacted copy."
      )
    };
  }

  if (input.action === "useCloud") {
    return existing
      ? { response: success(userID, "restored", existing, now, false, true) }
      : { response: noData(userID, now) };
  }

  if (!existing) {
    if (!input.hasMeaningfulLocalData) {
      return { response: noData(userID, now) };
    }
    if (input.action === "keepLocal" && (input.expectedRevision ?? 0) !== 0) {
      return { response: noData(userID, now) };
    }
    const snapshot = makeSnapshot(userID, 1, input, now);
    return {
      response: success(userID, "uploaded", snapshot, now, true, false),
      snapshotToWrite: snapshot
    };
  }

  if (input.action === "keepLocal") {
    if (!input.hasMeaningfulLocalData || input.expectedRevision !== existing.revision) {
      return { response: success(userID, "conflict", existing, now, false, true) };
    }
    const snapshot = makeSnapshot(userID, existing.revision + 1, input, now, existing.createdAt);
    return {
      response: success(userID, "uploaded", snapshot, now, true, false),
      snapshotToWrite: snapshot
    };
  }

  if (!input.hasMeaningfulLocalData) {
    return { response: success(userID, "restored", existing, now, false, true) };
  }
  if (input.payloadHash === existing.payloadHash) {
    return { response: success(userID, "inSync", existing, now, false, false) };
  }
  if (input.expectedRevision === undefined) {
    return { response: success(userID, "conflict", existing, now, false, true) };
  }
  if (input.expectedRevision === existing.revision) {
    const snapshot = makeSnapshot(userID, existing.revision + 1, input, now, existing.createdAt);
    return {
      response: success(userID, "uploaded", snapshot, now, true, false),
      snapshotToWrite: snapshot
    };
  }
  if (input.expectedRevision > existing.revision) {
    return { response: success(userID, "conflict", existing, now, false, true) };
  }
  if (input.basePayloadHash && input.payloadHash === input.basePayloadHash) {
    return { response: success(userID, "restored", existing, now, false, true) };
  }
  if (input.basePayloadHash && existing.payloadHash === input.basePayloadHash) {
    const snapshot = makeSnapshot(userID, existing.revision + 1, input, now, existing.createdAt);
    return {
      response: success(userID, "uploaded", snapshot, now, true, false),
      snapshotToWrite: snapshot
    };
  }
  return { response: success(userID, "conflict", existing, now, false, true) };
}

function makeSnapshot(
  userID: string,
  revision: number,
  input: ParsedCareerStateSyncInput,
  now: Date,
  createdAt: Date = now
): CareerStateSnapshot {
  return {
    schemaVersion: 1,
    ownerUserID: userID,
    revision,
    payloadHash: input.payloadHash,
    payload: input.payload,
    createdAt,
    updatedAt: now
  };
}

function success(
  userID: string,
  status: Exclude<CareerStateSyncStatus, "noData">,
  snapshot: CareerStateSnapshot,
  completedAt: Date,
  didWrite: boolean,
  includesCloudPayload: boolean
): CareerStateSyncSuccess {
  return {
    ok: true,
    schemaVersion: 1,
    userID,
    status,
    revision: snapshot.revision,
    payloadHash: snapshot.payloadHash,
    ...(includesCloudPayload ? { cloudPayload: snapshot.payload } : {}),
    serverUpdatedAt: snapshot.updatedAt.toISOString(),
    completedAt: completedAt.toISOString(),
    didWrite,
    externalActionTaken: false
  };
}

function noData(userID: string, completedAt: Date): CareerStateSyncSuccess {
  return {
    ok: true,
    schemaVersion: 1,
    userID,
    status: "noData",
    revision: 0,
    completedAt: completedAt.toISOString(),
    didWrite: false,
    externalActionTaken: false
  };
}

function parseRequest(
  data: unknown
): { ok: true; value: ParsedCareerStateSyncInput } | { ok: false; error: OpenLARPFunctionError } {
  if (!isPlainObject(data)) {
    return invalid("Career state sync request must be an object.");
  }
  const unknownKeys = Object.keys(data).filter((key) => !REQUEST_KEYS.has(key));
  if (unknownKeys.length > 0) {
    return invalid("Career state sync request contains unsupported fields.");
  }
  if (data.schemaVersion !== 1) {
    return invalid("schemaVersion must be 1.");
  }
  if (typeof data.action !== "string" || !ACTIONS.has(data.action as CareerStateSyncAction)) {
    return invalid("action must be reconcile, keepLocal, or useCloud.");
  }
  const requestedAt = parseDate(data.requestedAt);
  if (!requestedAt) {
    return invalid("requestedAt must be a valid ISO-8601 timestamp.");
  }
  if (typeof data.hasMeaningfulLocalData !== "boolean") {
    return invalid("hasMeaningfulLocalData must be a boolean.");
  }
  if (data.expectedRevision !== undefined && !isRevision(data.expectedRevision)) {
    return invalid("expectedRevision must be a non-negative integer.");
  }
  if (data.basePayloadHash !== undefined &&
      (typeof data.basePayloadHash !== "string" || !HASH_PATTERN.test(data.basePayloadHash))) {
    return invalid("basePayloadHash must be a lowercase SHA-256 hash.");
  }
  const parsedPayload = parsePayload(data.payload);
  if (!parsedPayload.ok) {
    return parsedPayload;
  }

  const value: ParsedCareerStateSyncInput = {
    schemaVersion: 1,
    action: data.action as CareerStateSyncAction,
    requestedAt,
    hasMeaningfulLocalData: data.hasMeaningfulLocalData,
    payload: parsedPayload.value,
    payloadHash: hashCareerStatePayload(parsedPayload.value)
  };
  if (data.expectedRevision !== undefined) {
    value.expectedRevision = data.expectedRevision as number;
  }
  if (data.basePayloadHash !== undefined) {
    value.basePayloadHash = data.basePayloadHash as string;
  }
  return {
    ok: true,
    value
  };
}

function parsePayload(
  value: unknown
): { ok: true; value: CareerStateCloudPayload } | { ok: false; error: OpenLARPFunctionError } {
  if (!isPlainObject(value) ||
      value.schemaVersion !== 1 ||
      typeof value.includesPrivateEvidence !== "boolean" ||
      !isPlainObject(value.state) ||
      Object.keys(value).some((key) => !["schemaVersion", "includesPrivateEvidence", "state"].includes(key))) {
    return invalid("payload must match career state cloud schema 1.");
  }
  if (!isJSONValue(value)) {
    return invalid("payload contains an unsupported value.");
  }
  const stateValidationError = validateStatePayload(value as CareerStateCloudPayload);
  if (stateValidationError) {
    return invalid(stateValidationError);
  }
  const byteCount = Buffer.byteLength(stableJSONString(value), "utf8");
  if (byteCount > MAX_PAYLOAD_BYTES) {
    return invalid(`payload must not exceed ${MAX_PAYLOAD_BYTES} bytes.`);
  }
  return { ok: true, value: value as CareerStateCloudPayload };
}

function validateStatePayload(payload: CareerStateCloudPayload): string | null {
  const state = payload.state;
  if (state.schemaVersion !== 16) {
    return "payload state schemaVersion must be 16.";
  }
  if (!isPlainObject(state.progress) || !Array.isArray(state.progress.recentProof) ||
      !Array.isArray(state.outcomeLog)) {
    return "payload state must include progress receipts and an outcome log.";
  }
  for (const key of ["betaEvents", "aiWorkflowRuns", "backendEvents"] as const) {
    if (!Array.isArray(state[key]) || state[key].length !== 0) {
      return `payload state ${key} must remain on-device.`;
    }
  }
  if (hasKeyNamed(payload, "localRelativePath")) {
    return "payload must not contain local file paths.";
  }
  const profile = state.userProfile;
  if (profile !== null && profile !== undefined) {
    if (!isPlainObject(profile) ||
        (profile.accountID !== null && profile.accountID !== undefined) ||
        (profile.email !== null && profile.email !== undefined)) {
      return "payload profile must not contain account identifiers or email.";
    }
  }
  if (!isPlainObject(state.questReminders) || state.questReminders.isEnabled !== false) {
    return "payload notification preferences must remain on-device.";
  }
  for (const proof of state.progress.recentProof) {
    if (!isPlainObject(proof) || !Array.isArray(proof.attachments) || proof.attachments.length !== 0) {
      return "payload proof receipts must not embed attachment files or paths.";
    }
  }
  if (!payload.includesPrivateEvidence) {
    if (state.progress.recentProof.length !== 0 || state.outcomeLog.some((outcome) =>
      isPlainObject(outcome) && outcome.isPrivate === true
    )) {
      return "payload includes private evidence without declaring consent.";
    }
  }
  return null;
}

function hasKeyNamed(value: unknown, forbiddenKey: string): boolean {
  if (Array.isArray(value)) return value.some((item) => hasKeyNamed(item, forbiddenKey));
  if (!isPlainObject(value)) return false;
  return Object.keys(value).some((key) => key === forbiddenKey || hasKeyNamed(value[key], forbiddenKey));
}

export function hashCareerStatePayload(payload: CareerStateCloudPayload): string {
  return createHash("sha256").update(stableJSONString(payload)).digest("hex");
}

function stableJSONString(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableJSONString).join(",")}]`;
  }
  if (isPlainObject(value)) {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJSONString(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function isJSONValue(value: unknown, depth = 0): boolean {
  if (depth > 80) return false;
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) return value.length <= 20_000 && value.every((item) => isJSONValue(item, depth + 1));
  if (isPlainObject(value)) {
    const keys = Object.keys(value);
    return keys.length <= 20_000 && keys.every((key) => isJSONValue(value[key], depth + 1));
  }
  return false;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function parseDate(value: unknown): Date | null {
  if (typeof value !== "string") return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function isRevision(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function invalid(message: string): { ok: false; error: OpenLARPFunctionError } {
  return { ok: false, error: functionError("invalid-argument", message) };
}

function safeErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 500) : "Unknown career state sync failure.";
}

type CareerStateFirestore = Pick<Firestore, "doc" | "runTransaction">;

export function adminCareerStateSyncDependencies(
  firestore: CareerStateFirestore = getFirestore()
): CareerStateSyncDependencies {
  return {
    async reconcileSnapshot(userID, input) {
      const snapshotReference = firestore.doc(`users/${userID}/careerState/current`);
      const consentReference = firestore.doc(`users/${userID}/consents/privateEvidenceCloudSync`);
      const deletionReference = firestore.doc(accountDeletionRequestPath(userID));
      return firestore.runTransaction(async (transaction) => {
        const [snapshotDocument, consentDocument, deletionDocument] = await Promise.all([
          transaction.get(snapshotReference),
          transaction.get(consentReference),
          transaction.get(deletionReference)
        ]);
        const deletionData = deletionDocument.data();
        if (deletionDocument.exists && isBlockingAccountDeletionRequest(userID, deletionData)) {
          return accountDeletionBlockedError(deletionData.status);
        }
        const existing = snapshotDocument.exists
          ? decodeStoredSnapshot(snapshotDocument.data(), userID)
          : null;
        const consent = consentDocument.data();
        const hasPrivateEvidenceConsent = consentDocument.exists &&
          consent?.schemaVersion === 1 &&
          consent?.ownerUserID === userID &&
          consent?.status === "accepted" &&
          consent?.allowsPrivateEvidenceCloudSync === true &&
          consent?.consentTextVersion === "private-evidence-cloud-sync-v1";
        const decision = input.decide(existing, hasPrivateEvidenceConsent);
        if (decision.snapshotToWrite) {
          const snapshot = decision.snapshotToWrite;
          transaction.set(snapshotReference, {
            schemaVersion: snapshot.schemaVersion,
            ownerUserID: snapshot.ownerUserID,
            revision: snapshot.revision,
            payloadHash: snapshot.payloadHash,
            payload: snapshot.payload,
            createdAt: Timestamp.fromDate(snapshot.createdAt),
            updatedAt: Timestamp.fromDate(snapshot.updatedAt),
            collectionPath: `users/${userID}/careerState`,
            documentPath: `users/${userID}/careerState/current`
          });
        }
        return decision.response;
      });
    }
  };
}

function decodeStoredSnapshot(data: Record<string, unknown> | undefined, userID: string): CareerStateSnapshot {
  if (!data ||
      data.schemaVersion !== 1 ||
      data.ownerUserID !== userID ||
      !isRevision(data.revision) || data.revision < 1 ||
      typeof data.payloadHash !== "string" || !HASH_PATTERN.test(data.payloadHash)) {
    throw new Error("Stored career state snapshot metadata is invalid.");
  }
  const payload = parsePayload(data.payload);
  const createdAt = timestampDate(data.createdAt);
  const updatedAt = timestampDate(data.updatedAt);
  if (!payload.ok || !createdAt || !updatedAt || hashCareerStatePayload(payload.value) !== data.payloadHash) {
    throw new Error("Stored career state snapshot payload is invalid.");
  }
  return {
    schemaVersion: 1,
    ownerUserID: userID,
    revision: data.revision,
    payloadHash: data.payloadHash,
    payload: payload.value,
    createdAt,
    updatedAt
  };
}

function timestampDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}
