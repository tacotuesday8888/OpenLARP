export const DEFAULT_GEMINI_MODEL_ID = "gemini-3.1-flash-lite";

const OPENLARP_AI_PROVIDERS = ["firebase-ai-logic", "vertex-ai", "local-mock"] as const;
const DEFAULT_MAX_OUTPUT_TOKENS = 1200;

export type OpenLARPAIBackendConfig = {
  modelId: string;
  provider: typeof OPENLARP_AI_PROVIDERS[number];
  enableLiveGeneration: boolean;
  maxOutputTokens: number;
};

export type OpenLARPAIProviderBudgetPolicy = {
  inputTokenMicrosPerThousand: number;
  outputTokenMicrosPerThousand: number;
  dailyBudgetMicros: number;
};

export function configFromEnvironment(env: NodeJS.ProcessEnv = process.env): OpenLARPAIBackendConfig {
  const provider = parseProvider(env.OPENLARP_AI_PROVIDER);
  const maxOutputTokens = parseMaxOutputTokens(env.OPENLARP_AI_MAX_OUTPUT_TOKENS);

  return {
    modelId: env.OPENLARP_GEMINI_MODEL_ID ?? DEFAULT_GEMINI_MODEL_ID,
    provider,
    enableLiveGeneration: env.OPENLARP_ENABLE_LIVE_AI === "true",
    maxOutputTokens
  };
}

export function providerBudgetPolicyFromEnvironment(
  env: NodeJS.ProcessEnv = process.env
): OpenLARPAIProviderBudgetPolicy | null {
  const input = env.OPENLARP_AI_INPUT_TOKEN_MICROS_PER_1K;
  const output = env.OPENLARP_AI_OUTPUT_TOKEN_MICROS_PER_1K;
  const dailyBudget = env.OPENLARP_AI_DAILY_BUDGET_MICROS;

  if (!input && !output && !dailyBudget) {
    return null;
  }
  if (!input || !output || !dailyBudget) {
    throw new Error("AI provider budget config requires input, output, and daily budget micros.");
  }

  return {
    inputTokenMicrosPerThousand: parseNonnegativeInteger(input, "OPENLARP_AI_INPUT_TOKEN_MICROS_PER_1K"),
    outputTokenMicrosPerThousand: parseNonnegativeInteger(output, "OPENLARP_AI_OUTPUT_TOKEN_MICROS_PER_1K"),
    dailyBudgetMicros: parsePositiveInteger(dailyBudget, "OPENLARP_AI_DAILY_BUDGET_MICROS")
  };
}

function parseProvider(value: string | undefined): OpenLARPAIBackendConfig["provider"] {
  if (value === undefined || value.length === 0) {
    return "firebase-ai-logic";
  }

  if (OPENLARP_AI_PROVIDERS.includes(value as OpenLARPAIBackendConfig["provider"])) {
    return value as OpenLARPAIBackendConfig["provider"];
  }

  throw new Error(`Unsupported OPENLARP_AI_PROVIDER: ${value}`);
}

function parseMaxOutputTokens(value: string | undefined): number {
  if (value === undefined || value.length === 0) {
    return DEFAULT_MAX_OUTPUT_TOKENS;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 128 || parsed > 8192) {
    throw new Error("OPENLARP_AI_MAX_OUTPUT_TOKENS must be an integer between 128 and 8192.");
  }

  return parsed;
}

function parseNonnegativeInteger(value: string, name: string): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0 || !Number.isInteger(parsed)) {
    throw new Error(`${name} must be a nonnegative integer.`);
  }
  return parsed;
}

function parsePositiveInteger(value: string, name: string): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0 || !Number.isInteger(parsed)) {
    throw new Error(`${name} must be a positive integer.`);
  }
  return parsed;
}
