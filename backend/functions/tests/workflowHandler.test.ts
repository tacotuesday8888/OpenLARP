import { describe, expect, it } from "vitest";
import { handleOpenLARPWorkflowRequest, type OpenLARPWorkflowCallableResponse } from "../src/workflowHandler.js";

const privacy = {
  memoryMode: "cloudReady",
  allowsLongTermMemoryWrite: true,
  requiresUserApprovalForExternalActions: true,
  shareWins: false
} as const;

const safetyRules = {
  hardBannedClaims: [
    "Do not invent fake employers, fake schools, fake certificates, fake titles, fake dates, fake projects, or fake ownership."
  ],
  requiredBehaviors: [
    "Keep career recommendations tied to evidence and user-approved actions."
  ],
  privacyRequirements: [
    "external actions require user approval before the system can act."
  ]
};

const readiness = {
  overall: 48,
  proofStrength: 42,
  confidence: 51,
  consistency: 39,
  skillProof: 44,
  networkStrength: 30
};

const progress = {
  readiness,
  completedQuestCount: 2,
  proofCount: 3,
  streakCount: 2,
  xp: 420,
  xpGoal: 1000
};

function envelope(kind: string, payload: unknown, overrides: Record<string, unknown> = {}) {
  return {
    schemaVersion: 1,
    run: {
      schemaVersion: 1,
      kind,
      providerRoute: "firebaseCallableGenkit",
      requestedAt: "2026-06-18T10:00:00.000Z",
      requestID: "11111111-1111-4111-8111-111111111111",
      privacy,
      ...((overrides.run as Record<string, unknown> | undefined) ?? {})
    },
    safetyRules: {
      ...safetyRules,
      ...((overrides.safetyRules as Record<string, unknown> | undefined) ?? {})
    },
    payload
  };
}

function authed(data: unknown) {
  return handleOpenLARPWorkflowRequest({
    auth: { uid: "user_123" },
    data
  });
}

function goalPayload() {
  return {
    goal: {
      currentStatus: "New graduate",
      targetRole: "AI product engineer",
      timeline: "12 weeks",
      background: "CS student with one shipped class project.",
      existingProof: "GitHub project and internship notes.",
      confidence: 3,
      biggestBlocker: "Not enough role-specific proof."
    },
    requestedAt: "2026-06-18T10:00:00.000Z"
  };
}

function workflowContext() {
  return {
    schemaVersion: 1,
    targetRoleTitle: "AI product engineer",
    currentQuest: {
      day: 1,
      title: "Map AI role requirements",
      purpose: "Identify proof gaps.",
      timeEstimateMinutes: 25,
      difficulty: "Starter",
      gap: "proofStrength",
      proofRequired: "Requirement notes",
      xpReward: 120,
      steps: ["Read two role descriptions", "List repeated requirements"]
    },
    progress,
    privacy,
    allowsLongTermMemoryWrite: true
  };
}

function proof() {
  return {
    kind: "project_note",
    text: "I mapped requirements from three AI product engineer postings and tied them to my existing project evidence.",
    link: "https://example.com/proof",
    attachments: [
      {
        contentType: "application/pdf",
        byteCount: 24_000
      }
    ]
  };
}

function opportunity() {
  return {
    type: "Project",
    title: "AI Product Engineer Portfolio Sprint",
    sourceName: "OpenLARP sample source",
    fitScore: 86,
    urgencyScore: 74,
    missingProofScore: 82,
    impactScore: 88,
    whyItMatters: "It creates direct proof for AI product engineering.",
    missingProof: "Shipped AI product spec and prototype.",
    recommendedAction: "Complete a two-day prototype and save proof.",
    deadline: "2026-07-01T10:00:00.000Z",
    approvalRequired: true
  };
}

describe("handleOpenLARPWorkflowRequest", () => {
  it("requires Firebase Auth before dispatch", async () => {
    const response = await handleOpenLARPWorkflowRequest({
      auth: null,
      data: envelope("cookedDiagnostic", goalPayload())
    });

    expect(response).toMatchObject({
      ok: false,
      code: "unauthenticated"
    });
  });

  it("rejects malformed envelopes", async () => {
    const response = await authed({ schemaVersion: 1 });

    expect(response).toMatchObject({
      ok: false,
      code: "invalid-argument"
    });
  });

  it("enforces OpenLARP safety guardrails before dispatch", async () => {
    const response = await authed(
      envelope("cookedDiagnostic", goalPayload(), {
        safetyRules: {
          hardBannedClaims: ["Do not fabricate claims."]
        }
      })
    );

    expect(response).toMatchObject({
      ok: false,
      code: "failed-precondition"
    });
  });

  it("blocks requests that try to mark external opportunities as pre-approved", async () => {
    const response = await authed(
      envelope("opportunityRanking", {
        targetRole: {
          title: "AI product engineer",
          keywords: ["AI", "product", "engineer"]
        },
        opportunities: [
          {
            ...opportunity(),
            approvalRequired: false
          }
        ]
      })
    );

    expect(response).toMatchObject({
      ok: false,
      code: "permission-denied"
    });
  });

  it("dispatches deterministic diagnostic workflows", async () => {
    const response = await authed(envelope("cookedDiagnostic", goalPayload()));

    expectSuccess(response, "cookedDiagnostic");
    expect(response.result).toMatchObject({
      label: "Some proof, not enough signal",
      readinessBaseline: 48
    });
  });

  it("dispatches deterministic workflows for every implemented kind", async () => {
    const diagnostic = {
      score: 62,
      label: "Some proof, not enough signal",
      mainGap: "Needs more evidence",
      strongestSignal: "Has project proof",
      fastestFix: "Create one artifact",
      readinessBaseline: 48
    };

    const cases = [
      ["questPlan", { ...goalPayload(), diagnostic }],
      ["proofQualityCheck", { context: workflowContext(), proof: proof(), targetRoleTitle: "AI product engineer" }],
      ["progressSummary", { context: workflowContext(), targetRoleTitle: "AI product engineer" }],
      ["careerBrief", { context: workflowContext(), targetRoleTitle: "AI product engineer", opportunities: [opportunity()] }],
      ["safeShareCardText", { context: workflowContext(), proof: proof(), targetRoleTitle: "AI product engineer", maxCharacters: 280 }],
      ["opportunityRanking", {
        targetRole: { title: "AI product engineer", keywords: ["AI", "product", "engineer"] },
        opportunities: [opportunity()]
      }],
      ["agentScan", {
        targetRole: { title: "AI product engineer", keywords: ["AI", "product", "engineer"] },
        approvedSources: [{ type: "projectBoard", name: "University projects", url: "https://example.com/projects" }],
        opportunities: [opportunity()]
      }]
    ] as const;

    for (const [kind, payload] of cases) {
      const response = await authed(envelope(kind, payload));
      expectSuccess(response, kind);
      expect(response.liveModelCallsEnabled).toBe(false);
      expect(response.externalActionTaken).toBe(false);
    }
  });
});

function expectSuccess(response: OpenLARPWorkflowCallableResponse, kind: string): asserts response is Extract<OpenLARPWorkflowCallableResponse, { ok: true }> {
  expect(response).toMatchObject({
    ok: true,
    schemaVersion: 1,
    kind,
    userID: "user_123",
    providerRoute: "firebaseCallableGenkit",
    liveModelCallsEnabled: false,
    externalActionTaken: false
  });
}
