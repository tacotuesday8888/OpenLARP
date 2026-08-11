import { createHash } from "node:crypto";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";

const RESERVATION_TTL_MILLISECONDS = 15 * 60 * 1_000;
const MAX_REQUEST_ID_LENGTH = 512;

type ProviderBudgetStore = Pick<Firestore, "doc" | "runTransaction">;

export type ProviderBudgetReservationDecision =
  | { ok: true; alreadyReserved: boolean }
  | { ok: false; reason: "budget" | "invalid" };

export interface ProviderBudgetGuard {
  reserve(input: {
    requestID: string;
    estimatedCostMicros: number;
    dailyBudgetMicros: number;
    occurredAt: Date;
  }): Promise<ProviderBudgetReservationDecision>;
  reconcile(input: {
    requestID: string;
    actualCostMicros: number;
    occurredAt: Date;
  }): Promise<void>;
}

export function providerBudgetDayPath(day: string): string {
  return `_serverAIUsage/providerDaily/days/${day}`;
}

export function providerBudgetReservationPath(day: string, requestID: string): string {
  return `${providerBudgetDayPath(day)}/reservations/${hashRequestID(requestID)}`;
}

export function createFirestoreProviderBudgetGuard(dependencies: {
  firestore: ProviderBudgetStore;
}): ProviderBudgetGuard {
  return {
    async reserve(input) {
      if (!isValidRequestID(input.requestID)
        || !isNonNegativeInteger(input.estimatedCostMicros)
        || !isPositiveInteger(input.dailyBudgetMicros)
        || !isValidDate(input.occurredAt)) {
        return { ok: false, reason: "invalid" };
      }

      const day = utcDay(input.occurredAt);
      const dayReference = dependencies.firestore.doc(providerBudgetDayPath(day));
      const reservationReference = dependencies.firestore.doc(
        providerBudgetReservationPath(day, input.requestID)
      );

      return dependencies.firestore.runTransaction(async (transaction) => {
        const [daySnapshot, reservationSnapshot] = await Promise.all([
          transaction.get(dayReference),
          transaction.get(reservationReference)
        ]);
        const existingReservation = reservationSnapshot.data();
        const dayLedger = daySnapshot.data();
        const storedReservedMicros = safeLedgerAmount(dayLedger?.reservedMicros);
        const actualSpentMicros = safeLedgerAmount(dayLedger?.actualSpentMicros);
        if (storedReservedMicros === null || actualSpentMicros === null) {
          return { ok: false, reason: "invalid" } as const;
        }

        let reservedMicros = storedReservedMicros;
        if (reservationSnapshot.exists) {
          const existingEstimate = safeLedgerAmount(existingReservation?.estimatedCostMicros);
          if (existingEstimate === null) {
            return { ok: false, reason: "invalid" } as const;
          }
          if (existingReservation?.status === "reconciled") {
            return existingEstimate === input.estimatedCostMicros
              ? { ok: true, alreadyReserved: true } as const
              : { ok: false, reason: "invalid" } as const;
          }
          const expiresAtMilliseconds = timestampMilliseconds(existingReservation?.expiresAt);
          if (existingReservation?.status !== "reserved" || expiresAtMilliseconds === null) {
            return { ok: false, reason: "invalid" } as const;
          }
          if (expiresAtMilliseconds > input.occurredAt.getTime()) {
            return existingEstimate === input.estimatedCostMicros
              ? { ok: true, alreadyReserved: true } as const
              : { ok: false, reason: "invalid" } as const;
          }
          reservedMicros = Math.max(reservedMicros - existingEstimate, 0);
        }

        if (actualSpentMicros + reservedMicros + input.estimatedCostMicros > input.dailyBudgetMicros) {
          return { ok: false, reason: "budget" } as const;
        }

        const occurredAt = Timestamp.fromDate(input.occurredAt);
        const resetAt = Timestamp.fromDate(nextUTCDay(input.occurredAt));
        transaction.set(dayReference, {
          schemaVersion: 1,
          scope: "providerDaily",
          day,
          dailyBudgetMicros: input.dailyBudgetMicros,
          reservedMicros: reservedMicros + input.estimatedCostMicros,
          actualSpentMicros,
          updatedAt: occurredAt,
          resetAt
        });
        const reservationDocument = {
          schemaVersion: 1,
          requestIDHash: hashRequestID(input.requestID),
          day,
          status: "reserved",
          estimatedCostMicros: input.estimatedCostMicros,
          reservedAt: occurredAt,
          expiresAt: Timestamp.fromDate(new Date(input.occurredAt.getTime() + RESERVATION_TTL_MILLISECONDS))
        };
        if (reservationSnapshot.exists) {
          transaction.set(reservationReference, reservationDocument);
        } else {
          transaction.create(reservationReference, reservationDocument);
        }
        return { ok: true, alreadyReserved: false } as const;
      });
    },

    async reconcile(input) {
      if (!isValidRequestID(input.requestID)
        || !isNonNegativeInteger(input.actualCostMicros)
        || !isValidDate(input.occurredAt)) {
        return;
      }

      const day = utcDay(input.occurredAt);
      const dayReference = dependencies.firestore.doc(providerBudgetDayPath(day));
      const reservationReference = dependencies.firestore.doc(
        providerBudgetReservationPath(day, input.requestID)
      );

      await dependencies.firestore.runTransaction(async (transaction) => {
        const [daySnapshot, reservationSnapshot] = await Promise.all([
          transaction.get(dayReference),
          transaction.get(reservationReference)
        ]);
        const reservation = reservationSnapshot.data();
        if (!reservationSnapshot.exists || reservation?.status !== "reserved") {
          return;
        }

        const estimatedCostMicros = safeLedgerAmount(reservation.estimatedCostMicros);
        const dayLedger = daySnapshot.data();
        const reservedMicros = safeLedgerAmount(dayLedger?.reservedMicros);
        const actualSpentMicros = safeLedgerAmount(dayLedger?.actualSpentMicros);
        if (estimatedCostMicros === null || reservedMicros === null || actualSpentMicros === null) {
          return;
        }

        transaction.set(dayReference, {
          reservedMicros: Math.max(reservedMicros - estimatedCostMicros, 0),
          actualSpentMicros: actualSpentMicros + input.actualCostMicros,
          updatedAt: Timestamp.fromDate(input.occurredAt)
        }, { merge: true });
        transaction.set(reservationReference, {
          status: "reconciled",
          actualCostMicros: input.actualCostMicros,
          reconciledAt: Timestamp.fromDate(input.occurredAt)
        }, { merge: true });
      });
    }
  };
}

export function adminProviderBudgetGuard(): ProviderBudgetGuard {
  return createFirestoreProviderBudgetGuard({ firestore: getFirestore() });
}

function hashRequestID(requestID: string): string {
  return createHash("sha256").update(requestID, "utf8").digest("hex");
}

function isValidRequestID(requestID: string): boolean {
  return requestID.length > 0 && requestID.length <= MAX_REQUEST_ID_LENGTH;
}

function isNonNegativeInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

function isPositiveInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}

function isValidDate(value: Date): boolean {
  return !Number.isNaN(value.getTime());
}

function safeLedgerAmount(value: unknown): number | null {
  if (value === undefined) {
    return 0;
  }
  return typeof value === "number" && isNonNegativeInteger(value) ? value : null;
}

function timestampMilliseconds(value: unknown): number | null {
  if (value instanceof Timestamp) {
    return value.toMillis();
  }
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const timestamp = value as { _seconds?: unknown; seconds?: unknown };
  const seconds = typeof timestamp.seconds === "number" ? timestamp.seconds : timestamp._seconds;
  return typeof seconds === "number" && Number.isSafeInteger(seconds) && seconds >= 0
    ? seconds * 1_000
    : null;
}

function utcDay(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function nextUTCDay(value: Date): Date {
  const next = new Date(value);
  next.setUTCHours(24, 0, 0, 0);
  return next;
}
