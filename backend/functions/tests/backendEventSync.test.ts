import { describe, expect, it } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import {
  handleBackendEventSyncRequest,
  type BackendEventSyncDependencies,
  type BackendEventSyncResponse
} from "../src/backendEventSync.js";
import { makeQuotaGuard } from "./quotaTestHelpers.js";

const now = new Date("2026-06-18T13:00:00.000Z");
const requestedAt = "2026-06-18T12:55:00.000Z";
const eventID = "11111111-1111-4111-8111-111111111111";
const questID = "22222222-2222-4222-8222-222222222222";

function backendEvent(overrides: Record<string, unknown> = {}) {
  return {
    id: eventID,
    schemaVersion: 1,
    kind: "questStarted",
    syncStatus: "inFlight",
    ownerUserID: "user_123",
    entityID: questID,
    idempotencyKey: `user_123-questStarted-${questID}`,
    occurredAt: "2026-06-18T12:45:00.000Z",
    retryCount: 1,
    lastAttemptAt: "2026-06-18T12:55:00.000Z",
    summary: {
      questID,
      questDay: 1,
      targetRoleTitle: "AI product engineer",
      xp: 20
    },
    ...overrides
  };
}

function eventUUID(index: number): string {
  return `00000000-0000-4000-8000-${index.toString(16).padStart(12, "0")}`;
}

function syncPayload(events: unknown[] = [backendEvent()], overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    requestedAt,
    session: {
      ownerUserID: "user_123",
      isAuthenticated: true,
      authProvider: "firebaseAuth"
    },
    events,
    integrationRoutes: [],
    ...overrides
  };
}

type ExistingBackendEvent = { exists: true; idempotencyKey: unknown; acceptedAt?: unknown } | { exists: false };

function makeDependencies(
  existing: ExistingBackendEvent = { exists: false },
  options: Pick<BackendEventSyncDependencies, "quotaGuard"> = {}
) {
  const reads: Array<{ userID: string; eventID: string }> = [];
  const writes: Array<{
    userID: string;
    eventID: string;
    idempotencyKey: string;
    document: Record<string, unknown>;
  }> = [];
  const dependencies: BackendEventSyncDependencies = {
    async acknowledgeBackendEventDocument(userID, backendEventID, idempotencyKey, document) {
      reads.push({ userID, eventID: backendEventID });
      if (existing.exists) {
        if (existing.idempotencyKey !== idempotencyKey) {
          return {
            ok: false,
            error: {
              ok: false,
              code: "failed-precondition",
              message: "An acknowledged backend event already exists with a different idempotency key."
            }
          };
        }
        return {
          ok: true,
          acceptedAt: timestampToISOString(existing.acceptedAt)
        };
      }
      writes.push({ userID, eventID: backendEventID, idempotencyKey, document });
      return {
        ok: true,
        acceptedAt: now.toISOString()
      };
    },
    ...options,
    now: () => now
  };

  return { dependencies, reads, writes };
}

function makeDeletingAccountDependencies() {
  const dependencies: BackendEventSyncDependencies = {
    async acknowledgeBackendEventDocument() {
      return {
        ok: false,
        error: {
          ok: false,
          code: "failed-precondition",
          message: "This OpenLARP account is already scheduled for deletion.",
          details: { status: "deleting" }
        }
      };
    },
    now: () => now
  };

  return { dependencies };
}

function authed(
  data: unknown,
  dependencies: BackendEventSyncDependencies
): Promise<BackendEventSyncResponse> {
  return handleBackendEventSyncRequest({
    auth: { uid: "user_123" },
    data
  }, dependencies);
}

function timestampToISOString(value: unknown): string {
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === "string") {
    return new Date(value).toISOString();
  }
  return now.toISOString();
}

describe("handleBackendEventSyncRequest", () => {
  it("stops before acknowledging backend events when account deletion starts concurrently", async () => {
    const { dependencies } = makeDeletingAccountDependencies();

    const response = await authed(syncPayload(), dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "failed-precondition",
      details: { status: "deleting" }
    });
  });

  it("requires Firebase Auth before acknowledging backend events", async () => {
    const { dependencies } = makeDependencies();

    const response = await handleBackendEventSyncRequest({
      auth: null,
      data: syncPayload()
    }, dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
  });

  it("writes acknowledged backend event documents with server timestamps", async () => {
    const { dependencies, reads, writes } = makeDependencies();

    const response = await authed(syncPayload(), dependencies);

    expect(reads).toEqual([{ userID: "user_123", eventID }]);
    expect(writes).toHaveLength(1);
    expect(writes[0]).toMatchObject({
      userID: "user_123",
      eventID,
      idempotencyKey: `user_123-questStarted-${questID}`,
      document: {
        schemaVersion: 1,
        eventID,
        ownerUserID: "user_123",
        entityID: questID,
        kind: "questStarted",
        syncStatus: "acknowledged",
        idempotencyKey: `user_123-questStarted-${questID}`,
        retryCount: 1,
        summary: {
          questID,
          questDay: 1,
          targetRoleTitle: "AI product engineer",
          xp: 20
        }
      }
    });
    expect(writes[0]?.document.occurredAt).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document.lastAttemptAt).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document.acceptedAt).toBeInstanceOf(Timestamp);
    expect(writes[0]?.document).not.toHaveProperty("failureSummary");
    expect(response).toEqual({
      ok: true,
      schemaVersion: 1,
      userID: "user_123",
      requestedAt,
      completedAt: "2026-06-18T13:00:00.000Z",
      didContactNetwork: true,
      receipts: [{
        schemaVersion: 1,
        eventID,
        idempotencyKey: `user_123-questStarted-${questID}`,
        status: "acknowledged",
        acceptedAt: "2026-06-18T13:00:00.000Z"
      }],
      externalActionTaken: false
    });
  });

  it("records quota before acknowledging backend event documents", async () => {
    const { guard, charges } = makeQuotaGuard({ limitUnits: 500 });
    const { dependencies, reads, writes } = makeDependencies({ exists: false }, {
      quotaGuard: guard
    });

    const response = await authed(syncPayload(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      receipts: [{ eventID }]
    });
    expect(reads).toEqual([{ userID: "user_123", eventID }]);
    expect(writes).toHaveLength(1);
    expect(charges).toHaveLength(1);
    expect(charges[0]).toMatchObject({
      userID: "user_123",
      callable: "acknowledgeBackendEvents",
      category: "backendEventSync",
      units: 1,
      occurredAt: now,
      metadata: {
        eventCount: 1
      }
    });
    expect(charges[0]?.auditKey).toMatch(/^[a-f0-9]{64}$/);
  });

  it("records quota for the maximum backend event batch without rejecting audit key length", async () => {
    const { guard, charges } = makeQuotaGuard({ limitUnits: 500 });
    const { dependencies, writes } = makeDependencies({ exists: false }, {
      quotaGuard: guard
    });
    const events = Array.from({ length: 25 }, (_, index) => {
      const entityID = `entity_${index}`;
      return backendEvent({
        id: eventUUID(index),
        entityID,
        idempotencyKey: `user_123-questStarted-${entityID}`,
        summary: {
          questDay: index + 1,
          xp: index
        }
      });
    });

    const response = await authed(syncPayload(events), dependencies);

    expect(response).toMatchObject({
      ok: true,
      receipts: expect.arrayContaining([
        expect.objectContaining({ eventID: eventUUID(0) }),
        expect.objectContaining({ eventID: eventUUID(24) })
      ])
    });
    expect(writes).toHaveLength(25);
    expect(charges).toHaveLength(1);
    expect(charges[0]).toMatchObject({
      callable: "acknowledgeBackendEvents",
      units: 25,
      metadata: {
        eventCount: 25
      }
    });
    expect(charges[0]?.auditKey).toMatch(/^[a-f0-9]{64}$/);
  });

  it("does not acknowledge backend events when sync quota is exhausted", async () => {
    const { guard, charges } = makeQuotaGuard({ exhausted: true, limitUnits: 500 });
    const { dependencies, reads, writes } = makeDependencies({ exists: false }, {
      quotaGuard: guard
    });

    const response = await authed(syncPayload(), dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "resource-exhausted"
    });
    expect(charges).toHaveLength(1);
    expect(reads).toEqual([]);
    expect(writes).toEqual([]);
  });

  it("allows idempotent retry only when existing server event has the same idempotency key", async () => {
    const { dependencies, writes } = makeDependencies({
      exists: true,
      idempotencyKey: `user_123-questStarted-${questID}`,
      acceptedAt: Timestamp.fromDate(new Date("2026-06-18T12:58:00.000Z"))
    });

    const response = await authed(syncPayload(), dependencies);

    expect(response).toMatchObject({
      ok: true,
      receipts: [{
        eventID,
        idempotencyKey: `user_123-questStarted-${questID}`,
        status: "acknowledged",
        acceptedAt: "2026-06-18T12:58:00.000Z"
      }]
    });
    expect(writes).toEqual([]);
  });

  it("rejects conflicting event documents before overwriting server history", async () => {
    const { dependencies, writes } = makeDependencies({
      exists: true,
      idempotencyKey: "user_123-proofClaimed-other"
    });

    const response = await authed(syncPayload(), dependencies);

    expect(response).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
    expect(writes).toEqual([]);
  });

  it("rejects unsafe request and event shapes before writing", async () => {
    const cases: Array<[string, unknown]> = [
      ["unredacted session", syncPayload([backendEvent()], {
        session: {
          ownerUserID: "user_123",
          isAuthenticated: true,
          authProvider: "firebaseAuth",
          email: "private@example.com"
        }
      })],
      ["unredacted object session", syncPayload([backendEvent()], {
        session: {
          ownerUserID: "user_123",
          isAuthenticated: true,
          authProvider: "firebaseAuth",
          email: { raw: "private@example.com" }
        }
      })],
      ["unsupported top-level field", syncPayload([backendEvent()], {
        rawPrivatePayload: "do not accept"
      })],
      ["bad session route", syncPayload([backendEvent()], {
        session: {
          ownerUserID: "user_123",
          isAuthenticated: true,
          authProvider: "firebaseAuth",
          auth: { kind: "firebaseAuth", status: 42 }
        }
      })],
      ["bad external action approval flag", syncPayload([backendEvent()], {
        session: {
          ownerUserID: "user_123",
          isAuthenticated: true,
          authProvider: "firebaseAuth",
          requiresUserApprovalForExternalActions: "yes"
        }
      })],
      ["owner mismatch", syncPayload([backendEvent({ ownerUserID: "other_user" })])],
      ["pending status", syncPayload([backendEvent({ syncStatus: "pending" })])],
      ["bad idempotency", syncPayload([backendEvent({ idempotencyKey: "wrong" })])],
      ["private summary key", syncPayload([backendEvent({
        summary: { questID, privateRawPayload: "do not store" }
      })])],
      ["loose date", syncPayload([backendEvent({ occurredAt: "June 18, 2026" })])],
      ["invalid normalized calendar date", syncPayload([
        backendEvent({ occurredAt: "2026-02-31T00:00:00.000Z" })
      ])],
      ["bad date", syncPayload([backendEvent({ occurredAt: "not-a-date" })])],
      ["duplicate IDs", syncPayload([backendEvent(), backendEvent()])],
      ["duplicate idempotency keys", syncPayload([
        backendEvent(),
        backendEvent({
          id: "33333333-3333-4333-8333-333333333333"
        })
      ])]
    ];

    for (const [label, payload] of cases) {
      const { dependencies, writes } = makeDependencies();

      const response = await authed(payload, dependencies);

      expect(response, label).toMatchObject({
        ok: false,
        code: "invalid-argument"
      });
      expect(writes, label).toEqual([]);
    }
  });
});
