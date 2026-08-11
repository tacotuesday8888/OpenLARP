import { describe, expect, it } from "vitest";
import {
  ACCEPTED_CONTROLLED_BETA_HIGH_PACKAGES,
  evaluateProductionAuditReport
} from "../production-dependency-audit.mjs";

function report(overrides = {}) {
  const highPackages = overrides.highPackages ?? ACCEPTED_CONTROLLED_BETA_HIGH_PACKAGES;
  const vulnerabilities = Object.fromEntries(highPackages.map((name) => [name, {
    name,
    severity: "high",
    isDirect: false,
    via: [],
    effects: [],
    range: "*",
    nodes: [`node_modules/${name}`],
    fixAvailable: false
  }]));
  return {
    auditReportVersion: 2,
    vulnerabilities,
    metadata: {
      vulnerabilities: {
        info: 0,
        low: 1,
        moderate: 5,
        high: highPackages.length,
        critical: 0,
        total: highPackages.length + 6
      }
    }
  };
}

describe("evaluateProductionAuditReport", () => {
  it("accepts only the enumerated transitive high residual for controlled beta", () => {
    const result = evaluateProductionAuditReport(report());
    expect(result).toEqual({
      ok: true,
      acceptedTransitiveHighCount: 6,
      message: "Production dependency audit accepted 6 enumerated transitive high findings for controlled beta."
    });
  });

  it("rejects critical, direct high, newly introduced high, and malformed reports", () => {
    const critical = report();
    critical.metadata.vulnerabilities.critical = 1;
    expect(evaluateProductionAuditReport(critical)).toMatchObject({ ok: false });

    const direct = report();
    direct.vulnerabilities[ACCEPTED_CONTROLLED_BETA_HIGH_PACKAGES[0]].isDirect = true;
    expect(evaluateProductionAuditReport(direct)).toMatchObject({ ok: false });

    expect(evaluateProductionAuditReport(report({
      highPackages: [...ACCEPTED_CONTROLLED_BETA_HIGH_PACKAGES, "new-high-package"]
    }))).toMatchObject({ ok: false });
    expect(evaluateProductionAuditReport({ auditReportVersion: 1 })).toMatchObject({ ok: false });
  });
});
