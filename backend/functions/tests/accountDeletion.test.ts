import { describe, expect, it } from "vitest";
import {
  ACCOUNT_DELETION_CONFIRMATION_TEXT,
  handleAccountDeletionRequest,
  type AccountDeletionAuthResult,
  type AccountDeletionDependencies,
  type AccountDeletionScopeResult
} from "../src/accountDeletion.js";
import { rejectIfAccountDeletionRequested } from "../src/accountDeletionGuard.js";

const now = new Date("2026-06-19T08:00:00.000Z");
const authTime = Math.floor(now.getTime() / 1000);

function requestData(overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    confirmDeletion: true,
    confirmationText: ACCOUNT_DELETION_CONFIRMATION_TEXT,
    ...overrides
  };
}

function completed(deletedCount = 0): AccountDeletionScopeResult {
  return {
    status: "completed",
    deletedCount
  };
}

function failed(message = "cleanup failed"): AccountDeletionScopeResult {
  return {
    status: "failed",
    deletedCount: 0,
    errorMessage: message
  };
}

function makeDependencies(options: {
  storage?: AccountDeletionScopeResult;
  firestoreUser?: AccountDeletionScopeResult;
  quotaUsage?: AccountDeletionScopeResult;
  auth?: AccountDeletionAuthResult;
  maxAuthAgeSeconds?: number;
} = {}) {
  const calls: string[] = [];
  const dependencies: AccountDeletionDependencies = {
    async writeDeletionRequestStarted(userID) {
      calls.push(`tombstoneStarted:${userID}`);
    },
    async writeDeletionRequestFinished(userID, result) {
      calls.push(`tombstoneFinished:${userID}:${result.status}`);
      return { status: "completed" };
    },
    async deleteStorageUserPrefix(userID) {
      calls.push(`storage:${userID}`);
      return options.storage ?? completed(2);
    },
    async deleteFirestoreUserTree(userID) {
      calls.push(`firestore:${userID}`);
      return options.firestoreUser ?? completed(5);
    },
    async deleteQuotaUsageTree(userID) {
      calls.push(`quota:${userID}`);
      return options.quotaUsage ?? completed(1);
    },
    async deleteAuthUser(userID) {
      calls.push(`auth:${userID}`);
      return options.auth ?? { status: "deleted" };
    },
    now: () => now,
    ...(options.maxAuthAgeSeconds === undefined ? {} : { maxAuthAgeSeconds: options.maxAuthAgeSeconds })
  };

  return {
    calls,
    dependencies
  };
}

function authed(
  data: unknown,
  dependencies: AccountDeletionDependencies,
  token: Record<string, unknown> = { auth_time: authTime }
) {
  return handleAccountDeletionRequest({
    auth: {
      uid: "user_123",
      token
    },
    data
  }, dependencies);
}

describe("handleAccountDeletionRequest", () => {
  it("requires Firebase Auth before any deletion work", async () => {
    const { dependencies, calls } = makeDependencies();

    const response = await handleAccountDeletionRequest({
      auth: null,
      data: requestData()
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
    expect(calls).toEqual([]);
  });

  it("requires the current schema, destructive confirmation boolean, and exact confirmation text", async () => {
    const cases: unknown[] = [
      undefined,
      { ...requestData(), schemaVersion: 2 },
      { ...requestData(), confirmDeletion: false },
      { ...requestData(), confirmationText: "delete my account" }
    ];

    for (const data of cases) {
      const { dependencies, calls } = makeDependencies();
      const response = await authed(data, dependencies);

      expect(response).toMatchObject({
        ok: false,
        code: "invalid-argument"
      });
      expect(calls).toEqual([]);
    }
  });

  it("requires recent Firebase auth before deleting account data", async () => {
    const { dependencies, calls } = makeDependencies();

    const response = await authed(requestData(), dependencies, {
      auth_time: authTime - 601
    });

    expect(response).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
    expect(calls).toEqual([]);
  });

  it("deletes Storage, Firestore user tree, quota usage, and Auth user when all data scopes complete", async () => {
    const { dependencies, calls } = makeDependencies();

    const response = await authed(requestData(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      schemaVersion: 1,
      userID: "user_123",
      status: "deleted",
      deletionRequestDocumentPath: "_accountDeletionRequests/user_123",
      requestedAt: "2026-06-19T08:00:00.000Z",
      completedAt: "2026-06-19T08:00:00.000Z",
      storageUserPrefix: {
        status: "completed",
        deletedCount: 2
      },
      firestoreUserTree: {
        status: "completed",
        deletedCount: 5
      },
      quotaUsageTree: {
        status: "completed",
        deletedCount: 1
      },
      firebaseAuthUser: {
        status: "deleted"
      },
      deletionRequestMarker: {
        status: "completed"
      },
      externalActionTaken: true
    });
    expect(calls).toEqual([
      "tombstoneStarted:user_123",
      "storage:user_123",
      "firestore:user_123",
      "quota:user_123",
      "auth:user_123",
      "tombstoneFinished:user_123:deleted"
    ]);
  });

  it("treats an already missing Auth user as a completed account deletion after data cleanup", async () => {
    const { dependencies } = makeDependencies({
      storage: completed(0),
      firestoreUser: completed(0),
      quotaUsage: completed(0),
      auth: { status: "alreadyMissing" }
    });

    const response = await authed(requestData(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "deleted",
      firebaseAuthUser: {
        status: "alreadyMissing"
      },
      externalActionTaken: false
    });
  });

  it("skips Auth deletion and returns partial when any data scope fails", async () => {
    const { dependencies, calls } = makeDependencies({
      storage: failed("storage unavailable"),
      firestoreUser: completed(3),
      quotaUsage: completed(1)
    });

    const response = await authed(requestData(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "partial",
      storageUserPrefix: {
        status: "failed",
        errorMessage: "storage unavailable"
      },
      firebaseAuthUser: {
        status: "skipped"
      },
      externalActionTaken: true
    });
    expect(calls).toEqual([
      "tombstoneStarted:user_123",
      "storage:user_123",
      "firestore:user_123",
      "quota:user_123",
      "tombstoneFinished:user_123:partial"
    ]);
  });

  it("returns partial when Firebase Auth deletion fails after completed data cleanup", async () => {
    const { dependencies } = makeDependencies({
      auth: {
        status: "failed",
        errorMessage: "Auth backend unavailable"
      }
    });

    const response = await authed(requestData(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "partial",
      firebaseAuthUser: {
        status: "failed",
        errorMessage: "Auth backend unavailable"
      }
    });
  });

  it("reports external action when cleanup was attempted but a data scope failed", async () => {
    const { dependencies } = makeDependencies({
      storage: {
        status: "failed",
        deletedCount: 0,
        attemptedCount: 2,
        failedCount: 2,
        failedPathSamples: [
          "users/user_123/proofAttachments/a",
          "users/user_123/proofAttachments/b"
        ],
        errorMessage: "Storage cleanup failed."
      },
      firestoreUser: completed(0),
      quotaUsage: completed(0)
    });

    const response = await authed(requestData(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "partial",
      storageUserPrefix: {
        status: "failed",
        attemptedCount: 2,
        failedCount: 2,
        failedPathSamples: [
          "users/user_123/proofAttachments/a",
          "users/user_123/proofAttachments/b"
        ]
      },
      externalActionTaken: true
    });
  });

  it("returns a partial result if final deletion marker update fails after destructive cleanup", async () => {
    const calls: string[] = [];
    const dependencies: AccountDeletionDependencies = {
      async writeDeletionRequestStarted(userID) {
        calls.push(`tombstoneStarted:${userID}`);
      },
      async writeDeletionRequestFinished(userID, result) {
        calls.push(`tombstoneFinished:${userID}:${result.status}`);
        return {
          status: "failed",
          errorMessage: "Marker update failed."
        };
      },
      async deleteStorageUserPrefix() {
        return completed(1);
      },
      async deleteFirestoreUserTree() {
        return completed(2);
      },
      async deleteQuotaUsageTree() {
        return completed(1);
      },
      async deleteAuthUser() {
        return { status: "deleted" };
      },
      now: () => now
    };

    const response = await authed(requestData(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      status: "partial",
      storageUserPrefix: { status: "completed", deletedCount: 1 },
      firestoreUserTree: { status: "completed", deletedCount: 2 },
      quotaUsageTree: { status: "completed", deletedCount: 1 },
      firebaseAuthUser: { status: "deleted" },
      deletionRequestMarker: {
        status: "failed",
        errorMessage: "Marker update failed."
      },
      externalActionTaken: true
    });
    expect(calls).toEqual([
      "tombstoneStarted:user_123",
      "tombstoneFinished:user_123:deleted"
    ]);
  });

  it("accepts auth_time strings but rejects missing auth_time claims", async () => {
    const { dependencies: stringTimeDependencies } = makeDependencies();
    const stringTimeResponse = await authed(requestData(), stringTimeDependencies, {
      auth_time: String(authTime)
    });
    expect(stringTimeResponse).toMatchObject({
      ok: true,
      status: "deleted"
    });

    const { dependencies: missingTimeDependencies, calls } = makeDependencies();
    const missingTimeResponse = await authed(requestData(), missingTimeDependencies, {});
    expect(missingTimeResponse).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
    expect(calls).toEqual([]);
  });
});

describe("rejectIfAccountDeletionRequested", () => {
  it("blocks work for deleting, deleted, or partial account deletion markers", async () => {
    for (const status of ["deleting", "deleted", "partial"]) {
      const response = await rejectIfAccountDeletionRequested("user_123", {
        async readAccountDeletionRequest() {
          return {
            schemaVersion: 1,
            ownerUserID: "user_123",
            status
          };
        }
      });

      expect(response).toMatchObject({
        ok: false,
        code: "failed-precondition",
        details: { status }
      });
    }
  });

  it("ignores malformed or cross-user account deletion markers", async () => {
    const response = await rejectIfAccountDeletionRequested("user_123", {
      async readAccountDeletionRequest() {
        return {
          schemaVersion: 1,
          ownerUserID: "other_user",
          status: "deleting"
        };
      }
    });

    expect(response).toBeNull();
  });
});
