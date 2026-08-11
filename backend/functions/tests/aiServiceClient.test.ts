import { describe, expect, it, vi } from "vitest";
import { requestEnvelopeSchema } from "../../ai/src/contracts.js";
import {
  AIServiceClientError,
  aiServiceClientFromEnvironment,
  createAIServiceClient,
  parseAIServiceURL
} from "../src/aiServiceClient.js";

const envelope = requestEnvelopeSchema.parse({
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
});

const serviceResponse = {
  ok: true,
  schemaVersion: 1,
  requestID: envelope.run.requestID,
  kind: envelope.run.kind,
  externalActionTaken: false,
  result: {
    score: 54,
    label: "Some proof, not enough signal",
    mainGap: "Role-specific proof is still thin.",
    strongestSignal: "One class app is confirmed.",
    fastestFix: "Create one small role-specific artifact.",
    readinessBaseline: 48,
    strongestSignals: ["One class app is confirmed."],
    readinessGaps: ["No role-specific artifact is confirmed."],
    missingInformation: ["The app outcome is unknown."],
    uncertaintyExplanation: "This result uses only confirmed information.",
    firstAction: "Map repeated requirements from two role descriptions."
  },
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
};

describe("createAIServiceClient", () => {
  it("uses the exact service origin as ID-token audience and a bounded internal POST", async () => {
    const request = vi.fn(async () => ({ data: serviceResponse }));
    const getIdTokenClient = vi.fn(async () => ({ request }));
    const client = createAIServiceClient({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient
    });

    const response = await client.run({
      envelope,
      policy: {
        enabled: true,
        policyRevision: "beta-2026-08-10",
        timeoutMs: 15_000,
        maxOutputTokens: 1200
      }
    });

    expect(response).toEqual(serviceResponse);
    expect(getIdTokenClient).toHaveBeenCalledWith("https://openlarp-ai-abc-uc.a.run.app");
    expect(request).toHaveBeenCalledWith({
      url: "https://openlarp-ai-abc-uc.a.run.app/v1/workflows:run",
      method: "POST",
      data: { schemaVersion: 1, envelope, policy: expect.any(Object) },
      timeout: 17_000,
      responseType: "json",
      maxContentLength: 256 * 1024,
      maxRedirects: 0,
      validateStatus: expect.any(Function)
    });
    expect(JSON.stringify(response)).not.toContain("openlarp-ai-abc-uc.a.run.app");
  });

  it("rejects insecure, credential-bearing, and path-bearing service URLs", () => {
    for (const value of [
      "http://openlarp-ai.example.com",
      "https://user:secret@openlarp-ai.example.com",
      "https://openlarp-ai.example.com/private",
      "https://openlarp-ai.example.com?token=secret"
    ]) {
      expect(() => parseAIServiceURL(value)).toThrow();
    }
    expect(parseAIServiceURL("http://127.0.0.1:8080", true).origin).toBe("http://127.0.0.1:8080");
  });

  it("fails closed without crashing the callable when the service URL environment value is invalid", () => {
    expect(aiServiceClientFromEnvironment({ OPENLARP_AI_SERVICE_URL: "http://insecure.example.com" })).toBeNull();
  });

  it("rejects malformed or mismatched service responses", async () => {
    const client = createAIServiceClient({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient: async () => ({
        request: async () => ({ data: { ...serviceResponse, requestID: "99999999-9999-4999-8999-999999999999" } })
      })
    });

    await expect(client.run({
      envelope,
      policy: { enabled: true, policyRevision: "beta-2026-08-10", timeoutMs: 15_000, maxOutputTokens: 1200 }
    })).rejects.toBeInstanceOf(AIServiceClientError);
  });

  it("rejects a service response whose result does not match its workflow kind", async () => {
    const client = createAIServiceClient({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient: async () => ({
        request: async () => ({ data: { ...serviceResponse, result: { label: "Incomplete" } } })
      })
    });

    await expect(client.run({
      envelope,
      policy: { enabled: true, policyRevision: "beta-2026-08-10", timeoutMs: 15_000, maxOutputTokens: 1200 }
    })).rejects.toBeInstanceOf(AIServiceClientError);
  });

  it("redacts provider and response details from transport errors", async () => {
    const client = createAIServiceClient({
      serviceURL: "https://openlarp-ai-abc-uc.a.run.app",
      getIdTokenClient: async () => ({
        request: async () => { throw new Error("Private proof text and bearer token"); }
      })
    });

    await expect(client.run({
      envelope,
      policy: { enabled: true, policyRevision: "beta-2026-08-10", timeoutMs: 15_000, maxOutputTokens: 1200 }
    })).rejects.toEqual(new AIServiceClientError("AI service request failed."));
  });
});
