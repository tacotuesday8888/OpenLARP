#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const severityLevels = ["info", "low", "moderate", "high", "critical"];
const invalidReport = { ok: false, message: "Production dependency audit report was invalid." };

export function evaluateProductionAuditReport(report) {
  const counts = report?.metadata?.vulnerabilities;
  const vulnerabilities = report?.vulnerabilities;
  if (
    report?.auditReportVersion !== 2 ||
    report.error ||
    ![...severityLevels, "total"].every((key) => Number.isSafeInteger(counts?.[key]) && counts[key] >= 0) ||
    !vulnerabilities ||
    typeof vulnerabilities !== "object" ||
    Array.isArray(vulnerabilities)
  ) {
    return invalidReport;
  }

  const entries = Object.entries(vulnerabilities);
  const observed = Object.fromEntries(severityLevels.map((level) => [level, 0]));
  for (const [name, entry] of entries) {
    if (
      !name || entry?.name !== name || !severityLevels.includes(entry.severity) ||
      typeof entry.isDirect !== "boolean" || !Array.isArray(entry.via) || entry.via.length === 0
    ) {
      return invalidReport;
    }
    for (const cause of entry.via) {
      if (typeof cause === "string" && Object.hasOwn(vulnerabilities, cause)) continue;
      if (!severityLevels.includes(cause?.severity) ||
          severityLevels.indexOf(cause.severity) > severityLevels.indexOf(entry.severity)) {
        return invalidReport;
      }
    }
    observed[entry.severity] += 1;
  }

  if (entries.length !== counts.total || severityLevels.some((level) => observed[level] !== counts[level])) {
    return invalidReport;
  }
  if (counts.high > 0 || counts.critical > 0) {
    return { ok: false, message: `Production dependency audit found ${counts.high} high and ${counts.critical} critical findings.` };
  }

  return {
    ok: true,
    message: "Production dependency audit found zero high or critical findings."
  };
}

function auditLockfile(directory, options = []) {
  const args = ["--prefix", directory, "audit", "--package-lock-only", "--omit=dev", "--audit-level=high", "--json", ...options];
  const audit = spawnSync("npm", args, {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024
  });
  if (audit.error || audit.signal || !audit.stdout) {
    return { ok: false, message: "Production dependency audit could not run." };
  }

  let report;
  try {
    report = JSON.parse(audit.stdout);
  } catch {
    return { ok: false, message: "Production dependency audit did not return JSON." };
  }
  const result = evaluateProductionAuditReport(report);
  if (result.ok && audit.status !== 0) {
    return { ok: false, message: "npm audit returned an unsuccessful exit status." };
  }
  return result;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const audits = [
    ["Workspace", auditLockfile(".")],
    ["Firebase Functions", auditLockfile("backend/functions", ["--workspaces=false"])]
  ];
  for (const [label, result] of audits) {
    console.log(`${result.ok ? "PASS" : "BLOCKER"} ${label}: ${result.message}`);
  }
  process.exitCode = audits.every(([, result]) => result.ok) ? 0 : 1;
}
