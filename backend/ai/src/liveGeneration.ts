import { vertexAI } from "@genkit-ai/google-genai";
import { genkit } from "genkit";
import type { z } from "zod";
import type { OpenLARPAIBackendConfig } from "./config.js";

export type StructuredGenerationRequest = {
  systemInstruction: string;
  userPrompt: string;
  schema: z.ZodTypeAny;
  maxOutputTokens: number;
  signal: AbortSignal;
};

export type StructuredGenerationResponse = {
  output: unknown;
  inputTokens: number;
  outputTokens: number;
};

export type StructuredGenerator = {
  generate: (request: StructuredGenerationRequest) => Promise<StructuredGenerationResponse>;
};

type GenkitGenerateOptions = {
  model: unknown;
  system: string;
  prompt: string;
  output: { schema: z.ZodTypeAny };
  config: { temperature: number; maxOutputTokens: number };
  tools: [];
  maxTurns: 1;
  abortSignal: AbortSignal;
};

type GenkitGenerateResult = {
  output: unknown | null;
  usage?: {
    inputTokens?: number;
    outputTokens?: number;
  };
};

type GenkitGenerate = (options: GenkitGenerateOptions) => Promise<GenkitGenerateResult>;

export class LiveGenerationInvalidOutputError extends Error {}

export class LiveGenerationProviderError extends Error {
  constructor(message: string, readonly retryable: boolean) {
    super(message);
    this.name = "LiveGenerationProviderError";
  }
}

export function makeGenkitStructuredGenerator(
  generate: GenkitGenerate,
  options: { model: unknown }
): StructuredGenerator {
  return {
    async generate(request) {
      let response: GenkitGenerateResult;
      try {
        response = await generate({
          model: options.model,
          system: request.systemInstruction,
          prompt: request.userPrompt,
          output: { schema: request.schema },
          config: {
            temperature: 0.2,
            maxOutputTokens: request.maxOutputTokens
          },
          tools: [],
          maxTurns: 1,
          abortSignal: request.signal
        });
      } catch (error) {
        if (request.signal.aborted) {
          throw request.signal.reason;
        }
        throw new LiveGenerationProviderError(
          error instanceof Error ? error.name : "VertexGenerationError",
          isRetryableProviderError(error)
        );
      }

      if (response.output === null || response.output === undefined) {
        throw new LiveGenerationInvalidOutputError("Gemini returned no structured output.");
      }

      return {
        output: response.output,
        inputTokens: safeTokenCount(response.usage?.inputTokens),
        outputTokens: safeTokenCount(response.usage?.outputTokens)
      };
    }
  };
}

export function createVertexStructuredGenerator(config: OpenLARPAIBackendConfig): StructuredGenerator {
  const ai = genkit({
    plugins: [vertexAI({ location: config.vertexLocation })]
  });
  const model = vertexAI.model(config.modelId);
  return makeGenkitStructuredGenerator(async ({ model: _model, ...options }) => {
    const response = await ai.generate({ ...options, model });
    return {
      output: response.output,
      usage: {
        inputTokens: response.usage.inputTokens ?? 0,
        outputTokens: response.usage.outputTokens ?? 0
      }
    };
  }, { model });
}

function safeTokenCount(value: number | undefined): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : 0;
}

function isRetryableProviderError(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }
  const candidate = error as { status?: unknown; code?: unknown };
  const value = candidate.status ?? candidate.code;
  return value === 408 || value === 429 ||
    (typeof value === "number" && value >= 500 && value <= 599) ||
    value === "UNAVAILABLE" || value === "RESOURCE_EXHAUSTED";
}
