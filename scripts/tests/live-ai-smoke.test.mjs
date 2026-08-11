import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { internalWorkflowRequestSchema } from "../../backend/ai/src/internalServiceContracts.js";
import { runLiveAISmoke } from "../live-ai-smoke.mjs";

const repoRoot = resolve(import.meta.dirname, "../..");

function diagnosticResult(marker = "synthetic private career marker") {
  return {
    score: 52,
    label: "Building proof",
    mainGap: marker,
    strongestSignal: "One relevant class project",
    fastestFix: "Publish a concise project case study",
    readinessBaseline: 52,
    strongestSignals: ["One relevant class project"],
    readinessGaps: [marker],
    missingInformation: ["No work sample link supplied"],
    uncertaintyExplanation: "The smoke profile is intentionally sparse.",
    firstAction: "Draft the project case study outline."
  };
}

function serviceResponse(requestID, overrides = {}) {
  return {
    status: 200,
    data: {
      ok: true,
      schemaVersion: 1,
      requestID,
      kind: "cookedDiagnostic",
      externalActionTaken: false,
      result: diagnosticResult(),
      execution: {
        schemaVersion: 1,
        liveModelCallsEnabled: true,
        liveModelUsed: true,
        usedFallback: false,
        fallbackReason: null,
        promptVersion: "openlarp.cooked.v1",
        policyRevision: "smoke-v1",
        usage: { inputTokens: 120, outputTokens: 80, latencyBucket: "under5s" }
      },
      ...overrides
    }
  };
}

describe("private live AI operational scripts", () => {
  it("requires every deployment identity and keeps Cloud Run authenticated", () => {
    const missing = spawnSync("bash", ["scripts/deploy-ai-service.sh"], {
      cwd: repoRoot,
      encoding: "utf8"
    });
    expect(missing.status).not.toBe(0);

    const deployment = spawnSync("bash", [
      "scripts/deploy-ai-service.sh",
      "--project", "openlarp-development",
      "--region", "us-central1",
      "--service", "openlarp-ai",
      "--ai-service-account", "openlarp-ai@openlarp-development.iam.gserviceaccount.com",
      "--functions-service-account", "openlarp-functions@openlarp-development.iam.gserviceaccount.com",
      "--repository", "openlarp",
      "--dry-run"
    ], {
      cwd: repoRoot,
      encoding: "utf8"
    });

    expect(deployment.status, deployment.stderr).toBe(0);
    expect(deployment.stdout).toContain("--no-allow-unauthenticated");
    expect(deployment.stdout).toContain("roles/run.invoker");
    expect(deployment.stdout).toContain("serviceAccount:openlarp-functions@openlarp-development.iam.gserviceaccount.com");
    expect(deployment.stdout).not.toContain("allUsers");
    expect(deployment.stdout).not.toMatch(/private[_-]?key|api[_-]?key|bearer /i);
  });

  it("uses the exact service origin as ADC ID-token audience and prints only bounded smoke metadata", async () => {
    const calls = [];
    const output = [];
    const result = await runLiveAISmoke({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient: async (audience) => {
        calls.push({ audience });
        return {
          async request(options) {
            calls.push(options);
            return serviceResponse(options.data.envelope.run.requestID);
          }
        };
      },
      log: (line) => output.push(line)
    });

    expect(calls[0]).toEqual({ audience: "https://openlarp-ai-abc-uc.a.run.app" });
    expect(calls[1]).toMatchObject({
      url: "https://openlarp-ai-abc-uc.a.run.app/v1/workflows:run",
      method: "POST",
      timeout: 20_000,
      maxContentLength: 256 * 1024,
      maxRedirects: 0
    });
    expect(internalWorkflowRequestSchema.safeParse(calls[1].data).success).toBe(true);
    expect(result).toEqual({
      status: 200,
      workflowKind: "cookedDiagnostic",
      liveModelCallsEnabled: true,
      liveModelUsed: true,
      usedFallback: false,
      fallbackReason: null,
      latencyBucket: "under5s",
      promptVersion: "openlarp.cooked.v1",
      inputTokens: 120,
      outputTokens: 80
    });
    expect(output).toEqual([JSON.stringify(result)]);
    expect(output[0]).not.toMatch(/synthetic private career marker|targetRole|modelId|modelName|policyRevision|serviceURL/i);
  });

  it("rejects a response with a malformed workflow result or inconsistent fallback metadata", async () => {
    const invoke = (overrides) => runLiveAISmoke({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient: async () => ({
        async request(options) {
          return serviceResponse(options.data.envelope.run.requestID, overrides);
        }
      }),
      log: () => undefined
    });

    await expect(invoke({ result: { privateCareerText: "invalid result" } }))
      .rejects.toThrow("Live AI smoke response failed validation.");
    await expect(invoke({
      execution: {
        ...serviceResponse("00000000-0000-4000-8000-000000000000").data.execution,
        fallbackReason: "provider"
      }
    })).rejects.toThrow("Live AI smoke response failed validation.");
  });

  it("fails a required-live check when the service honestly uses fallback", async () => {
    await expect(runLiveAISmoke({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      requireLive: true,
      getIdTokenClient: async () => ({
        async request(options) {
          const response = serviceResponse(options.data.envelope.run.requestID);
          response.data.execution = {
            ...response.data.execution,
            liveModelUsed: false,
            usedFallback: true,
            fallbackReason: "provider",
            promptVersion: null,
            usage: { inputTokens: 0, outputTokens: 0, latencyBucket: "notRun" }
          };
          return response;
        }
      }),
      log: () => undefined
    })).rejects.toThrow("Live AI smoke completed through fallback while --require-live was set.");
  });

  it("rejects malformed live smoke responses without printing response or credential details", async () => {
    const output = [];
    await expect(runLiveAISmoke({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient: async () => ({
        async request() {
          return { status: 200, data: { privateCareerText: "do not print" } };
        }
      }),
      log: (line) => output.push(line)
    })).rejects.toThrow("Live AI smoke response failed validation.");
    expect(output).toEqual([]);
  });
});
