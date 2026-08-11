import { describe, expect, it } from "vitest";
import { requestEnvelopeSchema } from "../src/contracts.js";
import { buildLiveWorkflowPrompt } from "../src/prompts.js";

const privacy = {
  memoryMode: "cloudReady",
  allowsLongTermMemoryWrite: true,
  requiresUserApprovalForExternalActions: true,
  shareWins: false,
  allowsPrivateEvidenceCloudSync: false
} as const;

function envelope(kind: string, payload: unknown) {
  return requestEnvelopeSchema.parse({
    schemaVersion: 1,
    run: {
      schemaVersion: 1,
      kind,
      providerRoute: "cloudRunGenkit",
      requestedAt: "2026-08-10T10:00:00.000Z",
      requestID: "11111111-1111-4111-8111-111111111111",
      privacy
    },
    safetyRules: {
      hardBannedClaims: ["Never invent an employer or any other substantial career claim."],
      requiredBehaviors: ["Separate facts, inferences, unknowns, and advice."],
      privacyRequirements: ["External actions require user approval before the system can act."]
    },
    payload
  });
}

describe("buildLiveWorkflowPrompt", () => {
  it("labels confirmed facts, hypotheses, unknowns, and advice for adaptive intake", () => {
    const prompt = buildLiveWorkflowPrompt(envelope("adaptiveCareerIntake", {
      confirmedFacts: [{
        id: "22222222-2222-4222-8222-222222222222",
        kind: "targetOutcome",
        value: "iOS engineer",
        source: "userEntry",
        lastUpdatedAt: "2026-08-10T09:00:00.000Z"
      }],
      pendingHypotheses: [],
      rejectedHypothesisIDs: [],
      unknownKinds: ["existingProof"],
      questionHistory: [],
      maxQuestions: 1
    }));

    expect(prompt.promptVersion).toBe("openlarp.adaptive-intake.v1");
    expect(prompt.systemInstruction).toContain("USER-CONFIRMED FACTS");
    expect(prompt.systemInstruction).toContain("AI HYPOTHESES AWAITING CONFIRMATION");
    expect(prompt.systemInstruction).toContain("UNKNOWNS");
    expect(prompt.systemInstruction).toContain("ADVICE");
    expect(prompt.systemInstruction).toContain("must never become confirmed");
    expect(prompt.userPrompt).toContain("iOS engineer");
  });

  it("prohibits fabricated career claims, tools, and external actions for Cooked", () => {
    const prompt = buildLiveWorkflowPrompt(envelope("cookedDiagnostic", {
      goal: {
        currentStatus: "New graduate",
        targetRole: "iOS engineer",
        timeline: "12 weeks",
        background: "One class app",
        existingProof: "A local demo",
        confidence: 3,
        biggestBlocker: "Thin role-specific proof"
      }
    }));

    for (const term of ["employer", "school", "credential", "title", "date", "project", "ownership", "result", "experience"]) {
      expect(prompt.systemInstruction.toLowerCase()).toContain(term);
    }
    expect(prompt.systemInstruction).toContain("Do not call tools");
    expect(prompt.systemInstruction).toContain("Do not send, submit, publish, apply, or message");
    expect(prompt.promptVersion).toBe("openlarp.cooked.v1");
  });

  it("states exactly what was not inspected for proof metadata", () => {
    const prompt = buildLiveWorkflowPrompt(envelope("proofQualityCheck", {
      context: {
        schemaVersion: 1,
        targetRoleTitle: "iOS engineer",
        currentQuest: null,
        progress: {
          readiness: { overall: 40, proofStrength: 30, confidence: 50, consistency: 35, skillProof: 30, networkStrength: 20 },
          completedQuestCount: 0,
          proofCount: 0,
          streakCount: 0,
          xp: 0,
          xpGoal: 1000
        },
        privacy,
        allowsLongTermMemoryWrite: true
      },
      proof: {
        kind: "screenshot",
        text: "I compared three role requirements.",
        link: "https://example.com/private-proof",
        attachments: [{ contentType: "image/png", byteCount: 12000 }]
      },
      targetRoleTitle: "iOS engineer"
    }));

    expect(prompt.systemInstruction).toContain("No link contents were fetched or inspected");
    expect(prompt.systemInstruction).toContain("No attachment bytes or images were transmitted or inspected");
    expect(prompt.systemInstruction).toContain("attachment metadata only");
    expect(prompt.systemInstruction).toContain("The server applies acceptance, score, label, rewards, and inspection scope separately");
  });

  it("does not include client safety prose, credentials, budgets, or unrelated memory", () => {
    const prompt = buildLiveWorkflowPrompt(envelope("progressSummary", {
      context: {
        schemaVersion: 1,
        targetRoleTitle: "iOS engineer",
        currentQuest: null,
        progress: {
          readiness: { overall: 40, proofStrength: 30, confidence: 50, consistency: 35, skillProof: 30, networkStrength: 20 },
          completedQuestCount: 0,
          proofCount: 0,
          streakCount: 0,
          xp: 0,
          xpGoal: 1000
        },
        privacy,
        allowsLongTermMemoryWrite: true
      },
      targetRoleTitle: "iOS engineer"
    }));

    const serialized = JSON.stringify(prompt);
    expect(serialized).not.toContain("Never invent an employer or any other substantial career claim.");
    expect(serialized).not.toMatch(/API[_ -]?KEY|Bearer |dailyBudget|token price/i);
    expect(serialized.length).toBeLessThan(24_000);
  });
});
