import { createHash } from "node:crypto";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp, type DocumentReference } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { accountDeletionRequestPath } from "./accountDeletionGuard.js";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPAccountDeletionAuth = {
  uid: string;
  token?: Record<string, unknown>;
};

export type OpenLARPAccountDeletionRequest = {
  auth?: OpenLARPAccountDeletionAuth | null;
  data: unknown;
};

export type AccountDeletionScopeResult = {
  status: "completed" | "failed";
  deletedCount: number;
  attemptedCount?: number;
  failedCount?: number;
  failedPathSamples?: string[];
  errorMessage?: string;
};

export type AccountDeletionAuthResult = {
  status: "deleted" | "alreadyMissing" | "failed" | "skipped";
  errorMessage?: string;
};

export type AccountDeletionMarkerResult = {
  status: "completed" | "failed";
  errorMessage?: string;
};

export type AccountDeletionSuccess = {
  ok: true;
  schemaVersion: 1;
  userID: string;
  status: "deleted" | "partial";
  deletionRequestDocumentPath: string;
  requestedAt: string;
  completedAt: string;
  firestoreUserTree: AccountDeletionScopeResult;
  storageUserPrefix: AccountDeletionScopeResult;
  quotaUsageTree: AccountDeletionScopeResult;
  firebaseAuthUser: AccountDeletionAuthResult;
  deletionRequestMarker: AccountDeletionMarkerResult;
  externalActionTaken: boolean;
};

export type AccountDeletionResponse =
  | AccountDeletionSuccess
  | OpenLARPFunctionError;

export type AccountDeletionDependencies = {
  writeDeletionRequestStarted: (userID: string, requestedAt: Date) => Promise<void>;
  writeDeletionRequestFinished: (
    userID: string,
    result: AccountDeletionSuccess
  ) => Promise<AccountDeletionMarkerResult>;
  deleteStorageUserPrefix: (userID: string) => Promise<AccountDeletionScopeResult>;
  deleteFirestoreUserTree: (userID: string) => Promise<AccountDeletionScopeResult>;
  deleteQuotaUsageTree: (userID: string) => Promise<AccountDeletionScopeResult>;
  deleteAuthUser: (userID: string) => Promise<AccountDeletionAuthResult>;
  now?: () => Date;
  maxAuthAgeSeconds?: number;
};

type ParsedAccountDeletionRequest = {
  schemaVersion: 1;
  confirmDeletion: true;
  confirmationText: typeof ACCOUNT_DELETION_CONFIRMATION_TEXT;
};

export const ACCOUNT_DELETION_CONFIRMATION_TEXT = "DELETE MY OPENLARP ACCOUNT";
const DEFAULT_MAX_AUTH_AGE_SECONDS = 10 * 60;

export async function handleAccountDeletionRequest(
  request: OpenLARPAccountDeletionRequest,
  dependencies: AccountDeletionDependencies = adminAccountDeletionDependencies()
): Promise<AccountDeletionResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before deleting your OpenLARP account.");
  }

  const parsed = parseAccountDeletionRequest(request.data);
  if (!parsed.ok) {
    return parsed.error;
  }

  const now = dependencies.now?.() ?? new Date();
  const authFreshness = validateRecentAuth(request.auth?.token, now, dependencies.maxAuthAgeSeconds);
  if (!authFreshness.ok) {
    return authFreshness.error;
  }

  try {
    await dependencies.writeDeletionRequestStarted(userID, now);
  } catch (error) {
    return functionError(
      "internal",
      "Account deletion could not start before any account data was deleted.",
      { errorMessage: safeErrorMessage(error) }
    );
  }

  const storageUserPrefix = await dependencies.deleteStorageUserPrefix(userID);
  const firestoreUserTree = await dependencies.deleteFirestoreUserTree(userID);
  const quotaUsageTree = await dependencies.deleteQuotaUsageTree(userID);
  const dataScopesCompleted = [
    storageUserPrefix.status,
    firestoreUserTree.status,
    quotaUsageTree.status
  ].every((status) => status === "completed");
  const firebaseAuthUser = dataScopesCompleted
    ? await dependencies.deleteAuthUser(userID)
    : { status: "skipped" as const, errorMessage: "Auth deletion skipped until account data cleanup completes." };
  const fullyDeleted = dataScopesCompleted &&
    (firebaseAuthUser.status === "deleted" || firebaseAuthUser.status === "alreadyMissing");

  const responseWithoutFinalMarker: AccountDeletionSuccess = {
    ok: true,
    schemaVersion: 1,
    userID,
    status: fullyDeleted ? "deleted" : "partial",
    deletionRequestDocumentPath: accountDeletionRequestPath(userID),
    requestedAt: now.toISOString(),
    completedAt: (dependencies.now?.() ?? new Date()).toISOString(),
    firestoreUserTree,
    storageUserPrefix,
    quotaUsageTree,
    firebaseAuthUser,
    deletionRequestMarker: { status: "completed" },
    externalActionTaken: accountDeletionTookExternalAction({
      storageUserPrefix,
      firestoreUserTree,
      quotaUsageTree,
      firebaseAuthUser
    })
  };

  const deletionRequestMarker = await dependencies.writeDeletionRequestFinished(userID, responseWithoutFinalMarker);
  const response: AccountDeletionSuccess = {
    ...responseWithoutFinalMarker,
    status: fullyDeleted && deletionRequestMarker.status === "completed" ? "deleted" : "partial",
    deletionRequestMarker
  };
  return response;
}

function parseAccountDeletionRequest(
  data: unknown
): { ok: true; value: ParsedAccountDeletionRequest } | { ok: false; error: OpenLARPFunctionError } {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return invalid("Account deletion request must be an object.");
  }

  const record = data as Record<string, unknown>;
  const schemaVersion = record.schemaVersion === undefined ? 1 : record.schemaVersion;
  if (schemaVersion !== 1) {
    return invalid("schemaVersion must be 1.");
  }
  if (record.confirmDeletion !== true) {
    return invalid("confirmDeletion must be true.");
  }
  if (record.confirmationText !== ACCOUNT_DELETION_CONFIRMATION_TEXT) {
    return invalid(`confirmationText must equal "${ACCOUNT_DELETION_CONFIRMATION_TEXT}".`);
  }

  return {
    ok: true,
    value: {
      schemaVersion: 1,
      confirmDeletion: true,
      confirmationText: ACCOUNT_DELETION_CONFIRMATION_TEXT
    }
  };
}

function validateRecentAuth(
  token: Record<string, unknown> | undefined,
  now: Date,
  maxAuthAgeSeconds = DEFAULT_MAX_AUTH_AGE_SECONDS
): { ok: true } | { ok: false; error: OpenLARPFunctionError } {
  const authTime = token?.auth_time;
  const authTimeSeconds = typeof authTime === "number"
    ? authTime
    : typeof authTime === "string"
      ? Number.parseInt(authTime, 10)
      : NaN;
  if (!Number.isFinite(authTimeSeconds)) {
    return {
      ok: false,
      error: functionError("failed-precondition", "Recent Firebase authentication is required before account deletion.")
    };
  }

  const ageSeconds = Math.floor(now.getTime() / 1000) - authTimeSeconds;
  if (ageSeconds < 0 || ageSeconds > maxAuthAgeSeconds) {
    return {
      ok: false,
      error: functionError("failed-precondition", "Sign in again before deleting your OpenLARP account.")
    };
  }

  return { ok: true };
}

function invalid(message: string): { ok: false; error: OpenLARPFunctionError } {
  return {
    ok: false,
    error: functionError("invalid-argument", message)
  };
}

export function adminAccountDeletionDependencies(): AccountDeletionDependencies {
  return {
    async writeDeletionRequestStarted(userID, requestedAt) {
      const timestamp = Timestamp.fromDate(requestedAt);
      await getFirestore().doc(accountDeletionRequestPath(userID)).set({
        schemaVersion: 1,
        ownerUserID: userID,
        status: "deleting",
        requestedAt: timestamp,
        startedAt: timestamp,
        updatedAt: timestamp,
        collectionPath: "_accountDeletionRequests",
        documentPath: accountDeletionRequestPath(userID),
        retentionReason: "Minimal operational deletion marker retained to block stale clients from writing account data after account deletion starts."
      }, { merge: true });
    },
    async writeDeletionRequestFinished(userID, result) {
      try {
        const completedAt = Timestamp.fromDate(new Date(result.completedAt));
        await getFirestore().doc(accountDeletionRequestPath(userID)).set({
          schemaVersion: 1,
          ownerUserID: userID,
          status: result.status,
          updatedAt: completedAt,
          completedAt,
          collectionPath: "_accountDeletionRequests",
          documentPath: accountDeletionRequestPath(userID),
          scopes: {
            storageUserPrefix: result.storageUserPrefix,
            firestoreUserTree: result.firestoreUserTree,
            quotaUsageTree: result.quotaUsageTree,
            firebaseAuthUser: result.firebaseAuthUser
          },
          externalActionTaken: result.externalActionTaken,
          retentionReason: "Minimal operational deletion marker retained to block stale clients from writing account data after account deletion starts."
        }, { merge: true });
        return { status: "completed" as const };
      } catch (error) {
        return {
          status: "failed" as const,
          errorMessage: safeErrorMessage(error)
        };
      }
    },
    deleteStorageUserPrefix,
    async deleteFirestoreUserTree(userID) {
      return deleteFirestoreDocumentTree(`users/${userID}`);
    },
    async deleteQuotaUsageTree(userID) {
      return deleteFirestoreDocumentTree(`_serverUsage/${callableQuotaUserBucketID(userID)}`);
    },
    async deleteAuthUser(userID) {
      try {
        await getAuth().deleteUser(userID);
        return { status: "deleted" as const };
      } catch (error) {
        const code = typeof (error as { code?: unknown })?.code === "string"
          ? (error as { code: string }).code
          : "";
        if (code === "auth/user-not-found") {
          return { status: "alreadyMissing" as const };
        }
        return {
          status: "failed" as const,
          errorMessage: safeErrorMessage(error)
        };
      }
    }
  };
}

async function deleteStorageUserPrefix(userID: string): Promise<AccountDeletionScopeResult> {
  try {
    const prefix = `users/${userID}/`;
    const [files] = await getStorage().bucket().getFiles({ prefix });
    const settled = await Promise.allSettled(files.map((file) => file.delete({ ignoreNotFound: true })));
    const deletedCount = settled.filter((result) => result.status === "fulfilled").length;
    const failedCount = settled.length - deletedCount;
    const failedPathSamples = files
      .filter((_, index) => settled[index]?.status === "rejected")
      .slice(0, 5)
      .map((file) => file.name);
    const result: AccountDeletionScopeResult = {
      status: failedCount === 0 ? "completed" : "failed",
      deletedCount,
      attemptedCount: files.length,
      failedCount
    };
    if (failedCount > 0) {
      result.errorMessage = "One or more Storage objects could not be deleted.";
      result.failedPathSamples = failedPathSamples;
    }
    return result;
  } catch (error) {
    return {
      status: "failed",
      deletedCount: 0,
      attemptedCount: 0,
      failedCount: 1,
      errorMessage: safeErrorMessage(error)
    };
  }
}

async function deleteFirestoreDocumentTree(documentPath: string): Promise<AccountDeletionScopeResult> {
  const result = await deleteFirestoreDocumentTreeAt(getFirestore().doc(documentPath));
  const response: AccountDeletionScopeResult = {
    status: result.failedCount === 0 ? "completed" : "failed",
    deletedCount: result.deletedCount,
    attemptedCount: result.attemptedCount,
    failedCount: result.failedCount
  };
  if (result.failedCount > 0) {
    response.errorMessage = "One or more Firestore documents could not be deleted.";
    response.failedPathSamples = result.failedPathSamples;
  }
  return response;
}

async function deleteFirestoreDocumentTreeAt(
  documentReference: DocumentReference
): Promise<{
  deletedCount: number;
  attemptedCount: number;
  failedCount: number;
  failedPathSamples: string[];
}> {
  const result = {
    deletedCount: 0,
    attemptedCount: 0,
    failedCount: 0,
    failedPathSamples: [] as string[]
  };
  let collections: Awaited<ReturnType<DocumentReference["listCollections"]>>;
  try {
    collections = await documentReference.listCollections();
  } catch {
    result.failedCount += 1;
    result.failedPathSamples.push(documentReference.path);
    return result;
  }

  for (const collection of collections) {
    let documents: DocumentReference[];
    try {
      documents = await collection.listDocuments();
    } catch {
      result.failedCount += 1;
      result.failedPathSamples.push(collection.path);
      continue;
    }
    for (const document of documents) {
      mergeFirestoreDeletionResult(result, await deleteFirestoreDocumentTreeAt(document));
    }
  }

  try {
    const snapshot = await documentReference.get();
    if (snapshot.exists) {
      result.attemptedCount += 1;
      await documentReference.delete();
      result.deletedCount += 1;
    }
  } catch {
    result.failedCount += 1;
    result.failedPathSamples.push(documentReference.path);
  }
  result.failedPathSamples = result.failedPathSamples.slice(0, 5);
  return result;
}

function mergeFirestoreDeletionResult(
  target: {
    deletedCount: number;
    attemptedCount: number;
    failedCount: number;
    failedPathSamples: string[];
  },
  source: {
    deletedCount: number;
    attemptedCount: number;
    failedCount: number;
    failedPathSamples: string[];
  }
) {
  target.deletedCount += source.deletedCount;
  target.attemptedCount += source.attemptedCount;
  target.failedCount += source.failedCount;
  target.failedPathSamples.push(...source.failedPathSamples);
  target.failedPathSamples = target.failedPathSamples.slice(0, 5);
}

function accountDeletionTookExternalAction(result: {
  storageUserPrefix: AccountDeletionScopeResult;
  firestoreUserTree: AccountDeletionScopeResult;
  quotaUsageTree: AccountDeletionScopeResult;
  firebaseAuthUser: AccountDeletionAuthResult;
}): boolean {
  return [
    result.storageUserPrefix,
    result.firestoreUserTree,
    result.quotaUsageTree
  ].some((scope) =>
    scope.deletedCount > 0 ||
      (scope.attemptedCount ?? 0) > 0
  ) || result.firebaseAuthUser.status === "deleted";
}

function callableQuotaUserBucketID(userID: string): string {
  return createHash("sha256").update(userID).digest("hex").slice(0, 40);
}

function safeErrorMessage(error: unknown): string {
  return error instanceof Error && error.message.length > 0
    ? error.message.slice(0, 240)
    : "Account deletion cleanup failed.";
}
