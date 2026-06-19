import { createHash, randomUUID } from "node:crypto";
import { getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

export type OpenLARPCallableName =
  | "runOpenLARPWorkflow"
  | "promoteProofUploadReceipt"
  | "reconcileProofUploads"
  | "cleanupRevokedPrivateEvidenceUploads"
  | "acknowledgeBackendEvents";

export type CallableQuotaCategory =
  | "aiWorkflow"
  | "proofUpload"
  | "proofUploadRepair"
  | "privateEvidenceRetention"
  | "backendEventSync";

export type CallableQuotaMetadataValue = string | number | boolean;

export type CallableQuotaCharge = {
  userID: string;
  callable: OpenLARPCallableName;
  category: CallableQuotaCategory;
  units: number;
  occurredAt: Date;
  auditKey?: string;
  metadata?: Record<string, CallableQuotaMetadataValue>;
};

export type CallableQuotaDecision =
  | {
    ok: true;
    schemaVersion: 1;
    scope: "userDaily";
    callable: OpenLARPCallableName;
    limitUnits: number;
    usedUnits: number;
    remainingUnits: number;
    resetAt: string;
  }
  | { ok: false; error: OpenLARPFunctionError };

export type CallableQuotaGuard = {
  checkAndRecord: (charge: CallableQuotaCharge) => Promise<CallableQuotaDecision>;
};

type CallableQuotaLimit = {
  category: CallableQuotaCategory;
  limitUnits: number;
};

type FirestoreQuotaStore = Pick<Firestore, "doc" | "runTransaction">;

export type FirestoreCallableQuotaGuardDependencies = {
  firestore: FirestoreQuotaStore;
};

export const CALLABLE_DAILY_QUOTA_LIMITS = {
  runOpenLARPWorkflow: {
    category: "aiWorkflow",
    limitUnits: 60
  },
  promoteProofUploadReceipt: {
    category: "proofUpload",
    limitUnits: 150
  },
  reconcileProofUploads: {
    category: "proofUploadRepair",
    limitUnits: 30
  },
  cleanupRevokedPrivateEvidenceUploads: {
    category: "privateEvidenceRetention",
    limitUnits: 30
  },
  acknowledgeBackendEvents: {
    category: "backendEventSync",
    limitUnits: 500
  }
} as const satisfies Record<OpenLARPCallableName, CallableQuotaLimit>;

export function adminCallableQuotaGuard(): CallableQuotaGuard {
  return createFirestoreCallableQuotaGuard({
    firestore: getFirestore()
  });
}

export function createFirestoreCallableQuotaGuard(
  dependencies: FirestoreCallableQuotaGuardDependencies
): CallableQuotaGuard {
  return {
    async checkAndRecord(charge) {
      const validation = validateCharge(charge);
      if (!validation.ok) {
        return validation;
      }

      const dayKey = dayKeyFor(validation.charge.occurredAt);
      const resetAt = resetAtForDay(dayKey);
      const quotaLimit = CALLABLE_DAILY_QUOTA_LIMITS[validation.charge.callable];
      const userBucketID = hashValue(validation.charge.userID).slice(0, 40);
      const chargeNonce = randomUUID();
      const chargeID = hashValue([
        "callableQuotaCharge",
        userBucketID,
        dayKey,
        validation.charge.callable,
        chargeNonce
      ].join(":"));
      const dayReference = dependencies.firestore.doc(callableQuotaDayPath(userBucketID, dayKey));
      const chargeReference = dependencies.firestore.doc(`${dayReference.path}/charges/${chargeID}`);

      return dependencies.firestore.runTransaction(async (transaction) => {
        const daySnapshot = await transaction.get(dayReference);
        const usedUnits = usedUnitsForCallable(daySnapshot.data(), validation.charge.callable);

        const nextUsedUnits = usedUnits + validation.charge.units;
        if (nextUsedUnits > quotaLimit.limitUnits) {
          return {
            ok: false,
            error: quotaExceededError({
              callable: validation.charge.callable,
              limitUnits: quotaLimit.limitUnits,
              usedUnits,
              requestedUnits: validation.charge.units,
              resetAt
            })
          };
        }

        const occurredAtTimestamp = Timestamp.fromDate(validation.charge.occurredAt);
        const resetAtTimestamp = Timestamp.fromDate(resetAt);
        transaction.set(dayReference, {
          schemaVersion: 1,
          scope: "userDaily",
          ownerUserIDHash: userBucketID,
          day: dayKey,
          resetAt: resetAtTimestamp,
          updatedAt: occurredAtTimestamp,
          totals: {
            [validation.charge.callable]: {
              category: quotaLimit.category,
              limitUnits: quotaLimit.limitUnits,
              usedUnits: nextUsedUnits,
              lastChargedAt: occurredAtTimestamp
            }
          }
        }, { merge: true });
        const chargeDocument: Record<string, unknown> = {
          schemaVersion: 1,
          scope: "userDaily",
          ownerUserIDHash: userBucketID,
          day: dayKey,
          callable: validation.charge.callable,
          category: validation.charge.category,
          units: validation.charge.units,
          chargedAt: occurredAtTimestamp,
          resetAt: resetAtTimestamp,
          metadata: validation.charge.metadata ?? {}
        };
        if (validation.charge.auditKey) {
          chargeDocument.auditKeyHash = hashValue(validation.charge.auditKey);
        }
        transaction.create(chargeReference, chargeDocument);

        return {
          ok: true,
          schemaVersion: 1,
          scope: "userDaily",
          callable: validation.charge.callable,
          limitUnits: quotaLimit.limitUnits,
          usedUnits: nextUsedUnits,
          remainingUnits: Math.max(quotaLimit.limitUnits - nextUsedUnits, 0),
          resetAt: resetAt.toISOString()
        };
      });
    }
  };
}

export function callableQuotaDayPath(userBucketID: string, dayKey: string): string {
  return `_serverUsage/${userBucketID}/days/${dayKey}`;
}

function validateCharge(
  charge: CallableQuotaCharge
): { ok: true; charge: CallableQuotaCharge } | { ok: false; error: OpenLARPFunctionError } {
  if (typeof charge.userID !== "string" || charge.userID.trim().length === 0) {
    return invalidCharge("Callable quota charge requires a signed-in user.");
  }
  if (CALLABLE_DAILY_QUOTA_LIMITS[charge.callable] === undefined) {
    return invalidCharge("Callable quota charge used an unknown callable.");
  }
  if (CALLABLE_DAILY_QUOTA_LIMITS[charge.callable].category !== charge.category) {
    return invalidCharge("Callable quota charge category did not match the callable.");
  }
  if (
    typeof charge.units !== "number" ||
    !Number.isInteger(charge.units) ||
    charge.units <= 0 ||
    charge.units > CALLABLE_DAILY_QUOTA_LIMITS[charge.callable].limitUnits
  ) {
    return invalidCharge("Callable quota charge units were outside the allowed range.");
  }
  if (!(charge.occurredAt instanceof Date) || !Number.isFinite(charge.occurredAt.getTime())) {
    return invalidCharge("Callable quota charge requires a valid occurredAt date.");
  }
  if (charge.auditKey !== undefined && (charge.auditKey.length === 0 || charge.auditKey.length > 512)) {
    return invalidCharge("Callable quota charge audit key was invalid.");
  }
  if (!isSafeMetadata(charge.metadata)) {
    return invalidCharge("Callable quota metadata must be a flat safe object.");
  }
  return { ok: true, charge };
}

function quotaExceededError(input: {
  callable: OpenLARPCallableName;
  limitUnits: number;
  usedUnits: number;
  requestedUnits: number;
  resetAt: Date;
}): OpenLARPFunctionError {
  return functionError(
    "resource-exhausted",
    "OpenLARP daily callable quota exceeded. Try again after the quota reset.",
    {
      schemaVersion: 1,
      scope: "userDaily",
      callable: input.callable,
      limitUnits: input.limitUnits,
      usedUnits: input.usedUnits,
      requestedUnits: input.requestedUnits,
      resetAt: input.resetAt.toISOString()
    }
  );
}

function invalidCharge(message: string): { ok: false; error: OpenLARPFunctionError } {
  return {
    ok: false,
    error: functionError("invalid-argument", message)
  };
}

function dayKeyFor(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function resetAtForDay(dayKey: string): Date {
  const resetAt = new Date(`${dayKey}T00:00:00.000Z`);
  resetAt.setUTCDate(resetAt.getUTCDate() + 1);
  return resetAt;
}

function usedUnitsForCallable(data: Record<string, unknown> | undefined, callable: OpenLARPCallableName): number {
  if (!isRecord(data?.totals)) {
    return 0;
  }

  const callableTotal = data.totals[callable];
  if (!isRecord(callableTotal)) {
    return 0;
  }

  const usedUnits = callableTotal.usedUnits;
  return typeof usedUnits === "number" && Number.isFinite(usedUnits) && usedUnits > 0
    ? Math.floor(usedUnits)
    : 0;
}

function isSafeMetadata(value: Record<string, CallableQuotaMetadataValue> | undefined): boolean {
  if (value === undefined) {
    return true;
  }

  return Object.entries(value).every(([key, entry]) =>
    /^[A-Za-z][A-Za-z0-9_]{0,40}$/.test(key) &&
    (
      typeof entry === "string" ||
      typeof entry === "number" ||
      typeof entry === "boolean"
    ) &&
    (typeof entry !== "string" || entry.length <= 160) &&
    (typeof entry !== "number" || Number.isFinite(entry))
  );
}

function hashValue(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
