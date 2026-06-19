import { describe, expect, it } from "vitest";
import { DEFAULT_GEMINI_MODEL_ID, configFromEnvironment } from "../src/config.js";
import {
  agentScanPayloadSchema,
  careerBriefPayloadSchema,
  diagnosticPayloadSchema,
  implementedWorkflowKinds,
  opportunityRankingPayloadSchema,
  requestEnvelopeSchema,
  safeShareCardTextPayloadSchema,
  safetyRulesSchema
} from "../src/contracts.js";
import {
  makeAgentScan,
  makeCareerBrief,
  makeDiagnostic,
  makeSafeShareCardText,
  rankOpportunities
} from "../src/mockWorkflows.js";
import { assertSafeGeneratedText, validateEnvelopeSafety } from "../src/safety.js";

const safeEnvelope = {
  schemaVersion: 1,
  run: {
    schemaVersion: 1,
    kind: "cookedDiagnostic",
    providerRoute: "cloudRunGenkit",
    requestedAt: "2026-06-18T00:00:00.000Z",
    requestID: "11111111-1111-1111-1111-111111111111",
    privacy: {
      memoryMode: "localOnly",
      allowsLongTermMemoryWrite: false,
      requiresUserApprovalForExternalActions: true,
      shareWins: false,
      allowsPrivateEvidenceCloudSync: false
    }
  },
  safetyRules: {
    hardBannedClaims: [
      "fake employers",
      "fake schools",
      "fake certificates",
      "fake job titles",
      "fake dates",
      "fake projects",
      "fake ownership claims"
    ],
    requiredBehaviors: [
      "frame real experience honestly",
      "separate proof from self-report",
      "recommend small truthful next steps"
    ],
    privacyRequirements: [
      "do not request provider credentials",
      "do not write long-term memory unless the user enabled it",
      "do not take external actions without approval"
    ]
  },
  payload: {
    goal: {
      currentStatus: "student",
      targetRole: "AI product internship",
      timeline: "30 days",
      background: "Second-year CS student",
      existingProof: "Class project",
      confidence: 3,
      biggestBlocker: "Needs stronger product proof."
    }
  }
};

const workflowContext = {
  schemaVersion: 1,
  targetRoleTitle: "AI product engineer",
  currentQuest: {
    day: 1,
    title: "Map AI product proof gaps",
    purpose: "Turn a broad goal into evidence.",
    timeEstimateMinutes: 25,
    difficulty: "Starter",
    gap: "proofStrength",
    proofRequired: "A saved note or link",
    xpReward: 120,
    steps: ["Find a role", "List requirements", "Pick one proof target"]
  },
  progress: {
    readiness: {
      overall: 58,
      proofStrength: 52,
      confidence: 61,
      consistency: 64,
      skillProof: 49,
      networkStrength: 45
    },
    completedQuestCount: 4,
    proofCount: 3,
    streakCount: 2,
    xp: 460,
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
};

const aiProductOpportunity = {
  type: "Project",
  title: "AI product artifact sprint",
  sourceName: "OpenLARP Agent",
  fitScore: 92,
  urgencyScore: 80,
  missingProofScore: 88,
  impactScore: 90,
  whyItMatters: "Directly creates role-specific proof.",
  missingProof: "AI product proof artifact",
  recommendedAction: "Build the artifact and save proof.",
  approvalRequired: true
} as const;

describe("OpenLARP AI backend contracts", () => {
  it("keeps Gemini model configuration server-side", () => {
    expect(DEFAULT_GEMINI_MODEL_ID).toBe("gemini-3.1-flash-lite");
    expect(configFromEnvironment({}).modelId).toBe("gemini-3.1-flash-lite");
    expect(configFromEnvironment({ OPENLARP_GEMINI_MODEL_ID: "gemini-test" }).modelId).toBe("gemini-test");
    expect(configFromEnvironment({ OPENLARP_AI_PROVIDER: "local-mock" }).provider).toBe("local-mock");
    expect(configFromEnvironment({ OPENLARP_AI_MAX_OUTPUT_TOKENS: "2048" }).maxOutputTokens).toBe(2048);
    expect(() => configFromEnvironment({ OPENLARP_AI_PROVIDER: "client-llm" })).toThrow(/Unsupported/);
    expect(() => configFromEnvironment({ OPENLARP_AI_MAX_OUTPUT_TOKENS: "not-a-number" })).toThrow(/MAX_OUTPUT_TOKENS/);
  });

  it("validates backend-safe request envelopes and safety rules", () => {
    const envelope = requestEnvelopeSchema.parse(safeEnvelope);
    const safetyRules = safetyRulesSchema.parse(safeEnvelope.safetyRules);

    expect(safetyRules.hardBannedClaims).toContain("fake employers");
    expect(validateEnvelopeSafety(envelope)).toEqual({
      ok: true,
      blockedReasons: []
    });
  });

  it("keeps every accepted workflow kind backed by a deterministic contract path", () => {
    expect(implementedWorkflowKinds).toEqual([
      "cookedDiagnostic",
      "questPlan",
      "proofQualityCheck",
      "progressSummary",
      "careerBrief",
      "safeShareCardText",
      "opportunityRanking",
      "agentScan"
    ]);
  });

  it("rejects envelopes that disable external-action approval", () => {
    const envelope = requestEnvelopeSchema.parse({
      ...safeEnvelope,
      run: {
        ...safeEnvelope.run,
        privacy: {
          ...safeEnvelope.run.privacy,
          requiresUserApprovalForExternalActions: false
        }
      }
    });

    expect(validateEnvelopeSafety(envelope).ok).toBe(false);
    expect(validateEnvelopeSafety(envelope).blockedReasons).toContain("external actions must require user approval");
  });

  it("rejects contradictory long-term memory settings", () => {
    const envelope = requestEnvelopeSchema.parse({
      ...safeEnvelope,
      run: {
        ...safeEnvelope.run,
        privacy: {
          ...safeEnvelope.run.privacy,
          memoryMode: "localOnly",
          allowsLongTermMemoryWrite: true
        }
      }
    });

    expect(validateEnvelopeSafety(envelope).ok).toBe(false);
    expect(validateEnvelopeSafety(envelope).blockedReasons).toContain("long-term memory writes require cloud-ready memory mode");
  });

  it("accepts normalized equivalent safety wording", () => {
    const envelope = requestEnvelopeSchema.parse({
      ...safeEnvelope,
      safetyRules: {
        ...safeEnvelope.safetyRules,
        hardBannedClaims: [
          "Never fabricate an employer, school, certificate, title, date, project, or ownership claim."
        ],
        privacyRequirements: [
          "Any external action needs user approval before the system acts."
        ]
      }
    });

    expect(validateEnvelopeSafety(envelope)).toEqual({
      ok: true,
      blockedReasons: []
    });
  });

  it("rejects external-action wording that mentions users without approval", () => {
    const envelope = requestEnvelopeSchema.parse({
      ...safeEnvelope,
      safetyRules: {
        ...safeEnvelope.safetyRules,
        privacyRequirements: [
          "Notify the user after an external action is completed."
        ]
      }
    });

    expect(validateEnvelopeSafety(envelope).ok).toBe(false);
    expect(validateEnvelopeSafety(envelope).blockedReasons).toContain("missing external-action approval guardrail");
  });

  it("creates deterministic diagnostic output from valid payloads", () => {
    const payload = diagnosticPayloadSchema.parse(safeEnvelope.payload);

    const diagnostic = makeDiagnostic(payload);

    expect(diagnostic.score).toBeGreaterThanOrEqual(50);
    expect(diagnostic.mainGap).toContain("AI product internship");
    expect(diagnostic.fastestFix).toContain("artifact");
  });

  it("blocks unsafe generated wording that encourages fake claims", () => {
    expect(() => assertSafeGeneratedText("Invent a certificate and say you worked at a famous employer."))
      .toThrow(/Unsafe generated text blocked/);
  });

  it("ranks opportunities by fit, urgency, missing proof, and impact", () => {
    const payload = opportunityRankingPayloadSchema.parse({
      targetRole: {
        title: "AI product engineer",
        keywords: ["ai", "product"]
      },
      opportunities: [
        {
          type: "Course",
          title: "Generic project management course",
          sourceName: "Course scan",
          fitScore: 60,
          urgencyScore: 30,
          missingProofScore: 40,
          impactScore: 45,
          whyItMatters: "Could help, but it is broad.",
          missingProof: "General skill proof",
          recommendedAction: "Only take it if it creates a portfolio receipt.",
          approvalRequired: true
        },
        {
          type: "Project",
          title: "AI product artifact sprint",
          sourceName: "OpenLARP Agent",
          fitScore: 92,
          urgencyScore: 80,
          missingProofScore: 88,
          impactScore: 90,
          whyItMatters: "Directly creates role-specific proof.",
          missingProof: "AI product proof artifact",
          recommendedAction: "Build the artifact and save proof.",
          approvalRequired: true
        }
      ]
    });

    const ranked = rankOpportunities(payload).opportunities;

    expect(ranked[0]?.title).toBe("AI product artifact sprint");
    expect(ranked[0]?.rank).toBe(1);
    expect(ranked[0]?.compositeScore).toBeGreaterThan(ranked[1]?.compositeScore ?? 0);
  });

  it("creates a career brief from readiness context and ranked opportunities", () => {
    const payload = careerBriefPayloadSchema.parse({
      context: workflowContext,
      targetRoleTitle: "AI product engineer",
      opportunities: [aiProductOpportunity]
    });

    const brief = makeCareerBrief(payload);

    expect(brief.title).toContain("AI product engineer");
    expect(brief.opportunities[0]?.rank).toBe(1);
    expect(brief.nextSteps.length).toBeGreaterThanOrEqual(1);
  });

  it("creates review-required safe share text without provider secrets or fake claims", () => {
    const payload = safeShareCardTextPayloadSchema.parse({
      context: workflowContext,
      targetRoleTitle: "AI product engineer",
      proof: {
        kind: "note",
        text: "a product teardown comparing AI onboarding prompts",
        link: "",
        attachments: []
      }
    });

    const shareText = makeSafeShareCardText(payload);

    expect(shareText.shareable).toBe(true);
    expect(shareText.disclosure).toContain("Review before sharing");
    expect(shareText.body).toContain("AI product engineer");
    expect(shareText.body).not.toContain("product teardown");
  });

  it("creates an agent scan brief from approved sources and ranked findings", () => {
    const payload = agentScanPayloadSchema.parse({
      targetRole: {
        title: "AI product engineer",
        keywords: ["ai", "product"]
      },
      approvedSources: [
        {
          type: "projectBoard",
          name: "Approved project source",
          url: "https://example.com/projects"
        }
      ],
      opportunities: [aiProductOpportunity]
    });

    const scan = makeAgentScan(payload);

    expect(scan.scannedSourceCount).toBe(1);
    expect(scan.findings[0]?.title).toBe("AI product artifact sprint");
    expect(scan.recommendedNextActions[0]).toContain("Build the artifact");
  });
});
