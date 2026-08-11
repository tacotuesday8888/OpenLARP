import type { z } from "zod";
import {
  adaptiveCareerIntakePayloadSchema,
  adaptiveCareerIntakeResponseSchema,
  contextualAssistantPayloadSchema,
  contextualAssistantResponseSchema,
  diagnosticPayloadSchema,
  diagnosticResponseSchema,
  executionMetadataSchema,
  missionBriefPayloadSchema,
  missionBriefResponseSchema,
  progressSummaryPayloadSchema,
  progressSummaryResponseSchema,
  proofCoachingResponseSchema,
  proofQualityPayloadSchema,
  proofQualityResponseSchema,
  questPlanPayloadSchema,
  questPlanResponseSchema,
  type RequestEnvelope
} from "./contracts.js";
import {
  LiveGenerationInvalidOutputError,
  LiveGenerationProviderError,
  type StructuredGenerationResponse,
  type StructuredGenerator
} from "./liveGeneration.js";
import {
  checkProofQuality,
  answerContextualQuestion,
  makeAdaptiveCareerIntake,
  makeDiagnostic,
  makeMissionBrief,
  makeQuestPlan,
  summarizeProgress
} from "./mockWorkflows.js";
import { validateGeneratedWorkflowResult } from "./postValidation.js";
import { buildLiveWorkflowPrompt } from "./prompts.js";

export type LiveWorkflowExecutionPolicy = {
  enabled: boolean;
  policyRevision: string;
  timeoutMs: number;
  maxOutputTokens: number;
};

export type WorkflowExecutionResult = {
  result: unknown;
  execution: z.infer<typeof executionMetadataSchema>;
};

export class WorkflowExecutionCancelledError extends Error {
  constructor() {
    super("Workflow execution was cancelled by the caller.");
    this.name = "WorkflowExecutionCancelledError";
  }
}

class WorkflowExecutionTimeoutError extends Error {}

export async function executeWorkflow(input: {
  envelope: RequestEnvelope;
  policy: LiveWorkflowExecutionPolicy;
  generator: StructuredGenerator;
  signal?: AbortSignal;
}): Promise<WorkflowExecutionResult> {
  const deterministicResult = deterministicLiveWorkflow(input.envelope);
  if (!input.policy.enabled) {
    return fallbackResult(input.policy, deterministicResult, "disabled", null);
  }
  if (input.signal?.aborted) {
    throw new WorkflowExecutionCancelledError();
  }

  const prompt = buildLiveWorkflowPrompt(input.envelope);
  const schema = responseSchemaForLiveWorkflow(input.envelope.run.kind);
  const startedAt = Date.now();
  let generation: StructuredGenerationResponse | null = null;

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      generation = await generateWithTimeout({
        generator: input.generator,
        prompt,
        schema,
        maxOutputTokens: input.policy.maxOutputTokens,
        timeoutMs: input.policy.timeoutMs,
        ...(input.signal ? { callerSignal: input.signal } : {})
      });
      break;
    } catch (error) {
      if (error instanceof WorkflowExecutionCancelledError) {
        throw error;
      }
      if (error instanceof WorkflowExecutionTimeoutError) {
        return fallbackResult(input.policy, deterministicResult, "timeout", prompt.promptVersion);
      }
      if (error instanceof LiveGenerationInvalidOutputError) {
        return fallbackResult(input.policy, deterministicResult, "invalidOutput", prompt.promptVersion);
      }
      if (error instanceof LiveGenerationProviderError && error.retryable && attempt === 0) {
        continue;
      }
      return fallbackResult(input.policy, deterministicResult, "provider", prompt.promptVersion);
    }
  }

  if (!generation) {
    return fallbackResult(input.policy, deterministicResult, "provider", prompt.promptVersion);
  }
  const validation = validateGeneratedWorkflowResult(
    input.envelope.run.kind,
    input.envelope.payload,
    generation.output
  );
  if (!validation.ok) {
    return fallbackResult(
      input.policy,
      deterministicResult,
      validation.reason,
      prompt.promptVersion,
      generation,
      startedAt
    );
  }

  return {
    result: validation.result,
    execution: executionMetadataSchema.parse({
      schemaVersion: 1,
      liveModelCallsEnabled: true,
      liveModelUsed: true,
      usedFallback: false,
      fallbackReason: null,
      promptVersion: prompt.promptVersion,
      policyRevision: input.policy.policyRevision,
      usage: {
        inputTokens: generation.inputTokens,
        outputTokens: generation.outputTokens,
        latencyBucket: latencyBucket(Date.now() - startedAt)
      }
    })
  };
}

function deterministicLiveWorkflow(envelope: RequestEnvelope): unknown {
  switch (envelope.run.kind) {
    case "adaptiveCareerIntake":
      return adaptiveCareerIntakeResponseSchema.parse(
        makeAdaptiveCareerIntake(adaptiveCareerIntakePayloadSchema.parse(envelope.payload))
      );
    case "cookedDiagnostic":
      return diagnosticResponseSchema.parse(makeDiagnostic(diagnosticPayloadSchema.parse(envelope.payload)));
    case "missionBrief":
      return missionBriefResponseSchema.parse(makeMissionBrief(missionBriefPayloadSchema.parse(envelope.payload)));
    case "questPlan":
      return questPlanResponseSchema.parse(makeQuestPlan(questPlanPayloadSchema.parse(envelope.payload)));
    case "proofQualityCheck":
      return proofQualityResponseSchema.parse(checkProofQuality(proofQualityPayloadSchema.parse(envelope.payload)));
    case "progressSummary":
      return progressSummaryResponseSchema.parse(summarizeProgress(progressSummaryPayloadSchema.parse(envelope.payload)));
    case "contextualAssistant":
      return contextualAssistantResponseSchema.parse(
        answerContextualQuestion(contextualAssistantPayloadSchema.parse(envelope.payload))
      );
    default:
      throw new Error(`Workflow ${envelope.run.kind} does not have a live execution path.`);
  }
}

function responseSchemaForLiveWorkflow(kind: RequestEnvelope["run"]["kind"]): z.ZodTypeAny {
  switch (kind) {
    case "adaptiveCareerIntake": return adaptiveCareerIntakeResponseSchema;
    case "cookedDiagnostic": return diagnosticResponseSchema;
    case "missionBrief": return missionBriefResponseSchema;
    case "questPlan": return questPlanResponseSchema;
    case "proofQualityCheck": return proofCoachingResponseSchema;
    case "progressSummary": return progressSummaryResponseSchema;
    case "contextualAssistant": return contextualAssistantResponseSchema;
    default: throw new Error(`Workflow ${kind} does not have a live response schema.`);
  }
}

async function generateWithTimeout(input: {
  generator: StructuredGenerator;
  prompt: ReturnType<typeof buildLiveWorkflowPrompt>;
  schema: z.ZodTypeAny;
  maxOutputTokens: number;
  timeoutMs: number;
  callerSignal?: AbortSignal;
}): Promise<StructuredGenerationResponse> {
  const controller = new AbortController();
  let timedOut = false;
  let cancelled = false;
  let rejectCancellation: (reason: WorkflowExecutionCancelledError) => void = () => {};
  const cancellation = new Promise<never>((_, reject) => {
    rejectCancellation = reject;
  });
  const cancel = () => {
    cancelled = true;
    const error = new WorkflowExecutionCancelledError();
    controller.abort(error);
    rejectCancellation(error);
  };
  input.callerSignal?.addEventListener("abort", cancel, { once: true });
  if (input.callerSignal?.aborted) {
    cancel();
  }

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      timedOut = true;
      const error = new WorkflowExecutionTimeoutError("Live generation timed out.");
      controller.abort(error);
      reject(error);
    }, input.timeoutMs);
  });
  try {
    return await Promise.race([
      input.generator.generate({
        systemInstruction: input.prompt.systemInstruction,
        userPrompt: input.prompt.userPrompt,
        schema: input.schema,
        maxOutputTokens: input.maxOutputTokens,
        signal: controller.signal
      }),
      timeout,
      cancellation
    ]);
  } catch (error) {
    if (cancelled || input.callerSignal?.aborted) {
      throw new WorkflowExecutionCancelledError();
    }
    if (timedOut) {
      throw new WorkflowExecutionTimeoutError("Live generation timed out.");
    }
    throw error;
  } finally {
    if (timer) clearTimeout(timer);
    input.callerSignal?.removeEventListener("abort", cancel);
  }
}

function fallbackResult(
  policy: LiveWorkflowExecutionPolicy,
  result: unknown,
  fallbackReason: "disabled" | "timeout" | "provider" | "invalidOutput" | "unsafeOutput",
  promptVersion: string | null,
  usage?: StructuredGenerationResponse,
  startedAt?: number
): WorkflowExecutionResult {
  return {
    result,
    execution: executionMetadataSchema.parse({
      schemaVersion: 1,
      liveModelCallsEnabled: policy.enabled,
      liveModelUsed: false,
      usedFallback: true,
      fallbackReason,
      promptVersion,
      policyRevision: policy.policyRevision,
      usage: {
        inputTokens: usage?.inputTokens ?? 0,
        outputTokens: usage?.outputTokens ?? 0,
        latencyBucket: startedAt === undefined ? "notRun" : latencyBucket(Date.now() - startedAt)
      }
    })
  };
}

function latencyBucket(milliseconds: number) {
  if (milliseconds < 1_000) return "under1s" as const;
  if (milliseconds < 5_000) return "under5s" as const;
  if (milliseconds < 15_000) return "under15s" as const;
  return "over15s" as const;
}
