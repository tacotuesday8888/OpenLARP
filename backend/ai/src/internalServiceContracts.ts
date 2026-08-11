import { z } from "zod";
import {
  adaptiveCareerIntakePayloadSchema,
  adaptiveCareerIntakeResponseSchema,
  diagnosticPayloadSchema,
  diagnosticResponseSchema,
  missionBriefPayloadSchema,
  missionBriefResponseSchema,
  executionMetadataSchema,
  progressSummaryPayloadSchema,
  progressSummaryResponseSchema,
  proofQualityPayloadSchema,
  proofQualityResponseSchema,
  questPlanPayloadSchema,
  questPlanResponseSchema,
  requestEnvelopeSchema
} from "./contracts.js";

export const internalWorkflowRequestSchema = z.object({
  schemaVersion: z.literal(1),
  envelope: requestEnvelopeSchema.refine(
    (envelope) => envelope.run.providerRoute === "cloudRunGenkit",
    { message: "Internal AI service requests require the Cloud Run provider route." }
  ),
  policy: z.object({
    enabled: z.boolean(),
    policyRevision: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/),
    timeoutMs: z.number().int().min(1_000).max(45_000),
    maxOutputTokens: z.number().int().min(128).max(8_192)
  })
}).superRefine((request, context) => {
  const schema = livePayloadSchema(request.envelope.run.kind);
  if (!schema || !schema.safeParse(request.envelope.payload).success) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["envelope", "payload"],
      message: "Payload did not match an enabled live workflow."
    });
  }
});

export const internalWorkflowSuccessSchema = z.object({
  ok: z.literal(true),
  schemaVersion: z.literal(1),
  requestID: z.string().uuid(),
  kind: z.string().min(1).max(80),
  externalActionTaken: z.literal(false),
  result: z.unknown(),
  execution: executionMetadataSchema
}).superRefine((response, context) => {
  const schema = liveResultSchema(response.kind);
  if (!schema || !schema.safeParse(response.result).success) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["result"],
      message: "Result did not match the declared live workflow."
    });
  }
});

export type InternalWorkflowRequest = z.infer<typeof internalWorkflowRequestSchema>;
export type InternalWorkflowSuccess = z.infer<typeof internalWorkflowSuccessSchema>;

function livePayloadSchema(kind: string): z.ZodTypeAny | null {
  switch (kind) {
    case "adaptiveCareerIntake": return adaptiveCareerIntakePayloadSchema;
    case "cookedDiagnostic": return diagnosticPayloadSchema;
    case "missionBrief": return missionBriefPayloadSchema;
    case "questPlan": return questPlanPayloadSchema;
    case "proofQualityCheck": return proofQualityPayloadSchema;
    case "progressSummary": return progressSummaryPayloadSchema;
    default: return null;
  }
}

function liveResultSchema(kind: string): z.ZodTypeAny | null {
  switch (kind) {
    case "adaptiveCareerIntake": return adaptiveCareerIntakeResponseSchema;
    case "cookedDiagnostic": return diagnosticResponseSchema;
    case "missionBrief": return missionBriefResponseSchema;
    case "questPlan": return questPlanResponseSchema;
    case "proofQualityCheck": return proofQualityResponseSchema;
    case "progressSummary": return progressSummaryResponseSchema;
    default: return null;
  }
}
