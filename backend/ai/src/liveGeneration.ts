import { GoogleGenAI, type GenerateContentParameters, type GenerateContentResponse } from "@google/genai";
import { GoogleAuth } from "google-auth-library";
import { z } from "zod";
import type { OpenLARPAIBackendConfig } from "./config.js";

export type StructuredGenerationRequest = {
  systemInstruction: string;
  userPrompt: string;
  schema: z.ZodType;
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

type VertexGenerate = (request: GenerateContentParameters) => Promise<
  Pick<GenerateContentResponse, "candidates" | "usageMetadata">
>;

export class LiveGenerationInvalidOutputError extends Error {}

export class LiveGenerationProviderError extends Error {
  constructor(message: string, readonly retryable: boolean) {
    super(message);
    this.name = "LiveGenerationProviderError";
  }
}

export function makeVertexStructuredGenerator(generate: VertexGenerate, model: string): StructuredGenerator {
  return {
    async generate(request) {
      let response: Awaited<ReturnType<VertexGenerate>>;
      try {
        request.signal.throwIfAborted();
        response = await generate({
          model,
          contents: [{ role: "user", parts: [{ text: request.userPrompt }] }],
          config: {
            systemInstruction: request.systemInstruction,
            temperature: 0.2,
            maxOutputTokens: request.maxOutputTokens,
            candidateCount: 1,
            automaticContinuation: false,
            responseMimeType: "application/json",
            responseJsonSchema: vertexResponseSchema(request.schema),
            abortSignal: request.signal,
            httpOptions: { retryOptions: { attempts: 1 } }
          }
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

      const candidate = response.candidates?.[0];
      const answer = candidate?.content?.parts?.filter((part) => !part.thought);
      if (candidate?.finishReason !== "STOP" || !answer?.length ||
          !answer.every((part) => typeof part.text === "string")) {
        throw new LiveGenerationInvalidOutputError("Gemini returned no completed text response.");
      }
      let output: unknown;
      try {
        output = JSON.parse(answer.map((part) => part.text).join(""));
      } catch {
        throw new LiveGenerationInvalidOutputError("Gemini returned invalid structured output.");
      }
      const usage = response.usageMetadata;
      return {
        output,
        inputTokens: safeTokenCount(usage?.promptTokenCount),
        outputTokens: safeTokenCount(usage?.candidatesTokenCount) + safeTokenCount(usage?.thoughtsTokenCount)
      };
    }
  };
}

export function createVertexStructuredGenerator(config: OpenLARPAIBackendConfig): StructuredGenerator {
  const auth = new GoogleAuth();
  let client: GoogleGenAI | undefined;
  return makeVertexStructuredGenerator(async (request) => {
    if (!client) {
      const project = await auth.getProjectId();
      client = new GoogleGenAI({ vertexai: true, project, location: config.vertexLocation, apiVersion: "v1" });
    }
    request.config?.abortSignal?.throwIfAborted();
    return client.models.generateContent(request);
  }, config.modelId);
}

function vertexResponseSchema(schema: z.ZodType) {
  // Vertex guides generation with a subset of JSON Schema. The full Zod
  // schema and workflow-specific checks still validate the returned object.
  const result = z.toJSONSchema(schema, {
    io: "input",
    override: ({ jsonSchema }) => {
      if (typeof jsonSchema.const === "string" || typeof jsonSchema.const === "number") {
        jsonSchema.enum = [jsonSchema.const];
      }
      delete jsonSchema.const;
      delete jsonSchema.default;
      delete jsonSchema.pattern;
      delete jsonSchema.minLength;
      delete jsonSchema.maxLength;
    }
  });
  delete result.$schema;
  return result;
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
