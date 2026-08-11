#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

export const ACCEPTED_CONTROLLED_BETA_HIGH_PACKAGES = Object.freeze([
  "@genkit-ai/core",
  "@genkit-ai/google-cloud",
  "@opentelemetry/auto-instrumentations-node",
  "@opentelemetry/propagator-jaeger",
  "@opentelemetry/sdk-node",
  "@opentelemetry/sdk-trace-node"
]);

export function evaluateProductionAuditReport(report) {
  const counts = report?.metadata?.vulnerabilities;
  const vulnerabilities = report?.vulnerabilities;
  if (
    report?.auditReportVersion !== 2 ||
    !counts ||
    !Number.isInteger(counts.critical) ||
    !Number.isInteger(counts.high) ||
    !vulnerabilities ||
    typeof vulnerabilities !== "object" ||
    Array.isArray(vulnerabilities)
  ) {
    return failure("Production dependency audit report format was invalid.");
  }

  const entries = Object.values(vulnerabilities);
  if (counts.critical > 0 || entries.some((entry) => entry?.severity === "critical")) {
    return failure("Production dependency audit found a critical vulnerability.");
  }

  const highEntries = entries.filter((entry) => entry?.severity === "high");
  if (highEntries.length !== counts.high) {
    return failure("Production dependency audit high-severity counts were inconsistent.");
  }
  if (highEntries.some((entry) => entry?.isDirect === true)) {
    return failure("Production dependency audit found a direct high-severity vulnerability.");
  }

  const actualHighPackages = highEntries
    .map((entry) => entry?.name)
    .filter((name) => typeof name === "string")
    .sort();
  const acceptedHighPackages = [...ACCEPTED_CONTROLLED_BETA_HIGH_PACKAGES].sort();
  if (
    actualHighPackages.length !== acceptedHighPackages.length ||
    actualHighPackages.some((name, index) => name !== acceptedHighPackages[index])
  ) {
    return failure("Production dependency audit high-severity residual changed and requires review.");
  }

  return {
    ok: true,
    acceptedTransitiveHighCount: acceptedHighPackages.length,
    message: `Production dependency audit accepted ${acceptedHighPackages.length} enumerated transitive high findings for controlled beta.`
  };
}

function failure(message) {
  return { ok: false, acceptedTransitiveHighCount: 0, message };
}

function runCLI() {
  const audit = spawnSync("npm", ["audit", "--omit=dev", "--json"], {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024
  });
  if (audit.error || !audit.stdout) {
    console.error("BLOCKER production dependency audit could not run.");
    process.exit(1);
  }

  let report;
  try {
    report = JSON.parse(audit.stdout);
  } catch {
    console.error("BLOCKER production dependency audit did not return JSON.");
    process.exit(1);
  }
  const result = evaluateProductionAuditReport(report);
  console.log(`${result.ok ? "PASS" : "BLOCKER"} ${result.message}`);
  process.exit(result.ok ? 0 : 1);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  runCLI();
}
