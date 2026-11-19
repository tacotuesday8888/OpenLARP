import { describe, expect, it } from "vitest";
import { evaluateProductionAuditReport } from "../production-dependency-audit.mjs";

function finding(name, severity, isDirect = false) {
  return { name, severity, isDirect, via: [{ dependency: name, severity }] };
}

function report(...findings) {
  const counts = { info: 0, low: 0, moderate: 0, high: 0, critical: 0, total: findings.length };
  for (const entry of findings) counts[entry.severity] += 1;
  return {
    auditReportVersion: 2,
    vulnerabilities: Object.fromEntries(findings.map((item) => [item.name, item])),
    metadata: { vulnerabilities: counts }
  };
}

describe("evaluateProductionAuditReport", () => {
  it("accepts a clean report and lower-severity direct or transitive findings", () => {
    expect(evaluateProductionAuditReport(report()).ok).toBe(true);
    const parent = { ...finding("parent", "moderate", true), via: ["nested"] };
    const result = evaluateProductionAuditReport(report(parent, finding("nested", "moderate"), finding("library", "low")));
    expect(result.ok).toBe(true);
  });

  it.each(["high", "critical"])("rejects %s findings on any dependency", (severity) => {
    for (const direct of [true, false]) {
      expect(evaluateProductionAuditReport(report(finding("dependency", severity, direct))).ok).toBe(false);
    }
  });

  it("rejects the exact previously accepted set of transitive high findings", () => {
    const names = [
      "@genkit-ai/core", "@genkit-ai/google-cloud", "@opentelemetry/auto-instrumentations-node",
      "@opentelemetry/propagator-jaeger", "@opentelemetry/sdk-node", "@opentelemetry/sdk-trace-node"
    ];
    const findings = names.map((name) => finding(name, "high"));
    expect(evaluateProductionAuditReport(report(...findings)).ok).toBe(false);
  });

  it.each([
    ["unsupported version", (r) => { r.auditReportVersion = 1; }],
    ["missing count", (r) => { delete r.metadata.vulnerabilities.high; }],
    ["negative count", (r) => { r.metadata.vulnerabilities.critical = -1; }],
    ["fractional count", (r) => { r.metadata.vulnerabilities.high = 0.5; }],
    ["inconsistent total", (r) => { r.metadata.vulnerabilities.total = 0; }],
    ["inconsistent severity count", (r) => { r.metadata.vulnerabilities.low = 0; }],
    ["absent entry map", (r) => { r.vulnerabilities = []; }],
    ["missing entry", (r) => { r.vulnerabilities.lib = null; }],
    ["wrong package", (r) => { r.vulnerabilities.lib.name = "other"; }],
    ["unknown severity", (r) => { r.vulnerabilities.lib.severity = "unknown"; }],
    ["missing directness", (r) => { delete r.vulnerabilities.lib.isDirect; }],
    ["unclassified advisory", (r) => { r.vulnerabilities.lib.via = [{}]; }],
    ["unresolved dependency", (r) => { r.vulnerabilities.lib.via = ["missing"]; }],
    ["empty cause list", (r) => { r.vulnerabilities.lib.via = []; }],
    ["hidden high advisory", (r) => { r.vulnerabilities.lib.via[0].severity = "high"; }],
    ["registry error", (r) => { r.error = { code: "E503" }; }]
  ])("rejects malformed reports with %s", (_label, change) => {
    const r = report(finding("lib", "low"));
    change(r);
    expect(evaluateProductionAuditReport(r).ok).toBe(false);
  });
});
