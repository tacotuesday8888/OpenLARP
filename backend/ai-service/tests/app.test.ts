import { describe, expect, it, vi } from "vitest";
import type { WorkflowExecutionResult } from "../../ai/src/index.js";
import { handleAIServiceRequest } from "../src/app.js";

const validRequest = {
  schemaVersion: 1,
  envelope: {
    schemaVersion: 1,
    run: {
      schemaVersion: 1,
      kind: "cookedDiagnostic",
      providerRoute: "cloudRunGenkit",
      requestedAt: "2026-08-10T10:00:00.000Z",
      requestID: "11111111-1111-4111-8111-111111111111",
      privacy: {
        memoryMode: "cloudReady",
        allowsLongTermMemoryWrite: true,
        requiresUserApprovalForExternalActions: true,
        shareWins: false,
        allowsPrivateEvidenceCloudSync: false
      }
    },
    safetyRules: {
      hardBannedClaims: ["Never invent an employer or any other substantial career claim."],
      requiredBehaviors: ["Separate facts, inferences, unknowns, and advice."],
      privacyRequirements: ["External actions require user approval before the system can act."]
    },
    payload: {
      goal: {
        currentStatus: "New graduate",
        targetRole: "iOS engineer",
        timeline: "12 weeks",
        background: "One class app",
        existingProof: "A local demo",
        confidence: 3,
        biggestBlocker: "Thin role-specific proof"
      }
    }
  },
  policy: {
    enabled: true,
    policyRevision: "beta-2026-08-10",
    timeoutMs: 15000,
    maxOutputTokens: 1200
  }
};

const executionResult = {
  result: { label: "Grounded result" },
  execution: {
    schemaVersion: 1,
    liveModelCallsEnabled: true,
    liveModelUsed: true,
    usedFallback: false,
    fallbackReason: null,
    promptVersion: "openlarp.cooked.v1",
    policyRevision: "beta-2026-08-10",
    usage: { inputTokens: 100, outputTokens: 50, latencyBucket: "under5s" }
  }
} satisfies WorkflowExecutionResult;

const execute = vi.fn(async () => executionResult);

describe("handleAIServiceRequest", () => {
  it("returns a non-sensitive health response", async () => {
    const response = await handleAIServiceRequest({
      method: "GET",
      path: "/healthz",
      headers: {},
      body: ""
    }, { execute });

    expect(response.status).toBe(200);
    expect(response.headers).toMatchObject({
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff"
    });
    expect(JSON.parse(response.body)).toEqual({ ok: true, schemaVersion: 1, service: "openlarp-ai" });
    expect(response.body).not.toMatch(/gemini|vertex|model|project/i);
  });

  it("executes the exact private workflow route and returns bounded metadata", async () => {
    execute.mockClear();
    const response = await handleAIServiceRequest({
      method: "POST",
      path: "/v1/workflows:run",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest)
    }, { execute });

    expect(response.status).toBe(200);
    expect(execute).toHaveBeenCalledTimes(1);
    expect(JSON.parse(response.body)).toMatchObject({
      ok: true,
      schemaVersion: 1,
      requestID: "11111111-1111-4111-8111-111111111111",
      kind: "cookedDiagnostic",
      externalActionTaken: false,
      result: { label: "Grounded result" },
      execution: { liveModelUsed: true }
    });
    expect(response.body).not.toContain("iOS engineer");
  });

  it.each([
    ["GET", "/v1/workflows:run", { "content-type": "application/json" }, JSON.stringify(validRequest), 405],
    ["POST", "/v1/workflows:run", { "content-type": "text/plain" }, JSON.stringify(validRequest), 415],
    ["POST", "/unknown", { "content-type": "application/json" }, JSON.stringify(validRequest), 404]
  ])("rejects unsupported HTTP input", async (method, path, headers, body, status) => {
    const response = await handleAIServiceRequest({ method, path, headers, body }, { execute });
    expect(response.status).toBe(status);
  });

  it("rejects bodies over 256 KiB before JSON parsing", async () => {
    const response = await handleAIServiceRequest({
      method: "POST",
      path: "/v1/workflows:run",
      headers: { "content-type": "application/json" },
      body: "x".repeat(256 * 1024 + 1)
    }, { execute });

    expect(response.status).toBe(413);
  });

  it("rejects malformed or non-internal contracts without echoing private input", async () => {
    const privateText = "Private career proof langqi@example.com";
    const wrongRoute = structuredClone(validRequest);
    wrongRoute.envelope.run.providerRoute = "firebaseCallableGenkit";
    wrongRoute.envelope.payload.goal.background = privateText;

    for (const body of ["{bad json", JSON.stringify(wrongRoute)]) {
      const response = await handleAIServiceRequest({
        method: "POST",
        path: "/v1/workflows:run",
        headers: { "content-type": "application/json" },
        body
      }, { execute });
      expect(response.status).toBe(400);
      expect(response.body).not.toContain(privateText);
      expect(response.body).not.toContain("bad json");
    }
  });

  it("returns a redacted service error when execution fails", async () => {
    const response = await handleAIServiceRequest({
      method: "POST",
      path: "/v1/workflows:run",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validRequest)
    }, {
      execute: async () => { throw new Error("provider error containing Private career proof"); }
    });

    expect(response.status).toBe(503);
    expect(JSON.parse(response.body)).toEqual({
      ok: false,
      schemaVersion: 1,
      code: "service-unavailable",
      message: "OpenLARP AI service could not complete the workflow."
    });
    expect(response.body).not.toContain("Private career proof");
  });
});
