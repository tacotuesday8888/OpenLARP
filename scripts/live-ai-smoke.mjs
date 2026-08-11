#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { GoogleAuth } from "google-auth-library";

const FALLBACK_REASONS = new Set([
  "disabled", "policy", "quota", "budget", "timeout", "provider", "invalidOutput", "unsafeOutput"
]);
const LATENCY_BUCKETS = new Set(["notRun", "under1s", "under5s", "under15s", "over15s"]);
const SAFE_IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;

export async function runLiveAISmoke(input) {
  const serviceURL = parseServiceURL(input.serviceURL);
  const requestID = randomUUID();
  const getIdTokenClient = input.getIdTokenClient ?? (async (audience) =>
    new GoogleAuth().getIdTokenClient(audience)
  );
  const client = await getIdTokenClient(serviceURL.origin);
  const response = await client.request({
    url: `${serviceURL.origin}/v1/workflows:run`,
    method: "POST",
    data: syntheticRequest(requestID),
    timeout: 20_000,
    responseType: "json",
    maxContentLength: 256 * 1024,
    maxRedirects: 0,
    validateStatus: (status) => status >= 200 && status < 300
  });

  const data = response?.data;
  const execution = data?.execution;
  if (
    response?.status !== 200 ||
    data?.ok !== true ||
    data?.schemaVersion !== 1 ||
    data?.requestID !== requestID ||
    data?.kind !== "cookedDiagnostic" ||
    data?.externalActionTaken !== false ||
    !validCookedDiagnostic(data?.result) ||
    !validExecution(execution)
  ) {
    throw new Error("Live AI smoke response failed validation.");
  }

  const summary = {
    status: response.status,
    workflowKind: data.kind,
    liveModelCallsEnabled: execution.liveModelCallsEnabled,
    liveModelUsed: execution.liveModelUsed,
    usedFallback: execution.usedFallback,
    fallbackReason: execution.fallbackReason,
    latencyBucket: execution.usage.latencyBucket,
    promptVersion: execution.promptVersion,
    inputTokens: execution.usage.inputTokens,
    outputTokens: execution.usage.outputTokens
  };
  if (input.requireLive && !summary.liveModelUsed) {
    throw new Error("Live AI smoke completed through fallback while --require-live was set.");
  }
  (input.log ?? console.log)(JSON.stringify(summary));
  return summary;
}

function parseServiceURL(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("--service-url must be a valid HTTPS Cloud Run service origin.");
  }
  if (
    url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
    (url.pathname !== "" && url.pathname !== "/")
  ) {
    throw new Error("--service-url must be a credential-free HTTPS service origin.");
  }
  return url;
}

function validExecution(execution) {
  if (
    execution?.schemaVersion !== 1 ||
    typeof execution.liveModelCallsEnabled !== "boolean" ||
    typeof execution.liveModelUsed !== "boolean" ||
    typeof execution.usedFallback !== "boolean" ||
    !SAFE_IDENTIFIER.test(execution.policyRevision ?? "") ||
    (execution.promptVersion !== null && !SAFE_IDENTIFIER.test(execution.promptVersion ?? "")) ||
    !Number.isSafeInteger(execution.usage?.inputTokens) || execution.usage.inputTokens < 0 ||
    !Number.isSafeInteger(execution.usage?.outputTokens) || execution.usage.outputTokens < 0 ||
    !LATENCY_BUCKETS.has(execution.usage?.latencyBucket)
  ) {
    return false;
  }
  if (execution.liveModelUsed && (!execution.liveModelCallsEnabled || execution.usedFallback)) return false;
  if (execution.usedFallback) {
    if (!FALLBACK_REASONS.has(execution.fallbackReason)) return false;
  } else if (execution.fallbackReason !== null) {
    return false;
  }
  if (!execution.liveModelUsed && !execution.usedFallback) return false;
  return true;
}

function validCookedDiagnostic(result) {
  if (!result || typeof result !== "object" || Array.isArray(result)) return false;
  if (!boundedInteger(result.score, 0, 100) || !boundedInteger(result.readinessBaseline, 0, 100)) {
    return false;
  }
  const stringFields = [
    ["label", 80],
    ["mainGap", 500],
    ["strongestSignal", 500],
    ["fastestFix", 500],
    ["uncertaintyExplanation", 700],
    ["firstAction", 500]
  ];
  if (stringFields.some(([field, maximum]) => !boundedString(result[field], maximum))) {
    return false;
  }
  return boundedStringArray(result.strongestSignals, 1, 4, 500) &&
    boundedStringArray(result.readinessGaps, 1, 4, 500) &&
    boundedStringArray(result.missingInformation, 0, 4, 500);
}

function boundedInteger(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function boundedString(value, maximum) {
  return typeof value === "string" && value.length >= 1 && value.length <= maximum;
}

function boundedStringArray(value, minimum, maximum, stringMaximum) {
  return Array.isArray(value) && value.length >= minimum && value.length <= maximum &&
    value.every((item) => boundedString(item, stringMaximum));
}

function syntheticRequest(requestID) {
  return {
    schemaVersion: 1,
    envelope: {
      schemaVersion: 1,
      run: {
        schemaVersion: 1,
        kind: "cookedDiagnostic",
        providerRoute: "cloudRunGenkit",
        requestedAt: new Date().toISOString(),
        requestID,
        privacy: {
          memoryMode: "localOnly",
          allowsLongTermMemoryWrite: false,
          requiresUserApprovalForExternalActions: true,
          shareWins: false,
          allowsPrivateEvidenceCloudSync: false
        }
      },
      safetyRules: {
        hardBannedClaims: ["Never fabricate an employer or any other substantial career claim."],
        requiredBehaviors: ["Separate facts, inferences, unknowns, and advice."],
        privacyRequirements: ["External actions require user approval before the system can act."]
      },
      payload: {
        goal: {
          currentStatus: "Synthetic development smoke profile",
          targetRole: "iOS engineer",
          timeline: "12 weeks",
          background: "One synthetic class project used only for a bounded development smoke check.",
          existingProof: "Synthetic project notes.",
          confidence: 3,
          biggestBlocker: "Needs stronger role-specific proof."
        }
      }
    },
    policy: {
      enabled: true,
      policyRevision: "smoke-v1",
      timeoutMs: 15_000,
      maxOutputTokens: 1200
    }
  };
}

async function runCLI() {
  let serviceURL = "";
  let requireLive = false;
  const args = process.argv.slice(2);
  while (args.length > 0) {
    const argument = args.shift();
    if (argument === "--service-url") serviceURL = args.shift() ?? "";
    else if (argument === "--require-live") requireLive = true;
    else throw new Error("Usage: scripts/live-ai-smoke.sh --service-url URL [--require-live]");
  }
  if (!serviceURL) throw new Error("Usage: scripts/live-ai-smoke.sh --service-url URL [--require-live]");
  await runLiveAISmoke({ serviceURL, requireLive });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  runCLI().catch((error) => {
    console.error(error instanceof Error ? error.message : "Live AI smoke failed.");
    process.exit(1);
  });
}
