import {
  adaptiveCareerIntakePayloadSchema,
  adaptiveCareerIntakeResponseSchema,
  agentScanPayloadSchema,
  agentScanResponseSchema,
  careerBriefPayloadSchema,
  careerBriefResponseSchema,
  diagnosticPayloadSchema,
  diagnosticResponseSchema,
  opportunityRankingPayloadSchema,
  opportunityRankingResponseSchema,
  progressSummaryPayloadSchema,
  progressSummaryResponseSchema,
  proofQualityPayloadSchema,
  proofQualityResponseSchema,
  questPlanPayloadSchema,
  questPlanResponseSchema,
  requestEnvelopeSchema,
  safeShareCardTextPayloadSchema,
  safeShareCardTextResponseSchema,
  type RequestEnvelope,
  type WorkflowKind
} from "../../ai/src/contracts.js";
import {
  configFromEnvironment,
  providerBudgetPolicyFromEnvironment,
  type OpenLARPAIBackendConfig,
  type OpenLARPAIProviderBudgetPolicy
} from "../../ai/src/config.js";
import {
  estimateProviderUsage,
  providerCostMicros,
  providerUsageMetadata
} from "../../ai/src/costAccounting.js";
import {
  checkProofQuality,
  makeAdaptiveCareerIntake,
  makeAgentScan,
  makeCareerBrief,
  makeDiagnostic,
  makeQuestPlan,
  makeSafeShareCardText,
  rankOpportunities,
  summarizeProgress
} from "../../ai/src/mockWorkflows.js";
import { validateEnvelopeSafety } from "../../ai/src/safety.js";
import { type AIRuntimePolicyDecision, type AIRuntimePolicyReader } from "./aiRuntimePolicy.js";
import { type AIServiceClient } from "./aiServiceClient.js";
import { type CallableQuotaGuard } from "./callableQuotaGuard.js";
import { functionError, type OpenLARPFunctionError } from "./errors.js";
import { type ProviderBudgetGuard } from "./providerBudgetGuard.js";

const LIVE_WORKFLOW_KINDS: ReadonlySet<WorkflowKind> = new Set([
  "adaptiveCareerIntake",
  "cookedDiagnostic",
  "questPlan",
  "proofQualityCheck",
  "progressSummary"
]);

type FallbackReason =
  | "disabled"
  | "policy"
  | "quota"
  | "budget"
  | "timeout"
  | "provider"
  | "invalidOutput"
  | "unsafeOutput";

type CallableExecutionMetadata = {
  liveModelCallsEnabled: boolean;
  liveModelUsed: boolean;
  usedFallback: boolean;
  fallbackReason: FallbackReason | null;
  promptVersion: string | null;
  policyRevision: string;
};

export type OpenLARPCallableAuth = {
  uid: string;
  token?: Record<string, unknown>;
};

export type OpenLARPWorkflowCallableRequest = {
  auth?: OpenLARPCallableAuth | null;
  data: unknown;
};

export type OpenLARPWorkflowCallableSuccess = {
  ok: true;
  schemaVersion: 1;
  requestID: string;
  kind: WorkflowKind;
  userID: string;
  evaluatedAt: string;
  providerRoute: "firebaseCallableGenkit";
  liveModelCallsEnabled: boolean;
  liveModelUsed: boolean;
  usedFallback: boolean;
  fallbackReason: FallbackReason | null;
  promptVersion: string | null;
  policyRevision: string;
  externalActionTaken: false;
  result: unknown;
};

export type OpenLARPWorkflowCallableResponse =
  | OpenLARPWorkflowCallableSuccess
  | OpenLARPFunctionError;

export type OpenLARPWorkflowDependencies = {
  aiConfig?: OpenLARPAIBackendConfig;
  budgetPolicy?: OpenLARPAIProviderBudgetPolicy | null;
  quotaGuard?: CallableQuotaGuard;
  runtimePolicyReader?: AIRuntimePolicyReader;
  providerBudgetGuard?: ProviderBudgetGuard;
  aiServiceClient?: AIServiceClient | null;
  now?: () => Date;
};

export async function handleOpenLARPWorkflowRequest(
  request: OpenLARPWorkflowCallableRequest,
  dependencies: OpenLARPWorkflowDependencies = {}
): Promise<OpenLARPWorkflowCallableResponse> {
  const userID = request.auth?.uid;
  if (!userID) {
    return functionError("unauthenticated", "Sign in before running OpenLARP AI workflows.");
  }

  const parsedEnvelope = requestEnvelopeSchema.safeParse(request.data);
  if (!parsedEnvelope.success) {
    return functionError("invalid-argument", "Request envelope did not match the OpenLARP AI contract.", {
      issues: parsedEnvelope.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message
      }))
    });
  }
  if (parsedEnvelope.data.run.providerRoute !== "firebaseCallableGenkit") {
    return functionError("invalid-argument", "Public workflow requests require the Firebase callable provider route.");
  }

  const safety = validateEnvelopeSafety(parsedEnvelope.data);
  if (!safety.ok) {
    return functionError("failed-precondition", "Request failed OpenLARP safety guardrails.", {
      blockedReasons: safety.blockedReasons
    });
  }

  const externalActionViolation = findExternalActionViolation(parsedEnvelope.data.payload);
  if (externalActionViolation) {
    return functionError("permission-denied", externalActionViolation);
  }

  let deterministicResult: unknown;
  try {
    deterministicResult = dispatchDeterministicWorkflow(parsedEnvelope.data);
  } catch (error) {
    return functionError("invalid-argument", "Workflow payload did not match its declared kind.", {
      message: error instanceof Error ? error.message : "Unknown workflow dispatch error"
    });
  }

  const evaluatedAt = dependencies.now?.() ?? new Date();
  const isLiveWorkflow = LIVE_WORKFLOW_KINDS.has(parsedEnvelope.data.run.kind);
  let aiConfig: OpenLARPAIBackendConfig | null = null;
  let budgetPolicy: OpenLARPAIProviderBudgetPolicy | null = null;
  let runtimeDecision: AIRuntimePolicyDecision | null = null;
  let fallbackReason: FallbackReason | null = null;

  if (isLiveWorkflow) {
    try {
      aiConfig = dependencies.aiConfig ?? configFromEnvironment();
    } catch {
      fallbackReason = "policy";
    }

    if (aiConfig && !aiConfig.enableLiveGeneration) {
      fallbackReason = "disabled";
      runtimeDecision = disabledRuntimeDecision();
    } else if (aiConfig) {
      try {
        runtimeDecision = dependencies.runtimePolicyReader
          ? await dependencies.runtimePolicyReader.read(parsedEnvelope.data.run.kind, evaluatedAt)
          : unavailableRuntimeDecision();
      } catch {
        runtimeDecision = unavailableRuntimeDecision();
      }
      if (!runtimeDecision.enabled) {
        fallbackReason = "policy";
      }
    }

    if (runtimeDecision?.enabled) {
      try {
        budgetPolicy = dependencies.budgetPolicy === undefined
          ? providerBudgetPolicyFromEnvironment()
          : dependencies.budgetPolicy;
      } catch {
        fallbackReason = "budget";
      }
    }
  }

  const effectiveConfig = aiConfig && runtimeDecision
    ? { ...aiConfig, maxOutputTokens: Math.min(aiConfig.maxOutputTokens, runtimeDecision.maxOutputTokens) }
    : aiConfig;
  const providerUsage = effectiveConfig
    ? estimateProviderUsage({
        config: effectiveConfig,
        workflowKind: parsedEnvelope.data.run.kind,
        payload: parsedEnvelope.data.payload,
        budgetPolicy
      })
    : null;
  const liveModelCallsEnabled = Boolean(
    isLiveWorkflow && aiConfig?.enableLiveGeneration && runtimeDecision?.enabled
  );
  let providerBudgetReserved = false;

  if (liveModelCallsEnabled && fallbackReason === null) {
    const estimatedCostMicros = providerUsage?.estimatedCostMicros;
    if (!budgetPolicy || estimatedCostMicros === null || estimatedCostMicros === undefined || !dependencies.providerBudgetGuard) {
      fallbackReason = "budget";
    } else if (providerUsage?.budgetExceeded) {
      fallbackReason = "budget";
    } else {
      try {
        const reservation = await dependencies.providerBudgetGuard.reserve({
          requestID: parsedEnvelope.data.run.requestID,
          estimatedCostMicros,
          dailyBudgetMicros: budgetPolicy.dailyBudgetMicros,
          occurredAt: evaluatedAt
        });
        providerBudgetReserved = reservation.ok && !reservation.alreadyReserved;
        if (!reservation.ok || reservation.alreadyReserved) fallbackReason = "budget";
      } catch {
        fallbackReason = "budget";
      }
    }
  }

  let quotaDecision: Awaited<ReturnType<CallableQuotaGuard["checkAndRecord"]>> | undefined;
  try {
    quotaDecision = await dependencies.quotaGuard?.checkAndRecord({
      userID,
      callable: "runOpenLARPWorkflow",
      category: "aiWorkflow",
      units: 1,
      auditKey: parsedEnvelope.data.run.requestID,
      occurredAt: evaluatedAt,
      metadata: {
        providerRoute: parsedEnvelope.data.run.providerRoute,
        workflowKind: parsedEnvelope.data.run.kind,
        ...(providerUsage ? providerUsageMetadata(providerUsage) : {})
      }
    });
  } catch {
    if (providerBudgetReserved) {
      await safelyReconcileBudget(dependencies.providerBudgetGuard, {
        requestID: parsedEnvelope.data.run.requestID,
        actualCostMicros: 0,
        occurredAt: evaluatedAt
      });
    }
    if (isLiveWorkflow) {
      return callableSuccess({
        envelope: parsedEnvelope.data,
        userID,
        evaluatedAt,
        result: deterministicResult,
        execution: fallbackExecution(liveModelCallsEnabled, "quota", runtimeDecision?.policyRevision ?? "unavailable")
      });
    }
    return functionError("internal", "OpenLARP callable quota could not be checked.");
  }
  if (quotaDecision && !quotaDecision.ok) {
    if (providerBudgetReserved) {
      await safelyReconcileBudget(dependencies.providerBudgetGuard, {
        requestID: parsedEnvelope.data.run.requestID,
        actualCostMicros: 0,
        occurredAt: evaluatedAt
      });
    }
    if (isLiveWorkflow && quotaDecision.error.code === "resource-exhausted") {
      return callableSuccess({
        envelope: parsedEnvelope.data,
        userID,
        evaluatedAt,
        result: deterministicResult,
        execution: fallbackExecution(liveModelCallsEnabled, "quota", runtimeDecision?.policyRevision ?? "unavailable")
      });
    }
    return quotaDecision.error;
  }

  if (!isLiveWorkflow) {
    return callableSuccess({
      envelope: parsedEnvelope.data,
      userID,
      evaluatedAt,
      result: deterministicResult,
      execution: deterministicExecution()
    });
  }

  if (fallbackReason !== null || !runtimeDecision) {
    return callableSuccess({
      envelope: parsedEnvelope.data,
      userID,
      evaluatedAt,
      result: deterministicResult,
      execution: fallbackExecution(
        liveModelCallsEnabled,
        fallbackReason ?? "policy",
        runtimeDecision?.policyRevision ?? "unavailable"
      )
    });
  }

  if (!dependencies.aiServiceClient || !budgetPolicy || !providerBudgetReserved) {
    if (providerBudgetReserved) {
      await safelyReconcileBudget(dependencies.providerBudgetGuard, {
        requestID: parsedEnvelope.data.run.requestID,
        actualCostMicros: 0,
        occurredAt: evaluatedAt
      });
    }
    return callableSuccess({
      envelope: parsedEnvelope.data,
      userID,
      evaluatedAt,
      result: deterministicResult,
      execution: fallbackExecution(liveModelCallsEnabled, "provider", runtimeDecision.policyRevision)
    });
  }

  try {
    const serviceResponse = await dependencies.aiServiceClient.run({
      envelope: {
        ...parsedEnvelope.data,
        run: { ...parsedEnvelope.data.run, providerRoute: "cloudRunGenkit" }
      },
      policy: {
        enabled: true,
        policyRevision: runtimeDecision.policyRevision,
        timeoutMs: runtimeDecision.timeoutMs,
        maxOutputTokens: Math.min(runtimeDecision.maxOutputTokens, aiConfig?.maxOutputTokens ?? runtimeDecision.maxOutputTokens)
      }
    });
    const actualCostMicros = providerCostMicros({
      inputTokens: serviceResponse.execution.usage.inputTokens,
      outputTokens: serviceResponse.execution.usage.outputTokens,
      budgetPolicy
    });
    await safelyReconcileBudget(dependencies.providerBudgetGuard, {
      requestID: parsedEnvelope.data.run.requestID,
      actualCostMicros,
      occurredAt: evaluatedAt
    });
    return callableSuccess({
      envelope: parsedEnvelope.data,
      userID,
      evaluatedAt,
      result: serviceResponse.result,
      execution: {
        liveModelCallsEnabled: serviceResponse.execution.liveModelCallsEnabled,
        liveModelUsed: serviceResponse.execution.liveModelUsed,
        usedFallback: serviceResponse.execution.usedFallback,
        fallbackReason: serviceResponse.execution.fallbackReason,
        promptVersion: serviceResponse.execution.promptVersion,
        policyRevision: serviceResponse.execution.policyRevision
      }
    });
  } catch {
    await safelyReconcileBudget(dependencies.providerBudgetGuard, {
      requestID: parsedEnvelope.data.run.requestID,
      actualCostMicros: 0,
      occurredAt: evaluatedAt
    });
    return callableSuccess({
      envelope: parsedEnvelope.data,
      userID,
      evaluatedAt,
      result: deterministicResult,
      execution: fallbackExecution(liveModelCallsEnabled, "provider", runtimeDecision.policyRevision)
    });
  }
}

function callableSuccess(input: {
  envelope: RequestEnvelope;
  userID: string;
  evaluatedAt: Date;
  result: unknown;
  execution: CallableExecutionMetadata;
}): OpenLARPWorkflowCallableSuccess {
  return {
    ok: true,
    schemaVersion: 1,
    requestID: input.envelope.run.requestID,
    kind: input.envelope.run.kind,
    userID: input.userID,
    evaluatedAt: input.evaluatedAt.toISOString(),
    providerRoute: "firebaseCallableGenkit",
    ...input.execution,
    externalActionTaken: false,
    result: input.result
  };
}

function deterministicExecution(): CallableExecutionMetadata {
  return {
    liveModelCallsEnabled: false,
    liveModelUsed: false,
    usedFallback: false,
    fallbackReason: null,
    promptVersion: null,
    policyRevision: "deterministic-v1"
  };
}

function fallbackExecution(
  liveModelCallsEnabled: boolean,
  fallbackReason: FallbackReason,
  policyRevision: string
): CallableExecutionMetadata {
  return {
    liveModelCallsEnabled,
    liveModelUsed: false,
    usedFallback: true,
    fallbackReason,
    promptVersion: null,
    policyRevision
  };
}

function disabledRuntimeDecision(): AIRuntimePolicyDecision {
  return {
    enabled: false,
    policyRevision: "environment-disabled",
    timeoutMs: 10_000,
    maxOutputTokens: 1200,
    fallbackReason: "policy"
  };
}

function unavailableRuntimeDecision(): AIRuntimePolicyDecision {
  return {
    enabled: false,
    policyRevision: "unavailable",
    timeoutMs: 10_000,
    maxOutputTokens: 1200,
    fallbackReason: "policy"
  };
}

async function safelyReconcileBudget(
  guard: ProviderBudgetGuard | undefined,
  input: Parameters<ProviderBudgetGuard["reconcile"]>[0]
): Promise<void> {
  try {
    await guard?.reconcile(input);
  } catch {
    // A failed ledger reconciliation must remain conservatively reserved and must not expose provider details.
  }
}

function dispatchDeterministicWorkflow(envelope: RequestEnvelope): unknown {
  switch (envelope.run.kind) {
    case "adaptiveCareerIntake": {
      const payload = adaptiveCareerIntakePayloadSchema.parse(envelope.payload);
      return adaptiveCareerIntakeResponseSchema.parse(makeAdaptiveCareerIntake(payload));
    }
    case "cookedDiagnostic": {
      const payload = diagnosticPayloadSchema.parse(envelope.payload);
      return diagnosticResponseSchema.parse(makeDiagnostic(payload));
    }
    case "questPlan": {
      const payload = questPlanPayloadSchema.parse(envelope.payload);
      return questPlanResponseSchema.parse(makeQuestPlan(payload));
    }
    case "proofQualityCheck": {
      const payload = proofQualityPayloadSchema.parse(envelope.payload);
      return proofQualityResponseSchema.parse(checkProofQuality(payload));
    }
    case "progressSummary": {
      const payload = progressSummaryPayloadSchema.parse(envelope.payload);
      return progressSummaryResponseSchema.parse(summarizeProgress(payload));
    }
    case "careerBrief": {
      const payload = careerBriefPayloadSchema.parse(envelope.payload);
      return careerBriefResponseSchema.parse(makeCareerBrief(payload));
    }
    case "safeShareCardText": {
      const payload = safeShareCardTextPayloadSchema.parse(envelope.payload);
      return safeShareCardTextResponseSchema.parse(makeSafeShareCardText(payload));
    }
    case "opportunityRanking": {
      const payload = opportunityRankingPayloadSchema.parse(envelope.payload);
      return opportunityRankingResponseSchema.parse(rankOpportunities(payload));
    }
    case "agentScan": {
      const payload = agentScanPayloadSchema.parse(envelope.payload);
      return agentScanResponseSchema.parse(makeAgentScan(payload));
    }
  }
}

function findExternalActionViolation(value: unknown): string | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const violation = findExternalActionViolation(item);
      if (violation) {
        return violation;
      }
    }
    return null;
  }

  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, unknown>;
  if (record.externalActionTaken === true || record.executeExternalAction === true) {
    return "OpenLARP workflows may brief and rank actions, but they cannot execute external actions.";
  }

  if (record.approvalRequired === false) {
    return "External opportunities must remain user-approved actions.";
  }

  for (const child of Object.values(record)) {
    const violation = findExternalActionViolation(child);
    if (violation) {
      return violation;
    }
  }

  return null;
}
