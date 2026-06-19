import {
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
import { estimateProviderUsage, providerUsageMetadata } from "../../ai/src/costAccounting.js";
import {
  checkProofQuality,
  makeAgentScan,
  makeCareerBrief,
  makeDiagnostic,
  makeQuestPlan,
  makeSafeShareCardText,
  rankOpportunities,
  summarizeProgress
} from "../../ai/src/mockWorkflows.js";
import { validateEnvelopeSafety } from "../../ai/src/safety.js";
import { type CallableQuotaGuard } from "./callableQuotaGuard.js";
import { functionError, type OpenLARPFunctionError } from "./errors.js";

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
  providerRoute: RequestEnvelope["run"]["providerRoute"];
  liveModelCallsEnabled: false;
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

  const evaluatedAt = dependencies.now?.() ?? new Date();
  let aiConfig: OpenLARPAIBackendConfig;
  let budgetPolicy: OpenLARPAIProviderBudgetPolicy | null;
  try {
    aiConfig = dependencies.aiConfig ?? configFromEnvironment();
    budgetPolicy = dependencies.budgetPolicy ?? providerBudgetPolicyFromEnvironment();
  } catch (error) {
    return functionError("failed-precondition", "OpenLARP AI provider budget configuration is invalid.", {
      message: error instanceof Error ? error.message : "Unknown AI provider budget configuration error."
    });
  }
  const providerUsage = estimateProviderUsage({
    config: aiConfig,
    workflowKind: parsedEnvelope.data.run.kind,
    payload: parsedEnvelope.data.payload,
    budgetPolicy
  });
  if (providerUsage.liveModelCallsEnabled && !providerUsage.priceConfigured) {
    return functionError("failed-precondition", "Live OpenLARP AI requires provider token pricing and a daily budget.", {
      schemaVersion: 1,
      provider: providerUsage.provider,
      workflowKind: providerUsage.workflowKind,
      estimatedInputTokens: providerUsage.estimatedInputTokens,
      maxOutputTokens: providerUsage.maxOutputTokens
    });
  }
  if (providerUsage.liveModelCallsEnabled && providerUsage.budgetExceeded) {
    return functionError("resource-exhausted", "OpenLARP AI provider budget would be exceeded.", {
      schemaVersion: 1,
      provider: providerUsage.provider,
      workflowKind: providerUsage.workflowKind,
      estimatedCostMicros: providerUsage.estimatedCostMicros,
      dailyBudgetMicros: providerUsage.dailyBudgetMicros
    });
  }
  const quotaDecision = await dependencies.quotaGuard?.checkAndRecord({
    userID,
    callable: "runOpenLARPWorkflow",
    category: "aiWorkflow",
    units: 1,
    auditKey: parsedEnvelope.data.run.requestID,
    occurredAt: evaluatedAt,
    metadata: {
      providerRoute: parsedEnvelope.data.run.providerRoute,
      ...providerUsageMetadata(providerUsage)
    }
  });
  if (quotaDecision && !quotaDecision.ok) {
    return quotaDecision.error;
  }

  try {
    const result = dispatchDeterministicWorkflow(parsedEnvelope.data);
    return {
      ok: true,
      schemaVersion: 1,
      requestID: parsedEnvelope.data.run.requestID,
      kind: parsedEnvelope.data.run.kind,
      userID,
      evaluatedAt: evaluatedAt.toISOString(),
      providerRoute: parsedEnvelope.data.run.providerRoute,
      liveModelCallsEnabled: false,
      externalActionTaken: false,
      result
    };
  } catch (error) {
    return functionError("invalid-argument", "Workflow payload did not match its declared kind.", {
      message: error instanceof Error ? error.message : "Unknown workflow dispatch error"
    });
  }
}

function dispatchDeterministicWorkflow(envelope: RequestEnvelope): unknown {
  switch (envelope.run.kind) {
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
