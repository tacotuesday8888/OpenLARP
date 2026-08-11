import { describe, expect, it, vi } from "vitest";
import { requestEnvelopeSchema } from "../src/contracts.js";
import { LiveGenerationProviderError } from "../src/liveGeneration.js";
import {
  WorkflowExecutionCancelledError,
  executeWorkflow
} from "../src/workflowExecution.js";
import { checkProofQuality, makeDiagnostic } from "../src/mockWorkflows.js";

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

const policy = {
  enabled: true,
  policyRevision: "beta-2026-08-10",
  timeoutMs: 200,
  maxOutputTokens: 1200
};

const validDiagnostic = makeDiagnostic(envelope.payload as Parameters<typeof makeDiagnostic>[0]);

const proofEnvelope = requestEnvelopeSchema.parse({
  ...envelope,
  run: {
    ...envelope.run,
    kind: "proofQualityCheck",
    requestID: "22222222-2222-4222-8222-222222222222"
  },
  payload: {
    context: {
      schemaVersion: 1,
      targetRoleTitle: "iOS engineer",
      currentQuest: null,
      progress: {
        readiness: {
          overall: 40,
          proofStrength: 30,
          confidence: 50,
          consistency: 35,
          skillProof: 30,
          networkStrength: 20
        },
        completedQuestCount: 0,
        proofCount: 0,
        streakCount: 0,
        xp: 0,
        xpGoal: 1000
      },
      privacy: envelope.run.privacy,
      allowsLongTermMemoryWrite: true
    },
    proof: {
      kind: "proof",
      text: "I compared three role requirements and turned the repeated gap into a concrete project improvement plan.",
      link: "",
      attachments: []
    },
    targetRoleTitle: "iOS engineer"
  }
});
const proofContext = (proofEnvelope.payload as {
  context: { currentQuest: unknown; progress: unknown };
}).context;

const assistantEnvelope = requestEnvelopeSchema.parse({
  ...envelope,
  run: {
    ...envelope.run,
    kind: "contextualAssistant",
    requestID: "55555555-5555-4555-8555-555555555555",
    privacy: { ...envelope.run.privacy, allowsLongTermMemoryWrite: false }
  },
  payload: {
    surface: "questDetail",
    question: "Why this quest?",
    goal: { targetRole: "iOS engineer", timeline: "12 weeks", outcomeType: "job" },
    confirmedFacts: [{
      id: "66666666-6666-4666-8666-666666666666",
      kind: "experience",
      value: "One shipped class app"
    }],
    currentQuest: proofContext.currentQuest,
    progress: proofContext.progress,
    allowsLongTermMemoryWrite: false,
    externalActionsAllowed: false
  }
});

describe("executeWorkflow", () => {
  it("returns a post-validated live result with privacy-safe metadata", async () => {
    const generator = {
      generate: vi.fn(async () => ({ output: validDiagnostic, inputTokens: 120, outputTokens: 80 }))
    };

    const result = await executeWorkflow({ envelope, policy, generator });

    expect(result.result).toEqual(validDiagnostic);
    expect(result.execution).toMatchObject({
      liveModelCallsEnabled: true,
      liveModelUsed: true,
      usedFallback: false,
      fallbackReason: null,
      promptVersion: "openlarp.cooked.v1",
      policyRevision: "beta-2026-08-10",
      usage: { inputTokens: 120, outputTokens: 80 }
    });
    expect(JSON.stringify(result.execution)).not.toContain("iOS engineer");
  });

  it("asks the model only for proof coaching and attaches server-owned review fields", async () => {
    const coaching = {
      reason: "The written description identifies a concrete comparison and resulting decision.",
      improvement: "Add one measurable before-and-after detail."
    };
    const generator = {
      generate: vi.fn(async ({ schema }) => {
        expect(schema.safeParse(coaching).success).toBe(true);
        expect(schema.safeParse(checkProofQuality(proofEnvelope.payload as Parameters<typeof checkProofQuality>[0])).success)
          .toBe(false);
        return { output: coaching, inputTokens: 90, outputTokens: 35 };
      })
    };

    const result = await executeWorkflow({ envelope: proofEnvelope, policy, generator });
    const expected = checkProofQuality(proofEnvelope.payload as Parameters<typeof checkProofQuality>[0]);

    expect(result.result).toEqual({ ...expected, ...coaching });
    expect(result.execution).toMatchObject({
      liveModelUsed: true,
      usedFallback: false,
      promptVersion: "openlarp.proof-quality.v1"
    });
  });

  it("rejects contextual answers that cite an unconfirmed fact ID", async () => {
    const unsafeAnswer = {
      answer: "Start with the first quest step.",
      factIDsUsed: ["77777777-7777-4777-8777-777777777777"],
      inferences: [],
      advice: ["Complete one bounded action."],
      nextAction: { title: "Start", detail: "Complete the first listed step." },
      suggestedDraft: null
    };
    const generator = {
      generate: vi.fn(async () => ({ output: unsafeAnswer, inputTokens: 50, outputTokens: 30 }))
    };

    const result = await executeWorkflow({ envelope: assistantEnvelope, policy, generator });

    expect(result.execution).toMatchObject({ usedFallback: true, fallbackReason: "unsafeOutput" });
    expect(result.result).not.toEqual(unsafeAnswer);
  });

  it("returns deterministic output when live generation is disabled", async () => {
    const generator = { generate: vi.fn() };

    const result = await executeWorkflow({ envelope, policy: { ...policy, enabled: false }, generator });

    expect(result.result).toEqual(validDiagnostic);
    expect(result.execution).toMatchObject({
      liveModelCallsEnabled: false,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "disabled",
      usage: { inputTokens: 0, outputTokens: 0, latencyBucket: "notRun" }
    });
    expect(generator.generate).not.toHaveBeenCalled();
  });

  it("retries one retryable provider failure and then succeeds", async () => {
    const generator = {
      generate: vi.fn()
        .mockRejectedValueOnce(new LiveGenerationProviderError("temporary", true))
        .mockResolvedValueOnce({ output: validDiagnostic, inputTokens: 120, outputTokens: 80 })
    };

    const result = await executeWorkflow({ envelope, policy, generator });

    expect(result.execution.liveModelUsed).toBe(true);
    expect(generator.generate).toHaveBeenCalledTimes(2);
  });

  it("falls back after retryable provider failure is exhausted", async () => {
    const generator = {
      generate: vi.fn().mockRejectedValue(new LiveGenerationProviderError("temporary", true))
    };

    const result = await executeWorkflow({ envelope, policy, generator });

    expect(result.result).toEqual(validDiagnostic);
    expect(result.execution).toMatchObject({ usedFallback: true, fallbackReason: "provider" });
    expect(generator.generate).toHaveBeenCalledTimes(2);
  });

  it("does not retry malformed or unsafe output", async () => {
    const malformed = { generate: vi.fn(async () => ({ output: { score: 1 }, inputTokens: 1, outputTokens: 1 })) };
    const malformedResult = await executeWorkflow({ envelope, policy, generator: malformed });
    expect(malformedResult.execution).toMatchObject({ usedFallback: true, fallbackReason: "invalidOutput" });
    expect(malformed.generate).toHaveBeenCalledTimes(1);

    const unsafe = {
      generate: vi.fn(async () => ({
        output: {
          ...validDiagnostic,
          strongestSignal: "You worked at Apple for three years.",
          strongestSignals: ["You worked at Apple for three years."]
        },
        inputTokens: 1,
        outputTokens: 1
      }))
    };
    const unsafeResult = await executeWorkflow({ envelope, policy, generator: unsafe });
    expect(unsafeResult.execution).toMatchObject({ usedFallback: true, fallbackReason: "unsafeOutput" });
    expect(unsafe.generate).toHaveBeenCalledTimes(1);
  });

  it("aborts a timed-out provider call and falls back without retry", async () => {
    const generator = {
      generate: vi.fn(({ signal }: { signal: AbortSignal }) => new Promise<never>((_, reject) => {
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      }))
    };

    const result = await executeWorkflow({
      envelope,
      policy: { ...policy, timeoutMs: 10 },
      generator
    });

    expect(result.execution).toMatchObject({ usedFallback: true, fallbackReason: "timeout" });
    expect(generator.generate).toHaveBeenCalledTimes(1);
  });

  it("propagates caller cancellation instead of manufacturing a result", async () => {
    const controller = new AbortController();
    const generator = {
      generate: vi.fn(({ signal }: { signal: AbortSignal }) => new Promise<never>((_, reject) => {
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      }))
    };
    const execution = executeWorkflow({ envelope, policy, generator, signal: controller.signal });
    controller.abort();

    await expect(execution).rejects.toBeInstanceOf(WorkflowExecutionCancelledError);
  });
});
