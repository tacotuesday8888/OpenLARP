import { describe, expect, it } from "vitest";
import type { Firestore } from "firebase-admin/firestore";
import {
  createFirestoreProviderBudgetGuard,
  providerBudgetDayPath,
  providerBudgetReservationPath
} from "../src/providerBudgetGuard.js";

type Reference = { path: string };

class Snapshot {
  constructor(private readonly value: Record<string, unknown> | undefined) {}
  get exists() { return this.value !== undefined; }
  data() { return this.value ? structuredClone(this.value) : undefined; }
}

class FakeFirestore {
  readonly documents = new Map<string, Record<string, unknown>>();
  doc(path: string): Reference { return { path }; }

  async runTransaction<T>(run: (transaction: {
    get: (reference: Reference) => Promise<Snapshot>;
    set: (reference: Reference, data: Record<string, unknown>, options?: { merge?: boolean }) => void;
    create: (reference: Reference, data: Record<string, unknown>) => void;
  }) => Promise<T>): Promise<T> {
    const writes: Array<{
      kind: "set" | "create";
      reference: Reference;
      data: Record<string, unknown>;
      merge: boolean;
    }> = [];
    const result = await run({
      get: async (reference) => new Snapshot(this.documents.get(reference.path)),
      set: (reference, data, options) => writes.push({
        kind: "set", reference, data: structuredClone(data), merge: options?.merge === true
      }),
      create: (reference, data) => writes.push({
        kind: "create", reference, data: structuredClone(data), merge: false
      })
    });
    for (const write of writes) {
      if (write.kind === "create" && this.documents.has(write.reference.path)) {
        throw new Error("duplicate create");
      }
      const existing = write.merge ? this.documents.get(write.reference.path) ?? {} : {};
      this.documents.set(write.reference.path, { ...existing, ...write.data });
    }
    return result;
  }
}

const now = new Date("2026-08-10T10:00:00.000Z");

function setup() {
  const firestore = new FakeFirestore();
  const guard = createFirestoreProviderBudgetGuard({ firestore: firestore as unknown as Firestore });
  return { firestore, guard };
}

describe("createFirestoreProviderBudgetGuard", () => {
  it("uses valid Firestore document paths for day ledgers and reservations", () => {
    expect(providerBudgetDayPath("2026-08-10").split("/")).toHaveLength(4);
    expect(providerBudgetReservationPath("2026-08-10", "request-1").split("/")).toHaveLength(6);
  });

  it("reserves estimated cost atomically and stores only hashed request identity", async () => {
    const { firestore, guard } = setup();
    const decision = await guard.reserve({
      requestID: "private-request-id",
      estimatedCostMicros: 400,
      dailyBudgetMicros: 1_000,
      occurredAt: now
    });

    expect(decision).toEqual({ ok: true, alreadyReserved: false });
    expect(firestore.documents.get(providerBudgetDayPath("2026-08-10"))).toMatchObject({
      scope: "providerDaily",
      day: "2026-08-10",
      reservedMicros: 400,
      actualSpentMicros: 0
    });
    const serialized = JSON.stringify([...firestore.documents]);
    expect(serialized).not.toContain("private-request-id");
    expect(firestore.documents.has(providerBudgetReservationPath("2026-08-10", "private-request-id"))).toBe(true);
  });

  it("is idempotent for the same request and estimate", async () => {
    const { firestore, guard } = setup();
    const input = { requestID: "request-1", estimatedCostMicros: 400, dailyBudgetMicros: 1_000, occurredAt: now };

    await expect(guard.reserve(input)).resolves.toEqual({ ok: true, alreadyReserved: false });
    await expect(guard.reserve(input)).resolves.toEqual({ ok: true, alreadyReserved: true });
    expect(firestore.documents.get(providerBudgetDayPath("2026-08-10"))).toMatchObject({ reservedMicros: 400 });
  });

  it("rejects a reservation that would exceed the actual plus reserved daily budget", async () => {
    const { guard } = setup();
    await guard.reserve({ requestID: "request-1", estimatedCostMicros: 700, dailyBudgetMicros: 1_000, occurredAt: now });

    await expect(guard.reserve({
      requestID: "request-2",
      estimatedCostMicros: 301,
      dailyBudgetMicros: 1_000,
      occurredAt: now
    })).resolves.toEqual({ ok: false, reason: "budget" });
  });

  it("reconciles estimated reservation to actual provider usage exactly once", async () => {
    const { firestore, guard } = setup();
    await guard.reserve({ requestID: "request-1", estimatedCostMicros: 400, dailyBudgetMicros: 1_000, occurredAt: now });

    await guard.reconcile({ requestID: "request-1", actualCostMicros: 175, occurredAt: now });
    await guard.reconcile({ requestID: "request-1", actualCostMicros: 175, occurredAt: now });

    expect(firestore.documents.get(providerBudgetDayPath("2026-08-10"))).toMatchObject({
      reservedMicros: 0,
      actualSpentMicros: 175
    });
    expect(firestore.documents.get(providerBudgetReservationPath("2026-08-10", "request-1"))).toMatchObject({
      status: "reconciled",
      estimatedCostMicros: 400,
      actualCostMicros: 175
    });
  });

  it("releases and replaces an expired reservation instead of permanently consuming budget", async () => {
    const { firestore, guard } = setup();
    await guard.reserve({
      requestID: "request-1",
      estimatedCostMicros: 400,
      dailyBudgetMicros: 1_000,
      occurredAt: now
    });

    const replacementTime = new Date("2026-08-10T10:16:00.000Z");
    await expect(guard.reserve({
      requestID: "request-1",
      estimatedCostMicros: 250,
      dailyBudgetMicros: 1_000,
      occurredAt: replacementTime
    })).resolves.toEqual({ ok: true, alreadyReserved: false });

    expect(firestore.documents.get(providerBudgetDayPath("2026-08-10"))).toMatchObject({
      reservedMicros: 250,
      actualSpentMicros: 0
    });
    expect(firestore.documents.get(providerBudgetReservationPath("2026-08-10", "request-1"))).toMatchObject({
      status: "reserved",
      estimatedCostMicros: 250
    });
  });
});
