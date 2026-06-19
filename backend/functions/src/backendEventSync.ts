import { createHash } from "node:crypto";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import {
  accountDeletionBlockedError,
  accountDeletionRequestPath,
  isBlockingAccountDeletionRequest
} from "./accountDeletionGuard.js";
import { type CallableQuotaGuard } from "./callableQuotaGuard.js";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPBackendEventSyncAuth = {
  uid: string;
};

export type OpenLARPBackendEventSyncRequest = {
  auth?: OpenLARPBackendEventSyncAuth | null;
  data: unknown;
};

type BackendEventKind =
  | "goalConfirmed"
  | "questStarted"
  | "proofReviewed"
  | "proofClaimed"
  | "outcomeLogged"
  | "outcomeUpdated"
  | "outcomeDeleted"
  | "privacyUpdated"
  | "syncPreviewPrepared";

type BackendEventSyncStatus = "pending" | "inFlight" | "acknowledged" | "failed";

type BackendEventSummary = {
  targetRoleTitle?: string;
  questID?: string;
  questDay?: number;
  proofID?: string;
  outcomeID?: string;
  outcomeKind?: string;
  readinessOverall?: number;
  xp?: number;
  proofCount?: number;
  qualityAccepted?: boolean;
  qualityScore?: number;
  memoryMode?: string;
  shareWins?: boolean;
  allowsPrivateEvidenceCloudSync?: boolean;
  documentCount?: number;
  proofUploadCount?: number;
};

type ParsedBackendEvent = {
  schemaVersion: 1;
  id: string;
  kind: BackendEventKind;
  syncStatus: "inFlight";
  ownerUserID: string;
  entityID: string;
  idempotencyKey: string;
  occurredAt: Date;
  retryCount: number;
  lastAttemptAt?: Date;
  summary: BackendEventSummary;
};

type ParsedBackendEventSyncRequest = {
  schemaVersion: 1;
  requestedAt: Date;
  events: ParsedBackendEvent[];
};

export type BackendEventSyncReceipt = {
  schemaVersion: 1;
  eventID: string;
  idempotencyKey: string;
  status: "acknowledged";
  acceptedAt: string;
};

export type BackendEventSyncSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  requestedAt: string;
  completedAt: string;
  didContactNetwork: true;
  receipts: BackendEventSyncReceipt[];
  externalActionTaken: false;
};

export type BackendEventSyncResponse =
  | BackendEventSyncSuccess
  | OpenLARPFunctionError;

export type BackendEventDocumentAcknowledgement =
  | { ok: true; acceptedAt: string }
  | { ok: false; error: OpenLARPFunctionError };

export type BackendEventSyncDependencies = {
  acknowledgeBackendEventDocument: (
    userID: string,
    eventID: string,
    idempotencyKey: string,
    document: Record<string, unknown>
  ) => Promise<BackendEventDocumentAcknowledgement>;
  quotaGuard?: CallableQuotaGuard;
  now?: () => Date;
};

const KNOWN_BACKEND_EVENT_KINDS = new Set<BackendEventKind>([
  "goalConfirmed",
  "questStarted",
  "proofReviewed",
  "proofClaimed",
  "outcomeLogged",
  "outcomeUpdated",
  "outcomeDeleted",
  "privacyUpdated",
  "syncPreviewPrepared"
]);

const KNOWN_OUTCOME_KINDS = new Set([
  "applied",
  "interview",
  "rejection",
  "offer",
  "changedGoal",
  "other"
]);

const KNOWN_MEMORY_MODES = new Set(["localOnly", "cloudReady", "off"]);
const SUMMARY_KEYS = new Set([
  "targetRoleTitle",
  "questID",
  "questDay",
  "proofID",
  "outcomeID",
  "outcomeKind",
  "readinessOverall",
  "xp",
  "proofCount",
  "qualityAccepted",
  "qualityScore",
  "memoryMode",
  "shareWins",
  "allowsPrivateEvidenceCloudSync",
  "documentCount",
  "proofUploadCount"
]);
const EVENT_KEYS = new Set([
  "id",
  "schemaVersion",
  "kind",
  "syncStatus",
  "ownerUserID",
  "entityID",
  "idempotencyKey",
  "occurredAt",
  "retryCount",
  "lastAttemptAt",
  "summary"
]);
const REQUEST_KEYS = new Set([
  "schemaVersion",
  "requestedAt",
  "session",
  "events",
  "integrationRoutes"
]);
const SESSION_KEYS = new Set([
  "ownerUserID",
  "isAuthenticated",
  "authProvider",
  "auth",
  "firestore",
  "storage",
  "functions",
  "cloudRun",
  "genkit",
  "requiresUserApprovalForExternalActions"
]);
const MAX_EVENTS_PER_SYNC = 25;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ISO_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?Z$/;

export async function handleBackendEventSyncRequest(
  request: OpenLARPBackendEventSyncRequest,
  dependencies: BackendEventSyncDependencies = adminBackendEventSyncDependencies()
): Promise<BackendEventSyncResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before acknowledging OpenLARP backend events.");
  }

  const parsed = parseBackendEventSyncRequest(userID, request.data);
  if (!parsed.ok) {
    return parsed.error;
  }

  const completedAtDate = dependencies.now?.() ?? new Date();
  const quotaDecision = await dependencies.quotaGuard?.checkAndRecord({
    userID,
    callable: "acknowledgeBackendEvents",
    category: "backendEventSync",
    units: parsed.value.events.length,
    auditKey: auditKeyForBackendEventBatch(parsed.value.events
      .map((event) => `${event.id}:${event.idempotencyKey}`)
      .sort()
      .join("|")),
    occurredAt: completedAtDate,
    metadata: {
      eventCount: parsed.value.events.length
    }
  });
  if (quotaDecision && !quotaDecision.ok) {
    return quotaDecision.error;
  }

  const completedAt = completedAtDate.toISOString();
  const receipts: BackendEventSyncReceipt[] = [];
  for (const event of parsed.value.events) {
    const acknowledgement = await dependencies.acknowledgeBackendEventDocument(
      userID,
      event.id,
      event.idempotencyKey,
      backendEventDocument(event, completedAtDate)
    );
    if (!acknowledgement.ok) {
      return acknowledgement.error;
    }
    receipts.push({
      schemaVersion: 1,
      eventID: event.id,
      idempotencyKey: event.idempotencyKey,
      status: "acknowledged",
      acceptedAt: acknowledgement.acceptedAt
    });
  }

  return {
    ok: true,
    schemaVersion: 1,
    userID,
    requestedAt: parsed.value.requestedAt.toISOString(),
    completedAt,
    didContactNetwork: true,
    receipts,
    externalActionTaken: false
  };
}

function auditKeyForBackendEventBatch(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function parseBackendEventSyncRequest(
  userID: string,
  data: unknown
): { ok: true; value: ParsedBackendEventSyncRequest } | { ok: false; error: OpenLARPFunctionError } {
  if (!isRecord(data)) {
    return invalid("Backend event sync request must be an object.");
  }
  if (Object.keys(data).some((key) => !REQUEST_KEYS.has(key))) {
    return invalid("Backend event sync request contains unsupported fields.");
  }

  if (data.schemaVersion !== 1) {
    return invalid("schemaVersion must be 1.");
  }

  const requestedAt = parseDate(data.requestedAt, "requestedAt");
  if (!requestedAt.ok) {
    return requestedAt;
  }

  const session = parseSession(userID, data.session);
  if (!session.ok) {
    return session;
  }

  if (!Array.isArray(data.events) || data.events.length === 0 || data.events.length > MAX_EVENTS_PER_SYNC) {
    return invalid(`events must contain 1 to ${MAX_EVENTS_PER_SYNC} backend events.`);
  }
  if (!Array.isArray(data.integrationRoutes)) {
    return invalid("integrationRoutes must be an array.");
  }

  const events: ParsedBackendEvent[] = [];
  for (const event of data.events) {
    const parsedEvent = parseBackendEvent(userID, event);
    if (!parsedEvent.ok) {
      return parsedEvent;
    }
    events.push(parsedEvent.value);
  }

  const ids = new Set(events.map((event) => event.id));
  if (ids.size !== events.length) {
    return invalid("events must not contain duplicate event IDs.");
  }
  const idempotencyKeys = new Set(events.map((event) => event.idempotencyKey));
  if (idempotencyKeys.size !== events.length) {
    return invalid("events must not contain duplicate idempotency keys.");
  }

  return {
    ok: true,
    value: {
      schemaVersion: 1,
      requestedAt: requestedAt.value,
      events
    }
  };
}

function parseSession(
  userID: string,
  value: unknown
): { ok: true } | { ok: false; error: OpenLARPFunctionError } {
  if (!isRecord(value)) {
    return invalid("session must be an object.");
  }
  if (Object.keys(value).some((key) => !SESSION_KEYS.has(key))) {
    return invalid("session contains unsupported fields.");
  }
  if (value.ownerUserID !== userID) {
    return invalid("session owner must match the signed-in user.");
  }
  if (value.isAuthenticated !== true || value.authProvider !== "firebaseAuth") {
    return invalid("session must be an authenticated Firebase session.");
  }
  if (hasOwn(value, "accountID") || hasOwn(value, "email")) {
    return invalid("session must be redacted before backend event sync.");
  }
  if (
    value.requiresUserApprovalForExternalActions !== undefined &&
    typeof value.requiresUserApprovalForExternalActions !== "boolean"
  ) {
    return invalid("session external action approval flag must be a boolean.");
  }
  const routeFields = ["auth", "firestore", "storage", "functions", "cloudRun", "genkit"] as const;
  for (const field of routeFields) {
    if (value[field] !== undefined) {
      const route = parseIntegrationRoute(value[field], field);
      if (!route.ok) {
        return route;
      }
    }
  }
  return { ok: true };
}

function parseBackendEvent(
  userID: string,
  value: unknown
): { ok: true; value: ParsedBackendEvent } | { ok: false; error: OpenLARPFunctionError } {
  if (!isRecord(value)) {
    return invalid("backend event must be an object.");
  }
  if (Object.keys(value).some((key) => !EVENT_KEYS.has(key))) {
    return invalid("backend event contains unsupported fields.");
  }

  const id = parseUUID(value.id, "id");
  const kind = parseBackendEventKind(value.kind);
  const entityID = parseEntityID(value.entityID);
  const occurredAt = parseDate(value.occurredAt, "occurredAt");
  const retryCount = parseInteger(value.retryCount, "retryCount", 0, 1000);
  const lastAttemptAt = value.lastAttemptAt === undefined
    ? { ok: true as const, value: undefined }
    : parseDate(value.lastAttemptAt, "lastAttemptAt");
  const summary = parseSummary(value.summary);

  if (value.schemaVersion !== 1) {
    return invalid("backend event schemaVersion must be 1.");
  }
  if (!id.ok) {
    return id;
  }
  if (!kind.ok) {
    return kind;
  }
  if (value.syncStatus !== "inFlight") {
    return invalid("backend events must be marked inFlight before server acknowledgement.");
  }
  if (value.ownerUserID !== userID) {
    return invalid("backend event owner must match the signed-in user.");
  }
  if (!entityID.ok) {
    return entityID;
  }
  const expectedIdempotencyKey = `${userID}-${kind.value}-${entityID.value}`;
  if (value.idempotencyKey !== expectedIdempotencyKey) {
    return invalid("backend event idempotency key does not match owner, kind, and entity ID.");
  }
  if (!occurredAt.ok) {
    return occurredAt;
  }
  if (!retryCount.ok) {
    return retryCount;
  }
  if (!lastAttemptAt.ok) {
    return lastAttemptAt;
  }
  if (!summary.ok) {
    return summary;
  }

  const parsedEvent: ParsedBackendEvent = {
    schemaVersion: 1,
    id: id.value,
    kind: kind.value,
    syncStatus: "inFlight",
    ownerUserID: userID,
    entityID: entityID.value,
    idempotencyKey: expectedIdempotencyKey,
    occurredAt: occurredAt.value,
    retryCount: retryCount.value,
    summary: summary.value
  };
  if (lastAttemptAt.value) {
    parsedEvent.lastAttemptAt = lastAttemptAt.value;
  }

  return { ok: true, value: parsedEvent };
}

function parseSummary(
  value: unknown
): { ok: true; value: BackendEventSummary } | { ok: false; error: OpenLARPFunctionError } {
  if (!isRecord(value)) {
    return invalid("backend event summary must be an object.");
  }
  if (Object.keys(value).some((key) => !SUMMARY_KEYS.has(key))) {
    return invalid("backend event summary contains unsupported fields.");
  }

  const summary: BackendEventSummary = {};
  const stringFields = ["questID", "proofID", "outcomeID"] as const;
  for (const field of stringFields) {
    if (value[field] !== undefined) {
      const parsed = parseUUID(value[field], field);
      if (!parsed.ok) {
        return parsed;
      }
      summary[field] = parsed.value;
    }
  }

  if (value.targetRoleTitle !== undefined) {
    if (typeof value.targetRoleTitle !== "string" || value.targetRoleTitle.length > 80) {
      return invalid("targetRoleTitle must be a string no longer than 80 characters.");
    }
    summary.targetRoleTitle = value.targetRoleTitle;
  }
  if (value.outcomeKind !== undefined) {
    if (typeof value.outcomeKind !== "string" || !KNOWN_OUTCOME_KINDS.has(value.outcomeKind)) {
      return invalid("outcomeKind is not recognized.");
    }
    summary.outcomeKind = value.outcomeKind;
  }
  if (value.memoryMode !== undefined) {
    if (typeof value.memoryMode !== "string" || !KNOWN_MEMORY_MODES.has(value.memoryMode)) {
      return invalid("memoryMode is not recognized.");
    }
    summary.memoryMode = value.memoryMode;
  }

  const integerFields = [
    "questDay",
    "readinessOverall",
    "xp",
    "proofCount",
    "qualityScore",
    "documentCount",
    "proofUploadCount"
  ] as const;
  for (const field of integerFields) {
    if (value[field] !== undefined) {
      const parsed = parseInteger(value[field], field, 0, 100000);
      if (!parsed.ok) {
        return parsed;
      }
      summary[field] = parsed.value;
    }
  }

  const boolFields = ["qualityAccepted", "shareWins", "allowsPrivateEvidenceCloudSync"] as const;
  for (const field of boolFields) {
    if (value[field] !== undefined) {
      if (typeof value[field] !== "boolean") {
        return invalid(`${field} must be a boolean.`);
      }
      summary[field] = value[field];
    }
  }

  return { ok: true, value: summary };
}

function backendEventDocument(
  event: ParsedBackendEvent,
  acceptedAt: Date
): Record<string, unknown> {
  const document: Record<string, unknown> = {
    schemaVersion: 1,
    eventID: event.id,
    ownerUserID: event.ownerUserID,
    entityID: event.entityID,
    kind: event.kind,
    syncStatus: "acknowledged",
    idempotencyKey: event.idempotencyKey,
    occurredAt: Timestamp.fromDate(event.occurredAt),
    retryCount: event.retryCount,
    summary: event.summary,
    acceptedAt: Timestamp.fromDate(acceptedAt)
  };
  if (event.lastAttemptAt) {
    document.lastAttemptAt = Timestamp.fromDate(event.lastAttemptAt);
  }
  return document;
}

export function adminBackendEventSyncDependencies(
  quotaGuard?: CallableQuotaGuard
): BackendEventSyncDependencies {
  return {
    async acknowledgeBackendEventDocument(userID, eventID, idempotencyKey, document) {
      const firestore = getFirestore();
      const deletionReference = firestore.doc(accountDeletionRequestPath(userID));
      const reference = firestore.doc(`users/${userID}/backendEvents/${eventID}`);
      return firestore.runTransaction(async (transaction) => {
        const deletionSnapshot = await transaction.get(deletionReference);
        const deletionDocument = deletionSnapshot.exists ? deletionSnapshot.data() : null;
        if (isBlockingAccountDeletionRequest(userID, deletionDocument)) {
          return {
            ok: false,
            error: accountDeletionBlockedError(deletionDocument.status)
          };
        }

        const snapshot = await transaction.get(reference);
        if (snapshot.exists) {
          if (snapshot.get("idempotencyKey") !== idempotencyKey) {
            return {
              ok: false,
              error: functionError(
                "failed-precondition",
                "An acknowledged backend event already exists with a different idempotency key."
              )
            };
          }

          const acceptedAt = timestampToISOString(snapshot.get("acceptedAt"));
          if (!acceptedAt) {
            return {
              ok: false,
              error: functionError(
                "failed-precondition",
                "Existing backend event acknowledgement is missing a valid acceptedAt timestamp."
              )
            };
          }
          return { ok: true, acceptedAt };
        }

        transaction.create(reference, document);
        const acceptedAt = timestampToISOString(document.acceptedAt);
        if (!acceptedAt) {
          return {
            ok: false,
            error: functionError("internal", "Backend event acceptedAt timestamp was not generated.")
          };
        }
        return { ok: true, acceptedAt };
      });
    },
    ...(quotaGuard ? { quotaGuard } : {})
  };
}

function parseBackendEventKind(
  value: unknown
): { ok: true; value: BackendEventKind } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "string" || !KNOWN_BACKEND_EVENT_KINDS.has(value as BackendEventKind)) {
    return invalid("backend event kind is not recognized.");
  }
  return { ok: true, value: value as BackendEventKind };
}

function parseUUID(
  value: unknown,
  fieldName: string
): { ok: true; value: string } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    return invalid(`${fieldName} must be a UUID string.`);
  }
  return { ok: true, value };
}

function parseEntityID(
  value: unknown
): { ok: true; value: string } | { ok: false; error: OpenLARPFunctionError } {
  if (
    typeof value !== "string" ||
    value.trim().length === 0 ||
    value.length > 128 ||
    value.includes("/") ||
    value.includes("\\")
  ) {
    return invalid("entityID must be a non-empty ID without path separators.");
  }
  return { ok: true, value };
}

function parseDate(
  value: unknown,
  fieldName: string
): { ok: true; value: Date } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "string") {
    return invalid(`${fieldName} must be an ISO 8601 date string.`);
  }
  const match = ISO_DATE_PATTERN.exec(value);
  if (!match) {
    return invalid(`${fieldName} must be an ISO 8601 UTC date string.`);
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    return invalid(`${fieldName} must be an ISO 8601 date string.`);
  }
  const [, year, month, day, hour, minute, second] = match;
  if (
    date.getUTCFullYear() !== Number(year) ||
    date.getUTCMonth() + 1 !== Number(month) ||
    date.getUTCDate() !== Number(day) ||
    date.getUTCHours() !== Number(hour) ||
    date.getUTCMinutes() !== Number(minute) ||
    date.getUTCSeconds() !== Number(second)
  ) {
    return invalid(`${fieldName} must be a valid ISO 8601 UTC calendar date.`);
  }
  return { ok: true, value: date };
}

function parseIntegrationRoute(
  value: unknown,
  fieldName: string
): { ok: true } | { ok: false; error: OpenLARPFunctionError } {
  if (!isRecord(value)) {
    return invalid(`session ${fieldName} route must be an object.`);
  }
  if (typeof value.kind !== "string" || typeof value.status !== "string") {
    return invalid(`session ${fieldName} route must include string kind and status.`);
  }
  if (value.detail !== undefined && typeof value.detail !== "string") {
    return invalid(`session ${fieldName} route detail must be a string.`);
  }
  if (value.displayName !== undefined && typeof value.displayName !== "string") {
    return invalid(`session ${fieldName} route displayName must be a string.`);
  }
  return { ok: true };
}

function parseInteger(
  value: unknown,
  fieldName: string,
  min: number,
  max: number
): { ok: true; value: number } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    return invalid(`${fieldName} must be an integer between ${min} and ${max}.`);
  }
  return { ok: true, value };
}

function timestampToISOString(value: unknown): string | undefined {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date.toISOString() : undefined;
  }
  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasOwn(value: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function invalid(message: string): { ok: false; error: OpenLARPFunctionError } {
  return {
    ok: false,
    error: functionError("invalid-argument", message)
  };
}
