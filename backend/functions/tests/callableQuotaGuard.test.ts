import { describe, expect, it } from "vitest";
import { type Firestore } from "firebase-admin/firestore";
import {
  CALLABLE_DAILY_QUOTA_LIMITS,
  createFirestoreCallableQuotaGuard,
  type CallableQuotaCharge
} from "../src/callableQuotaGuard.js";

type FakeDocumentReference = { path: string };
type FakeWrite =
  | {
    kind: "set";
    reference: FakeDocumentReference;
    data: Record<string, unknown>;
    merge: boolean;
  }
  | {
    kind: "create";
    reference: FakeDocumentReference;
    data: Record<string, unknown>;
  };

class FakeDocumentSnapshot {
  constructor(private readonly document: Record<string, unknown> | undefined) {}

  get exists() {
    return this.document !== undefined;
  }

  data() {
    return this.document;
  }
}

class FakeFirestore {
  readonly documents = new Map<string, Record<string, unknown>>();

  doc(path: string): FakeDocumentReference {
    return { path };
  }

  async runTransaction<T>(updateFunction: (transaction: {
    get: (reference: FakeDocumentReference) => Promise<FakeDocumentSnapshot>;
    set: (reference: FakeDocumentReference, data: Record<string, unknown>, options?: { merge?: boolean }) => void;
    create: (reference: FakeDocumentReference, data: Record<string, unknown>) => void;
  }) => Promise<T>): Promise<T> {
    const writes: FakeWrite[] = [];
    const transaction = {
      get: async (reference: FakeDocumentReference) =>
        new FakeDocumentSnapshot(cloneRecord(this.documents.get(reference.path))),
      set: (reference: FakeDocumentReference, data: Record<string, unknown>, options: { merge?: boolean } = {}) => {
        writes.push({
          kind: "set",
          reference,
          data: cloneRecord(data) ?? {},
          merge: options.merge === true
        });
      },
      create: (reference: FakeDocumentReference, data: Record<string, unknown>) => {
        writes.push({
          kind: "create",
          reference,
          data: cloneRecord(data) ?? {}
        });
      }
    };

    const result = await updateFunction(transaction);
    for (const write of writes) {
      if (write.kind === "create") {
        if (this.documents.has(write.reference.path)) {
          throw new Error(`Document already exists: ${write.reference.path}`);
        }
        this.documents.set(write.reference.path, write.data);
      } else if (write.merge) {
        const existing = this.documents.get(write.reference.path) ?? {};
        this.documents.set(write.reference.path, mergeRecords(existing, write.data));
      } else {
        this.documents.set(write.reference.path, write.data);
      }
    }
    return result;
  }
}

const now = new Date("2026-06-18T12:00:00.000Z");

function workflowCharge(overrides: Partial<CallableQuotaCharge> = {}): CallableQuotaCharge {
  return {
    userID: "user_123",
    callable: "runOpenLARPWorkflow",
    category: "aiWorkflow",
    units: 1,
    auditKey: "request-1",
    occurredAt: now,
    metadata: {
      workflowKind: "questPlan"
    },
    ...overrides
  };
}

function makeGuard() {
  const firestore = new FakeFirestore();
  const guard = createFirestoreCallableQuotaGuard({
    firestore: firestore as unknown as Firestore
  });
  return { firestore, guard };
}

describe("createFirestoreCallableQuotaGuard", () => {
  it("records every user daily callable invocation, even when audit keys repeat", async () => {
    const { firestore, guard } = makeGuard();

    const first = await guard.checkAndRecord(workflowCharge());
    const second = await guard.checkAndRecord(workflowCharge());

    expect(first).toMatchObject({
      ok: true,
      callable: "runOpenLARPWorkflow",
      usedUnits: 1,
      remainingUnits: CALLABLE_DAILY_QUOTA_LIMITS.runOpenLARPWorkflow.limitUnits - 1,
      resetAt: "2026-06-19T00:00:00.000Z"
    });
    expect(second).toMatchObject({
      ok: true,
      usedUnits: 2,
      remainingUnits: CALLABLE_DAILY_QUOTA_LIMITS.runOpenLARPWorkflow.limitUnits - 2
    });
    expect([...firestore.documents.keys()].filter((path) => path.includes("/charges/"))).toHaveLength(2);
    const dayDocument = [...firestore.documents.values()].find((document) => document.scope === "userDaily");
    expect(dayDocument).toMatchObject({
      schemaVersion: 1,
      scope: "userDaily",
      ownerUserIDHash: expect.any(String),
      day: "2026-06-18",
      totals: {
        runOpenLARPWorkflow: {
          category: "aiWorkflow",
          limitUnits: 60,
          usedUnits: 2
        }
      }
    });
    expect([...firestore.documents.keys()].join("\n")).not.toContain("user_123");
  });

  it("rejects new charges atomically when a callable daily limit is exhausted", async () => {
    const { firestore, guard } = makeGuard();

    for (let index = 0; index < CALLABLE_DAILY_QUOTA_LIMITS.runOpenLARPWorkflow.limitUnits; index += 1) {
      await expect(guard.checkAndRecord(workflowCharge({
        auditKey: `request-${index}`
      }))).resolves.toMatchObject({ ok: true });
    }

    const rejected = await guard.checkAndRecord(workflowCharge({
      auditKey: "request-over-limit"
    }));

    expect(rejected).toMatchObject({
      ok: false,
      error: {
        ok: false,
        code: "resource-exhausted",
        details: {
          schemaVersion: 1,
          scope: "userDaily",
          callable: "runOpenLARPWorkflow",
          limitUnits: 60,
          usedUnits: 60,
          requestedUnits: 1,
          resetAt: "2026-06-19T00:00:00.000Z"
        }
      }
    });
    expect([...firestore.documents.keys()].filter((path) => path.includes("/charges/"))).toHaveLength(60);
    expect(JSON.stringify(rejected)).not.toContain("request-over-limit");
    expect(JSON.stringify(rejected)).not.toContain("user_123");
  });

  it("keeps quota counters separate by callable", async () => {
    const { guard } = makeGuard();

    for (let index = 0; index < CALLABLE_DAILY_QUOTA_LIMITS.runOpenLARPWorkflow.limitUnits; index += 1) {
      await guard.checkAndRecord(workflowCharge({
        auditKey: `request-${index}`
      }));
    }

    const promotion = await guard.checkAndRecord({
      userID: "user_123",
      callable: "promoteProofUploadReceipt",
      category: "proofUpload",
      units: 1,
      auditKey: "user_123-attachment_123",
      occurredAt: now,
      metadata: {
        contentType: "image/png"
      }
    });

    expect(promotion).toMatchObject({
      ok: true,
      callable: "promoteProofUploadReceipt",
      usedUnits: 1
    });
  });
});

function cloneRecord(value: Record<string, unknown> | undefined): Record<string, unknown> | undefined {
  if (value === undefined) {
    return undefined;
  }
  return { ...value };
}

function mergeRecords(target: Record<string, unknown>, source: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = { ...target };
  for (const [key, value] of Object.entries(source)) {
    const existing = result[key];
    if (isPlainRecord(existing) && isPlainRecord(value)) {
      result[key] = mergeRecords(existing, value);
    } else {
      result[key] = value;
    }
  }
  return result;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}
