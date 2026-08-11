import type { OpenLARPAIBackendConfig, OpenLARPAIProviderBudgetPolicy } from "./config.js";
import type { WorkflowKind } from "./contracts.js";

export type OpenLARPAIProviderUsageEstimate = {
  schemaVersion: 1;
  provider: OpenLARPAIBackendConfig["provider"];
  workflowKind: WorkflowKind;
  liveModelCallsEnabled: boolean;
  estimatedInputTokens: number;
  maxOutputTokens: number;
  estimatedTotalTokens: number;
  priceConfigured: boolean;
  estimatedCostMicros: number | null;
  dailyBudgetMicros: number | null;
  budgetExceeded: boolean;
};

export type OpenLARPAIProviderUsageInput = {
  config: OpenLARPAIBackendConfig;
  workflowKind: WorkflowKind;
  payload: unknown;
  budgetPolicy?: OpenLARPAIProviderBudgetPolicy | null;
};

export function estimateProviderUsage(input: OpenLARPAIProviderUsageInput): OpenLARPAIProviderUsageEstimate {
  const estimatedInputTokens = estimateTokensFromJSON(input.payload);
  const maxOutputTokens = input.config.maxOutputTokens;
  const estimatedTotalTokens = estimatedInputTokens + maxOutputTokens;
  const estimatedCostMicros = input.budgetPolicy
    ? providerCostMicros({
        inputTokens: estimatedInputTokens,
        outputTokens: maxOutputTokens,
        budgetPolicy: input.budgetPolicy
      })
    : null;

  return {
    schemaVersion: 1,
    provider: input.config.provider,
    workflowKind: input.workflowKind,
    liveModelCallsEnabled: input.config.enableLiveGeneration,
    estimatedInputTokens,
    maxOutputTokens,
    estimatedTotalTokens,
    priceConfigured: input.budgetPolicy !== undefined && input.budgetPolicy !== null,
    estimatedCostMicros,
    dailyBudgetMicros: input.budgetPolicy?.dailyBudgetMicros ?? null,
    budgetExceeded: estimatedCostMicros !== null && estimatedCostMicros > (input.budgetPolicy?.dailyBudgetMicros ?? Infinity)
  };
}

export function providerUsageMetadata(
  estimate: OpenLARPAIProviderUsageEstimate
): Record<string, string | number | boolean> {
  return {
    provider: estimate.provider,
    workflowKind: estimate.workflowKind,
    liveModelCallsEnabled: estimate.liveModelCallsEnabled,
    estimatedInputTokens: estimate.estimatedInputTokens,
    maxOutputTokens: estimate.maxOutputTokens,
    estimatedTotalTokens: estimate.estimatedTotalTokens,
    priceConfigured: estimate.priceConfigured,
    estimatedCostMicros: estimate.estimatedCostMicros ?? 0,
    budgetConfigured: estimate.dailyBudgetMicros !== null,
    budgetExceeded: estimate.budgetExceeded
  };
}

function estimateTokensFromJSON(value: unknown): number {
  const serialized = JSON.stringify(value) ?? "";
  if (serialized.length === 0) {
    return 1;
  }

  // Conservative enough for budget gating without persisting prompts or proof text.
  return Math.max(1, Math.ceil(serialized.length / 4));
}

export function providerCostMicros(input: {
  inputTokens: number;
  outputTokens: number;
  budgetPolicy: OpenLARPAIProviderBudgetPolicy;
}): number {
  if (!isNonnegativeSafeInteger(input.inputTokens) || !isNonnegativeSafeInteger(input.outputTokens)) {
    throw new Error("Provider token counts must be nonnegative safe integers.");
  }
  if (!isNonnegativeSafeInteger(input.budgetPolicy.inputTokenMicrosPerThousand)
    || !isNonnegativeSafeInteger(input.budgetPolicy.outputTokenMicrosPerThousand)) {
    throw new Error("Provider token pricing must use nonnegative safe integer micros.");
  }
  const inputMicros = Math.ceil(input.inputTokens * input.budgetPolicy.inputTokenMicrosPerThousand / 1000);
  const outputMicros = Math.ceil(input.outputTokens * input.budgetPolicy.outputTokenMicrosPerThousand / 1000);
  const total = inputMicros + outputMicros;
  if (!Number.isSafeInteger(total)) {
    throw new Error("Provider cost exceeded the safe integer range.");
  }
  return total;
}

function isNonnegativeSafeInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}
