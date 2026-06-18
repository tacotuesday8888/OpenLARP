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

export async function handleOpenLARPWorkflowRequest(
  request: OpenLARPWorkflowCallableRequest
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

  try {
    const result = dispatchDeterministicWorkflow(parsedEnvelope.data);
    return {
      ok: true,
      schemaVersion: 1,
      requestID: parsedEnvelope.data.run.requestID,
      kind: parsedEnvelope.data.run.kind,
      userID,
      evaluatedAt: new Date().toISOString(),
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
