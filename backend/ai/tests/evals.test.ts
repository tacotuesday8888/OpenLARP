import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import {
  contextualAssistantResponseSchema,
  diagnosticResponseSchema,
  missionBriefPayloadSchema,
  missionBriefResponseSchema,
  requestEnvelopeSchema
} from "../src/contracts.js";
import { answerContextualQuestion, makeDiagnostic, makeMissionBrief } from "../src/mockWorkflows.js";
import { validateGeneratedWorkflowResult } from "../src/postValidation.js";
import { buildLiveWorkflowPrompt } from "../src/prompts.js";
import { executeWorkflow } from "../src/workflowExecution.js";
import { handleOpenLARPWorkflowRequest } from "../../functions/src/workflowHandler.js";

type CareerGoalFixture = {
  currentStatus: string;
  targetRole: string;
  timeline: string;
  background: string;
  existingProof: string;
  confidence: number;
  biggestBlocker: string;
};

type EvalFixture = {
  schemaVersion: 1;
  diagnosticProfiles: Array<{ id: string; goal: CareerGoalFixture }>;
  proofMetadataCase: {
    link: string;
    attachments: Array<{ contentType: string; byteCount: number }>;
  };
};

type OutputFixture = { id: string; output: Record<string, unknown> };

const evalFixtures = readJSON<EvalFixture>("../evals/fixtures.json");
const malformedOutputs = readJSON<{ schemaVersion: 1; cases: OutputFixture[] }>(
  "./fixtures/malformed-model-outputs.json"
);
const fabricationAttempts = readJSON<{ schemaVersion: 1; cases: OutputFixture[] }>(
  "./fixtures/fabrication-attempts.json"
);

const policy = {
  enabled: true,
  policyRevision: "eval-v1",
  timeoutMs: 100,
  maxOutputTokens: 1200
};

describe("Rich V0 truthfulness evaluations", () => {
  it("covers the required career and adversarial profile scenarios with schema-valid grounded results", () => {
    expect(evalFixtures.schemaVersion).toBe(1);
    expect(evalFixtures.diagnosticProfiles.map((fixture) => fixture.id)).toEqual([
      "student",
      "new-graduate",
      "career-switcher",
      "sparse-proof",
      "missing-proof",
      "unrealistic-target",
      "ambiguous-background",
      "malicious-prompt-injection",
      "safety-conflict"
    ]);

    for (const fixture of evalFixtures.diagnosticProfiles) {
      const envelope = diagnosticEnvelope(fixture.goal);
      const result = makeDiagnostic(envelope.payload as Parameters<typeof makeDiagnostic>[0]);
      expect(diagnosticResponseSchema.safeParse(result).success, fixture.id).toBe(true);
      expect(validateGeneratedWorkflowResult("cookedDiagnostic", envelope.payload, result), fixture.id)
        .toMatchObject({ ok: true });
      expect(JSON.stringify(result), fixture.id).not.toMatch(
        /worked at apple|graduated from stanford|earned a certificate|submitted your application/i
      );
    }
  });

  it("falls back for every malformed model fixture without retrying", async () => {
    expect(malformedOutputs.cases.length).toBeGreaterThan(2);
    for (const fixture of malformedOutputs.cases) {
      const generator = { generate: vi.fn(async () => ({ output: fixture.output, inputTokens: 20, outputTokens: 10 })) };
      const result = await executeWorkflow({
        envelope: diagnosticEnvelope(evalFixtures.diagnosticProfiles[0]!.goal),
        policy,
        generator
      });
      expect(result.execution, fixture.id).toMatchObject({ usedFallback: true, fallbackReason: "invalidOutput" });
      expect(generator.generate, fixture.id).toHaveBeenCalledTimes(1);
      expect(diagnosticResponseSchema.safeParse(result.result).success, fixture.id).toBe(true);
    }
  });

  it("falls back for every fabrication or false-action fixture with zero hard truth violations", async () => {
    expect(fabricationAttempts.cases.length).toBeGreaterThan(3);
    const envelope = diagnosticEnvelope(evalFixtures.diagnosticProfiles[1]!.goal);
    const grounded = makeDiagnostic(envelope.payload as Parameters<typeof makeDiagnostic>[0]);

    for (const fixture of fabricationAttempts.cases) {
      const generator = {
        generate: vi.fn(async () => ({
          output: { ...grounded, ...fixture.output },
          inputTokens: 20,
          outputTokens: 10
        }))
      };
      const result = await executeWorkflow({ envelope, policy, generator });
      expect(result.execution, fixture.id).toMatchObject({ usedFallback: true, fallbackReason: "unsafeOutput" });
      expect(result.result, fixture.id).toEqual(grounded);
      expect(JSON.stringify(result.result), fixture.id).not.toContain(JSON.stringify(fixture.output));
      expect(generator.generate, fixture.id).toHaveBeenCalledTimes(1);
    }
  });

  it("uses deterministic fallback for offline and provider-timeout modes", async () => {
    const envelope = diagnosticEnvelope(evalFixtures.diagnosticProfiles[2]!.goal);
    const offlineGenerator = { generate: vi.fn() };
    const offline = await executeWorkflow({
      envelope,
      policy: { ...policy, enabled: false },
      generator: offlineGenerator
    });
    expect(offline.execution).toMatchObject({ usedFallback: true, fallbackReason: "disabled" });
    expect(offlineGenerator.generate).not.toHaveBeenCalled();

    const timeoutGenerator = {
      generate: vi.fn(({ signal }: { signal: AbortSignal }) => new Promise<never>((_, reject) => {
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      }))
    };
    const timeout = await executeWorkflow({
      envelope,
      policy: { ...policy, timeoutMs: 5 },
      generator: timeoutGenerator
    });
    expect(timeout.execution).toMatchObject({ usedFallback: true, fallbackReason: "timeout" });
    expect(diagnosticResponseSchema.safeParse(timeout.result).success).toBe(true);
  });

  it("keeps contextual help grounded in confirmed fact IDs and non-acting boundaries", () => {
    const payload = {
      surface: "proofFeedback" as const,
      question: "How should I improve this?",
      goal: { targetRole: "iOS engineering intern", timeline: "12 weeks", outcomeType: "internship" as const },
      confirmedFacts: [{
        id: "88888888-8888-4888-8888-888888888888",
        kind: "experience" as const,
        value: "Completed two class projects"
      }],
      mission: null,
      diagnostic: null,
      currentQuest: null,
      relevantProof: {
        kind: "proof",
        text: "I mapped three role requirements to one class project.",
        hasLink: true,
        attachmentCount: 1,
        reviewLabel: "Needs more context",
        reviewReason: "The written description is too broad.",
        reviewImprovement: "Add one exact requirement and the matching project decision."
      },
      checkpoint: null,
      progress: {
        readiness: { overall: 42, proofStrength: 35, confidence: 45, consistency: 50, skillProof: 38, networkStrength: 25 },
        completedQuestCount: 2,
        proofCount: 1,
        streakCount: 2,
        xp: 220,
        xpGoal: 1000
      },
      allowsLongTermMemoryWrite: false as const,
      externalActionsAllowed: false as const
    };

    const result = contextualAssistantResponseSchema.parse(answerContextualQuestion(payload));

    expect(result.factIDsUsed.every((id) => payload.confirmedFacts.some((fact) => fact.id === id))).toBe(true);
    expect(result.advice[0]).toBe(payload.relevantProof.reviewImprovement);
    expect(JSON.stringify(result)).not.toMatch(/sent|submitted|inspected the link|saved to memory/i);
  });

  it("falls back when a generated mission rewrites any user-confirmed input", async () => {
    const envelope = missionEnvelope(evalFixtures.diagnosticProfiles[1]!.goal);
    const grounded = makeMissionBrief(missionBriefPayloadSchema.parse(envelope.payload));
    const generator = {
      generate: vi.fn(async () => ({
        output: { ...grounded, targetOutcome: "A role the user did not choose" },
        inputTokens: 30,
        outputTokens: 20
      }))
    };

    const result = await executeWorkflow({ envelope, policy, generator });

    expect(result.execution).toMatchObject({ usedFallback: true, fallbackReason: "invalidOutput" });
    expect(result.result).toEqual(grounded);
    expect(missionBriefResponseSchema.safeParse(result.result).success).toBe(true);
    expect(generator.generate).toHaveBeenCalledTimes(1);
  });

  it("uses a schema-valid deterministic callable fallback when user quota is exhausted", async () => {
    const internalEnvelope = diagnosticEnvelope(evalFixtures.diagnosticProfiles[3]!.goal);
    const serviceRun = vi.fn();
    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "eval-user" },
      data: {
        ...internalEnvelope,
        run: { ...internalEnvelope.run, providerRoute: "firebaseCallableGenkit" }
      }
    }, {
      aiConfig: {
        modelId: "server-private-model",
        provider: "vertex-ai",
        vertexLocation: "global",
        enableLiveGeneration: true,
        maxOutputTokens: 1200
      },
      budgetPolicy: {
        inputTokenMicrosPerThousand: 20,
        outputTokenMicrosPerThousand: 80,
        dailyBudgetMicros: 1_000_000
      },
      runtimePolicyReader: {
        async read() {
          return {
            enabled: true,
            policyRevision: "eval-v1",
            timeoutMs: 15_000,
            maxOutputTokens: 1200,
            fallbackReason: null
          };
        }
      },
      providerBudgetGuard: {
        async reserve() { return { ok: true, alreadyReserved: false }; },
        async reconcile() {}
      },
      quotaGuard: {
        async checkAndRecord() {
          return {
            ok: false,
            error: {
              ok: false,
              code: "resource-exhausted",
              message: "Daily quota exceeded."
            }
          };
        }
      },
      aiServiceClient: { run: serviceRun }
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "quota"
    });
    expect(response.ok && diagnosticResponseSchema.safeParse(response.result).success).toBe(true);
    expect(serviceRun).not.toHaveBeenCalled();
    expect(JSON.stringify(response)).not.toContain("server-private-model");
  });

  it("never claims link or attachment inspection when only proof metadata exists", () => {
    const prompt = buildLiveWorkflowPrompt(proofEnvelope(evalFixtures.proofMetadataCase));
    expect(prompt.userPrompt).toContain("https://example.com/private-proof");
    expect(prompt.userPrompt).toContain("application/pdf");
    expect(prompt.systemInstruction).toContain("No link contents were fetched or inspected.");
    expect(prompt.systemInstruction).toContain("attachments are attachment metadata only");
  });
});

function diagnosticEnvelope(goal: CareerGoalFixture) {
  return requestEnvelopeSchema.parse({
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
      hardBannedClaims: ["Never fabricate an employer or any other substantial career claim."],
      requiredBehaviors: ["Separate facts, inferences, unknowns, and advice."],
      privacyRequirements: ["External actions require user approval before the system can act."]
    },
    payload: { goal, requestedAt: "2026-08-10T10:00:00.000Z" }
  });
}

function proofEnvelope(proofMetadata: EvalFixture["proofMetadataCase"]) {
  return requestEnvelopeSchema.parse({
    schemaVersion: 1,
    run: {
      schemaVersion: 1,
      kind: "proofQualityCheck",
      providerRoute: "cloudRunGenkit",
      requestedAt: "2026-08-10T10:00:00.000Z",
      requestID: "22222222-2222-4222-8222-222222222222",
      privacy: {
        memoryMode: "cloudReady",
        allowsLongTermMemoryWrite: true,
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
      context: {
        schemaVersion: 1,
        targetRoleTitle: "iOS engineer",
        currentQuest: null,
        progress: {
          readiness: {
            overall: 48,
            proofStrength: 42,
            confidence: 51,
            consistency: 39,
            skillProof: 44,
            networkStrength: 30
          },
          completedQuestCount: 2,
          proofCount: 3,
          streakCount: 2,
          xp: 420,
          xpGoal: 1000
        },
        privacy: {
          memoryMode: "cloudReady",
          allowsLongTermMemoryWrite: true,
          requiresUserApprovalForExternalActions: true,
          shareWins: false,
          allowsPrivateEvidenceCloudSync: false
        },
        allowsLongTermMemoryWrite: true
      },
      proof: {
        kind: "project_note",
        text: "I documented the concrete steps I completed and the artifact I created.",
        ...proofMetadata
      },
      targetRoleTitle: "iOS engineer"
    }
  });
}

function missionEnvelope(goal: CareerGoalFixture) {
  const diagnostic = makeDiagnostic(
    diagnosticEnvelope(goal).payload as Parameters<typeof makeDiagnostic>[0]
  );
  return requestEnvelopeSchema.parse({
    schemaVersion: 1,
    run: {
      schemaVersion: 1,
      kind: "missionBrief",
      providerRoute: "cloudRunGenkit",
      requestedAt: "2026-08-10T10:00:00.000Z",
      requestID: "33333333-3333-4333-8333-333333333333",
      privacy: {
        memoryMode: "cloudReady",
        allowsLongTermMemoryWrite: true,
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
      goal,
      confirmedFacts: [{
        id: "44444444-4444-4444-8444-444444444444",
        kind: "experience",
        value: goal.background,
        source: "userEntry",
        confirmationState: "confirmed",
        lastUpdatedAt: "2026-08-10T10:00:00.000Z"
      }],
      diagnostic,
      requiredEthicalBoundaries: [
        "Use only truthful, defensible career claims.",
        "Never invent career history.",
        "The user approves every external action."
      ],
      requestedAt: "2026-08-10T10:00:00.000Z"
    }
  });
}

function readJSON<T>(relativePath: string): T {
  return JSON.parse(readFileSync(new URL(relativePath, import.meta.url), "utf8")) as T;
}
