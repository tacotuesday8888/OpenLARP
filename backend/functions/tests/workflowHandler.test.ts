import { describe, expect, it } from "vitest";
import type { InternalWorkflowRequest } from "../../ai/src/internalServiceContracts.js";
import { makeQuotaGuard } from "./quotaTestHelpers.js";
import type { AIRuntimePolicyReader } from "../src/aiRuntimePolicy.js";
import type { AIServiceClient } from "../src/aiServiceClient.js";
import type { ProviderBudgetGuard } from "../src/providerBudgetGuard.js";
import { handleOpenLARPWorkflowRequest, type OpenLARPWorkflowCallableResponse } from "../src/workflowHandler.js";

const privacy = {
  memoryMode: "cloudReady",
  allowsLongTermMemoryWrite: true,
  requiresUserApprovalForExternalActions: true,
  shareWins: false,
  allowsPrivateEvidenceCloudSync: false
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

const liveConfig = {
  modelId: "gemini-private-model-id",
  provider: "vertex-ai",
  vertexLocation: "global",
  enableLiveGeneration: true,
  maxOutputTokens: 1200
} as const;

const liveBudgetPolicy = {
  inputTokenMicrosPerThousand: 20,
  outputTokenMicrosPerThousand: 80,
  dailyBudgetMicros: 1_000_000
} as const;

function runtimePolicy(enabled = true): AIRuntimePolicyReader {
  return {
    async read() {
      return {
        enabled,
        policyRevision: "beta-2026-08-10",
        timeoutMs: 15_000,
        maxOutputTokens: 1200,
        fallbackReason: enabled ? null : "policy"
      };
    }
  };
}

function budgetGuard(options: { exhausted?: boolean; alreadyReserved?: boolean } = {}) {
  const reservations: Array<{ requestID: string; estimatedCostMicros: number; dailyBudgetMicros: number; occurredAt: Date }> = [];
  const reconciliations: Array<{ requestID: string; actualCostMicros: number; occurredAt: Date }> = [];
  const guard: ProviderBudgetGuard = {
    async reserve(input) {
      reservations.push(input);
      return options.exhausted
        ? { ok: false, reason: "budget" }
        : { ok: true, alreadyReserved: options.alreadyReserved ?? false };
    },
    async reconcile(input) {
      reconciliations.push(input);
    }
  };
  return { guard, reservations, reconciliations };
}

function liveDiagnostic() {
  return {
    score: 54,
    label: "Grounded live result",
    mainGap: "Role-specific proof is still thin.",
    strongestSignal: "One class project is confirmed.",
    fastestFix: "Create one small role-specific artifact.",
    readinessBaseline: 48,
    strongestSignals: ["One class project is confirmed."],
    readinessGaps: ["No role-specific artifact is confirmed."],
    missingInformation: ["The project outcome is unknown."],
    uncertaintyExplanation: "This result uses only confirmed information.",
    firstAction: "Map repeated requirements from two role descriptions."
  };
}

function liveService(options: { fail?: boolean } = {}) {
  const requests: Array<Omit<InternalWorkflowRequest, "schemaVersion">> = [];
  const service: AIServiceClient = {
    async run(request) {
      requests.push(request);
      if (options.fail) throw new Error("private provider detail");
      return {
        ok: true,
        schemaVersion: 1,
        requestID: request.envelope.run.requestID,
        kind: request.envelope.run.kind,
        externalActionTaken: false,
        result: liveDiagnostic(),
        execution: {
          schemaVersion: 1,
          liveModelCallsEnabled: true,
          liveModelUsed: true,
          usedFallback: false,
          fallbackReason: null,
          promptVersion: "openlarp.cooked.v1",
          policyRevision: request.policy.policyRevision,
          usage: { inputTokens: 120, outputTokens: 80, latencyBucket: "under5s" }
        }
      };
    }
  };
  return { service, requests };
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

  it("rejects internal and local provider routes at the public callable boundary", async () => {
    for (const providerRoute of ["cloudRunGenkit", "localMock"]) {
      const response = await authed(envelope("cookedDiagnostic", goalPayload(), {
        run: { providerRoute }
      }));
      expect(response).toMatchObject({ ok: false, code: "invalid-argument" });
    }
  });

  it("records per-user callable quota before dispatching safe workflows", async () => {
    const { guard, charges } = makeQuotaGuard();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      quotaGuard: guard,
      now: () => new Date("2026-06-18T12:00:00.000Z")
    });

    expectSuccess(response, "cookedDiagnostic");
    expect(charges).toEqual([{
      userID: "user_123",
      callable: "runOpenLARPWorkflow",
      category: "aiWorkflow",
      units: 1,
      auditKey: "11111111-1111-4111-8111-111111111111",
      occurredAt: new Date("2026-06-18T12:00:00.000Z"),
      metadata: {
        workflowKind: "cookedDiagnostic",
        providerRoute: "firebaseCallableGenkit",
        provider: "vertex-ai",
        liveModelCallsEnabled: false,
        estimatedInputTokens: expect.any(Number),
        maxOutputTokens: 1200,
        estimatedTotalTokens: expect.any(Number),
        priceConfigured: false,
        estimatedCostMicros: 0,
        budgetConfigured: false,
        budgetExceeded: false
      }
    }]);
    expect(JSON.stringify(charges)).not.toContain("AI product engineer");
  });

  it("dispatches enabled live workflows privately and reconciles actual provider usage", async () => {
    const { guard: quotaGuard } = makeQuotaGuard();
    const budget = budgetGuard();
    const live = liveService();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(),
      providerBudgetGuard: budget.guard,
      aiServiceClient: live.service,
      quotaGuard,
      now: () => new Date("2026-06-18T12:00:00.000Z")
    });

    expect(response).toMatchObject({
      ok: true,
      providerRoute: "firebaseCallableGenkit",
      liveModelCallsEnabled: true,
      liveModelUsed: true,
      usedFallback: false,
      fallbackReason: null,
      promptVersion: "openlarp.cooked.v1",
      policyRevision: "beta-2026-08-10",
      externalActionTaken: false,
      result: { label: "Grounded live result" }
    });
    expect(live.requests).toHaveLength(1);
    expect(live.requests[0]?.envelope.run.providerRoute).toBe("cloudRunGenkit");
    expect(budget.reservations).toHaveLength(1);
    expect(budget.reconciliations).toEqual([{
      requestID: "11111111-1111-4111-8111-111111111111",
      actualCostMicros: 10,
      occurredAt: new Date("2026-06-18T12:00:00.000Z")
    }]);
    expect(JSON.stringify(response)).not.toMatch(/gemini-private-model-id|cloudRunGenkit|a\.run\.app/);
  });

  it("uses an explicit deterministic fallback when runtime policy disables a live workflow", async () => {
    const { guard: quotaGuard } = makeQuotaGuard();
    const budget = budgetGuard();
    const live = liveService();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(false),
      providerBudgetGuard: budget.guard,
      aiServiceClient: live.service,
      quotaGuard
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelCallsEnabled: false,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "policy",
      policyRevision: "beta-2026-08-10"
    });
    expect(live.requests).toEqual([]);
    expect(budget.reservations).toEqual([]);
  });

  it("falls back without leaking provider details when private live dispatch fails", async () => {
    const budget = budgetGuard();
    const live = liveService({ fail: true });

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(),
      providerBudgetGuard: budget.guard,
      aiServiceClient: live.service
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelCallsEnabled: true,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "provider",
      result: { label: "Some proof, not enough signal" }
    });
    expect(budget.reconciliations).toEqual([expect.objectContaining({ actualCostMicros: 0 })]);
    expect(JSON.stringify(response)).not.toContain("private provider detail");
  });

  it("falls back without dispatch when the atomic daily budget reservation is refused", async () => {
    const budget = budgetGuard({ exhausted: true });
    const live = liveService();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(),
      providerBudgetGuard: budget.guard,
      aiServiceClient: live.service
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelCallsEnabled: true,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "budget"
    });
    expect(live.requests).toEqual([]);
    expect(budget.reconciliations).toEqual([]);
  });

  it("does not duplicate a provider call when a retried request ID already has a reservation", async () => {
    const budget = budgetGuard({ alreadyReserved: true });
    const live = liveService();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(),
      providerBudgetGuard: budget.guard,
      aiServiceClient: live.service
    });

    expect(response).toMatchObject({ ok: true, usedFallback: true, fallbackReason: "budget" });
    expect(live.requests).toEqual([]);
    expect(budget.reconciliations).toEqual([]);
  });

  it("releases a new reservation when the private AI service is not configured", async () => {
    const budget = budgetGuard();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(),
      providerBudgetGuard: budget.guard,
      aiServiceClient: null
    });

    expect(response).toMatchObject({ ok: true, usedFallback: true, fallbackReason: "provider" });
    expect(budget.reconciliations).toEqual([expect.objectContaining({ actualCostMicros: 0 })]);
  });

  it("releases a reservation and falls back when the callable quota store is unavailable", async () => {
    const budget = budgetGuard();
    const live = liveService();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: liveConfig,
      budgetPolicy: liveBudgetPolicy,
      runtimePolicyReader: runtimePolicy(),
      providerBudgetGuard: budget.guard,
      aiServiceClient: live.service,
      quotaGuard: { async checkAndRecord() { throw new Error("private Firestore detail"); } }
    });

    expect(response).toMatchObject({ ok: true, usedFallback: true, fallbackReason: "quota" });
    expect(live.requests).toEqual([]);
    expect(budget.reconciliations).toEqual([expect.objectContaining({ actualCostMicros: 0 })]);
    expect(JSON.stringify(response)).not.toContain("private Firestore detail");
  });

  it("falls back deterministically when provider pricing and budget config are missing", async () => {
    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      aiConfig: {
        modelId: "gemini-private-model-id",
        provider: "firebase-ai-logic",
        vertexLocation: "global",
        enableLiveGeneration: true,
        maxOutputTokens: 1200
      },
      budgetPolicy: null,
      runtimePolicyReader: runtimePolicy(),
      now: () => new Date("2026-06-18T12:00:00.000Z")
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelCallsEnabled: true,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "budget",
      policyRevision: "beta-2026-08-10"
    });
    expect(JSON.stringify(response)).not.toContain("gemini-private-model-id");
  });

  it("falls back before live dispatch when the estimated provider budget would be exceeded", async () => {
    const { guard, charges } = makeQuotaGuard();

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("proofQualityCheck", {
        context: workflowContext(),
        proof: {
          kind: "project_note",
          text: "Private proof text that must not be returned in budget errors.",
          link: "",
          attachments: []
        },
        targetRoleTitle: "AI product engineer"
      })
    }, {
      aiConfig: {
        modelId: "gemini-private-model-id",
        provider: "firebase-ai-logic",
        vertexLocation: "global",
        enableLiveGeneration: true,
        maxOutputTokens: 1200
      },
      budgetPolicy: {
        inputTokenMicrosPerThousand: 20,
        outputTokenMicrosPerThousand: 80,
        dailyBudgetMicros: 50
      },
      runtimePolicyReader: runtimePolicy(),
      quotaGuard: guard,
      now: () => new Date("2026-06-18T12:00:00.000Z")
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelCallsEnabled: true,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "budget"
    });
    expect(charges).toHaveLength(1);
    expect(JSON.stringify(response)).not.toContain("Private proof text");
    expect(JSON.stringify(response)).not.toContain("gemini-private-model-id");
  });

  it("uses an explicit deterministic fallback when live-workflow quota is exhausted", async () => {
    const { guard, charges } = makeQuotaGuard({ exhausted: true });

    const response = await handleOpenLARPWorkflowRequest({
      auth: { uid: "user_123" },
      data: envelope("cookedDiagnostic", goalPayload())
    }, {
      quotaGuard: guard,
      now: () => new Date("2026-06-18T12:00:00.000Z")
    });

    expect(response).toMatchObject({
      ok: true,
      liveModelCallsEnabled: false,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "quota"
    });
    expect(charges).toHaveLength(1);
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
    expect(response).toMatchObject({
      liveModelCallsEnabled: false,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason: "disabled",
      policyRevision: "environment-disabled"
    });
  });

  it("dispatches bounded deterministic adaptive intake when live AI is unavailable", async () => {
    const response = await authed(envelope("adaptiveCareerIntake", {
      confirmedFacts: [],
      pendingHypotheses: [],
      rejectedHypothesisIDs: [],
      unknownKinds: ["existingProof", "constraints", "confidence"],
      questionHistory: [],
      maxQuestions: 2
    }));

    expectSuccess(response, "adaptiveCareerIntake");
    expect(response.result).toMatchObject({
      questions: [
        { factKind: "existingProof" },
        { factKind: "constraints" }
      ],
      hypotheses: []
    });
    expect(response).toMatchObject({ usedFallback: true, fallbackReason: "disabled" });
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
      const isLiveWorkflow = ["questPlan", "proofQualityCheck", "progressSummary"].includes(kind);
      expect(response.usedFallback).toBe(isLiveWorkflow);
      expect(response.fallbackReason).toBe(isLiveWorkflow ? "disabled" : null);
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
