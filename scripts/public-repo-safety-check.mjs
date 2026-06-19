#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const BLOCKED_TRACKED_PATH_PATTERNS = [
  /(^|\/)\.DS_Store$/,
  /(^|\/)GoogleService-Info\.plist$/,
  /(^|\/)RevenueCat-Info\.plist$/,
  /(^|\/)\.env(\.|$)/,
  /\.(p8|p12|cer|mobileprovision|provisionprofile|key)$/i
];

const SECRET_TEXT_PATTERNS = [
  {
    name: "private key block",
    pattern: /-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----/
  },
  {
    name: "Firebase API key",
    pattern: /AIza[0-9A-Za-z_-]{20,}/
  },
  {
    name: "OpenAI-style API key",
    pattern: /\bsk-[A-Za-z0-9_-]{20,}\b/
  },
  {
    name: "RevenueCat iOS SDK key",
    pattern: /\b(?:appl|test)_[A-Za-z0-9]{16,}\b/
  }
];

export function blockedTrackedPaths(paths) {
  return paths.filter((path) =>
    BLOCKED_TRACKED_PATH_PATTERNS.some((pattern) => pattern.test(path))
  );
}

export function secretTextFindings(entries) {
  const findings = [];
  for (const entry of entries) {
    for (const secretPattern of SECRET_TEXT_PATTERNS) {
      if (secretPattern.pattern.test(entry.text)) {
        findings.push({
          path: entry.path,
          patternName: secretPattern.name
        });
      }
    }
  }
  return findings;
}

function trackedPaths() {
  const output = execFileSync("git", ["ls-files", "-z"], {
    encoding: "utf8"
  });
  return output.split("\0").filter(Boolean);
}

function trackedTextEntries(paths) {
  return paths.flatMap((path) => {
    let buffer;
    try {
      buffer = readFileSync(path);
    } catch {
      return [];
    }
    if (buffer.includes(0)) {
      return [];
    }
    return [{
      path,
      text: buffer.toString("utf8")
    }];
  });
}

export function runPublicRepoSafetyCheck(paths = trackedPaths()) {
  const blockedPaths = blockedTrackedPaths(paths);
  const secretFindings = secretTextFindings(trackedTextEntries(paths));
  return {
    ok: blockedPaths.length === 0 && secretFindings.length === 0,
    blockedPaths,
    secretFindings
  };
}

function main() {
  const result = runPublicRepoSafetyCheck();
  if (result.ok) {
    console.log("PASS public repo safety check");
    return;
  }

  for (const path of result.blockedPaths) {
    console.error(`Blocked tracked local/private file: ${path}`);
  }
  for (const finding of result.secretFindings) {
    console.error(`Possible secret in tracked file: ${finding.path} (${finding.patternName})`);
  }
  process.exitCode = 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
