import {
  type CallableQuotaCharge,
  type CallableQuotaDecision,
  type CallableQuotaGuard
} from "../src/callableQuotaGuard.js";

export function makeQuotaGuard(options: { exhausted?: boolean; limitUnits?: number } = {}) {
  const charges: CallableQuotaCharge[] = [];
  const limitUnits = options.limitUnits ?? 60;
  const guard: CallableQuotaGuard = {
    async checkAndRecord(charge) {
      charges.push(charge);
      if (options.exhausted) {
        return {
          ok: false,
          error: {
            ok: false,
            code: "resource-exhausted",
            message: "OpenLARP daily callable quota exceeded.",
            details: {
              schemaVersion: 1,
              scope: "userDaily",
              callable: charge.callable,
              limitUnits,
              usedUnits: limitUnits,
              requestedUnits: charge.units,
              resetAt: "2026-06-19T00:00:00.000Z"
            }
          }
        };
      }

      return {
        ok: true,
        schemaVersion: 1,
        scope: "userDaily",
        callable: charge.callable,
        limitUnits,
        usedUnits: charge.units,
        remainingUnits: limitUnits - charge.units,
        resetAt: "2026-06-19T00:00:00.000Z"
      } satisfies CallableQuotaDecision;
    }
  };
  return { guard, charges };
}
