export const DEFAULT_GEMINI_MODEL_ID = "gemini-3.1-flash-lite";

export type OpenLARPAIBackendConfig = {
  modelId: string;
  provider: "firebase-ai-logic" | "vertex-ai" | "local-mock";
  enableLiveGeneration: boolean;
  maxOutputTokens: number;
};

export function configFromEnvironment(env: NodeJS.ProcessEnv = process.env): OpenLARPAIBackendConfig {
  return {
    modelId: env.OPENLARP_GEMINI_MODEL_ID ?? DEFAULT_GEMINI_MODEL_ID,
    provider: (env.OPENLARP_AI_PROVIDER as OpenLARPAIBackendConfig["provider"] | undefined) ?? "firebase-ai-logic",
    enableLiveGeneration: env.OPENLARP_ENABLE_LIVE_AI === "true",
    maxOutputTokens: Number.parseInt(env.OPENLARP_AI_MAX_OUTPUT_TOKENS ?? "1200", 10)
  };
}
