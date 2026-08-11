import { describe, expect, it } from "vitest";
import {
  adaptiveCareerIntakePayloadSchema,
  diagnosticPayloadSchema,
  missionBriefPayloadSchema,
  proofQualityPayloadSchema,
  questPlanPayloadSchema
} from "../src/contracts.js";
import { makeDiagnostic, makeMissionBrief, makeQuestPlan, checkProofQuality } from "../src/mockWorkflows.js";
import { validateGeneratedWorkflowResult } from "../src/postValidation.js";

const goal = {
  currentStatus: "New graduate",
  targetRole: "iOS engineer",
  timeline: "12 weeks",
  background: "One class app",
  existingProof: "A local demo",
  confidence: 3,
  biggestBlocker: "Thin role-specific proof"
};

const privacy = {
  memoryMode: "cloudReady",
  allowsLongTermMemoryWrite: true,
  requiresUserApprovalForExternalActions: true,
  shareWins: false,
  allowsPrivateEvidenceCloudSync: false
} as const;

const context = {
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
};

describe("validateGeneratedWorkflowResult", () => {
  it("rejects a chapter-two plan with the wrong day range", () => {
    const payload = questPlanPayloadSchema.parse({
      goal: { ...goal, dailyCommitmentMinutes: 25 },
      diagnostic: {
        score: 62, label: "Recoverable", mainGap: "Needs proof", strongestSignal: "One class app",
        fastestFix: "Create one walkthrough", readinessBaseline: 48
      },
      chapterTwoContext: {
        sprintID: "11111111-1111-4111-8111-111111111111",
        checkpointSummary: "Seven focused actions completed.",
        nextFocus: "Use the strongest proof in applications.",
        readiness: context.progress.readiness,
        completedQuestCount: 7,
        proofCount: 7,
        outcomeCount: 0,
        completedQuestEvidence: Array.from({ length: 7 }, (_, index) => ({
          questTitle: `Quest ${index + 1}`, gap: "proofStrength", qualityScore: 80
        }))
      }
    });
    const candidate = makeQuestPlan(payload);
    const firstQuest = candidate.quests.at(0);
    if (!firstQuest) {
      throw new Error("Expected the generated plan to contain quests.");
    }
    firstQuest.day = 1;

    expect(validateGeneratedWorkflowResult("questPlan", payload, candidate)).toEqual({
      ok: false,
      reason: "invalidOutput"
    });
  });

  it("accepts a schema-valid grounded Cooked result", () => {
    const payload = diagnosticPayloadSchema.parse({ goal });
    expect(validateGeneratedWorkflowResult("cookedDiagnostic", payload, makeDiagnostic(payload)))
      .toMatchObject({ ok: true });
  });

  it("rejects invented substantial claims even when the shape is valid", () => {
    const payload = diagnosticPayloadSchema.parse({ goal });
    const result = {
      ...makeDiagnostic(payload),
      strongestSignal: "You worked at Apple for three years.",
      strongestSignals: ["You worked at Apple for three years."]
    };

    expect(validateGeneratedWorkflowResult("cookedDiagnostic", payload, result)).toEqual({
      ok: false,
      reason: "unsafeOutput"
    });
  });

  it("rejects claims that link or attachment contents were inspected", () => {
    const payload = proofQualityPayloadSchema.parse({
      context,
      proof: {
        kind: "screenshot",
        text: "I compared three role requirements.",
        link: "https://example.com/private-proof",
        attachments: [{ contentType: "image/png", byteCount: 12000 }]
      },
      targetRoleTitle: "iOS engineer"
    });
    const result = {
      ...checkProofQuality(payload),
      reason: "I inspected the screenshot and opened the link; both prove the work."
    };

    expect(validateGeneratedWorkflowResult("proofQualityCheck", payload, result)).toEqual({
      ok: false,
      reason: "unsafeOutput"
    });
  });

  it("rejects model-controlled XP and readiness rewards", () => {
    const payload = proofQualityPayloadSchema.parse({
      context,
      proof: { kind: "note", text: "A concrete comparison of three requirements with next steps.", link: "", attachments: [] },
      targetRoleTitle: "iOS engineer"
    });
    const result = { ...checkProofQuality(payload), xpEarned: 999, readinessDelta: 20 };

    expect(validateGeneratedWorkflowResult("proofQualityCheck", payload, result)).toEqual({
      ok: false,
      reason: "invalidOutput"
    });
  });

  it("rejects an adaptive hypothesis promoted to a confirmed fact", () => {
    const payload = adaptiveCareerIntakePayloadSchema.parse({
      confirmedFacts: [],
      pendingHypotheses: [],
      rejectedHypothesisIDs: [],
      unknownKinds: ["experience"],
      questionHistory: [],
      maxQuestions: 1
    });
    const result = {
      questions: [],
      hypotheses: [{ kind: "experience", value: "Shipped a production app", confirmationState: "confirmed" }]
    };

    expect(validateGeneratedWorkflowResult("adaptiveCareerIntake", payload, result)).toEqual({
      ok: false,
      reason: "invalidOutput"
    });
  });

  it("rejects adaptive questions beyond the requested count or known fields", () => {
    const payload = adaptiveCareerIntakePayloadSchema.parse({
      confirmedFacts: [],
      pendingHypotheses: [],
      rejectedHypothesisIDs: [],
      unknownKinds: ["experience"],
      questionHistory: [],
      maxQuestions: 1
    });
    const question = {
      id: "experience-question",
      factKind: "experience",
      question: "What relevant experience have you completed?",
      rationale: "This changes the first useful action.",
      responseType: "freeText",
      options: []
    };

    expect(validateGeneratedWorkflowResult("adaptiveCareerIntake", payload, {
      questions: [question, { ...question, id: "duplicate", factKind: "constraints" }],
      hypotheses: []
    })).toEqual({ ok: false, reason: "invalidOutput" });
  });

  it("keeps pending and newly generated adaptive hypotheses within the two-item review limit", () => {
    const payload = adaptiveCareerIntakePayloadSchema.parse({
      confirmedFacts: [],
      pendingHypotheses: [{
        id: "22222222-2222-4222-8222-222222222222",
        kind: "existingProof",
        value: "The class app may be available as proof.",
        source: "aiHypothesis",
        confirmationState: "awaitingConfirmation",
        lastUpdatedAt: "2026-08-10T10:01:00.000Z"
      }],
      rejectedHypothesisIDs: [],
      unknownKinds: ["existingProof", "constraints", "biggestBlocker"],
      questionHistory: [],
      maxQuestions: 1
    });

    expect(validateGeneratedWorkflowResult("adaptiveCareerIntake", payload, {
      questions: [],
      hypotheses: [
        { kind: "constraints", value: "Possible constraint", confirmationState: "awaitingConfirmation" },
        { kind: "biggestBlocker", value: "Possible blocker", confirmationState: "awaitingConfirmation" }
      ]
    })).toEqual({ ok: false, reason: "invalidOutput" });
  });

  it("rejects output claiming the system completed an external action", () => {
    const payload = diagnosticPayloadSchema.parse({ goal });
    const result = {
      ...makeDiagnostic(payload),
      firstAction: "I submitted your application and messaged the hiring manager."
    };

    expect(validateGeneratedWorkflowResult("cookedDiagnostic", payload, result)).toEqual({
      ok: false,
      reason: "unsafeOutput"
    });
  });

  it.each([
    ["target outcome", { targetOutcome: "Senior iOS engineer" }],
    ["confirmed current state", { confirmedCurrentState: [] }],
    ["constraints", { constraints: "No constraints" }],
    ["daily commitment", { dailyCommitmentMinutes: 90 }],
    ["ethical boundaries", { ethicalBoundaries: ["Be helpful."] }]
  ])("rejects a mission that changes the trusted %s", (_label, mutation) => {
    const payload = missionBriefPayloadSchema.parse({
      goal: { ...goal, constraints: "Weeknights only", dailyCommitmentMinutes: 30 },
      confirmedFacts: [{
        id: "11111111-1111-4111-8111-111111111111",
        kind: "experience",
        value: "One class app",
        source: "userEntry",
        confirmationState: "confirmed",
        lastUpdatedAt: "2026-08-10T10:01:00.000Z"
      }],
      diagnostic: makeDiagnostic(diagnosticPayloadSchema.parse({ goal })),
      requiredEthicalBoundaries: [
        "Use only truthful, defensible career claims.",
        "Never invent career history.",
        "The user approves every external action."
      ]
    });
    const result = { ...makeMissionBrief(payload), ...mutation };

    expect(validateGeneratedWorkflowResult("missionBrief", payload, result)).toEqual({
      ok: false,
      reason: "invalidOutput"
    });
  });
});
