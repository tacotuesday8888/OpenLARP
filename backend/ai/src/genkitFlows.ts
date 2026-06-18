import { genkit } from "genkit";
import { googleAI } from "@genkit-ai/google-genai";
import { configFromEnvironment } from "./config.js";
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
  safeShareCardTextPayloadSchema,
  safeShareCardTextResponseSchema
} from "./contracts.js";
import {
  checkProofQuality,
  makeAgentScan,
  makeCareerBrief,
  makeDiagnostic,
  makeQuestPlan,
  makeSafeShareCardText,
  rankOpportunities,
  summarizeProgress
} from "./mockWorkflows.js";

export function createOpenLARPGenkit() {
  const config = configFromEnvironment();
  return genkit({
    plugins: [googleAI()],
    model: googleAI.model(config.modelId)
  });
}

export function defineOpenLARPFlows(ai = createOpenLARPGenkit()) {
  const cookedDiagnostic = ai.defineFlow(
    {
      name: "openlarp.v0.cookedDiagnostic",
      inputSchema: diagnosticPayloadSchema,
      outputSchema: diagnosticResponseSchema
    },
    async (payload) => makeDiagnostic(payload)
  );

  const questPlan = ai.defineFlow(
    {
      name: "openlarp.v0.questPlan",
      inputSchema: questPlanPayloadSchema,
      outputSchema: questPlanResponseSchema
    },
    async (payload) => makeQuestPlan(payload)
  );

  const proofQualityCheck = ai.defineFlow(
    {
      name: "openlarp.v0.proofQualityCheck",
      inputSchema: proofQualityPayloadSchema,
      outputSchema: proofQualityResponseSchema
    },
    async (payload) => checkProofQuality(payload)
  );

  const progressSummary = ai.defineFlow(
    {
      name: "openlarp.v0.progressSummary",
      inputSchema: progressSummaryPayloadSchema,
      outputSchema: progressSummaryResponseSchema
    },
    async (payload) => summarizeProgress(payload)
  );

  const careerBrief = ai.defineFlow(
    {
      name: "openlarp.v0.careerBrief",
      inputSchema: careerBriefPayloadSchema,
      outputSchema: careerBriefResponseSchema
    },
    async (payload) => makeCareerBrief(payload)
  );

  const safeShareCardText = ai.defineFlow(
    {
      name: "openlarp.v0.safeShareCardText",
      inputSchema: safeShareCardTextPayloadSchema,
      outputSchema: safeShareCardTextResponseSchema
    },
    async (payload) => makeSafeShareCardText(payload)
  );

  const opportunityRanking = ai.defineFlow(
    {
      name: "openlarp.v1.opportunityRanking",
      inputSchema: opportunityRankingPayloadSchema,
      outputSchema: opportunityRankingResponseSchema
    },
    async (payload) => rankOpportunities(payload)
  );

  const agentScan = ai.defineFlow(
    {
      name: "openlarp.v1.agentScan",
      inputSchema: agentScanPayloadSchema,
      outputSchema: agentScanResponseSchema
    },
    async (payload) => makeAgentScan(payload)
  );

  return {
    cookedDiagnostic,
    questPlan,
    proofQualityCheck,
    progressSummary,
    careerBrief,
    safeShareCardText,
    opportunityRanking,
    agentScan
  };
}
