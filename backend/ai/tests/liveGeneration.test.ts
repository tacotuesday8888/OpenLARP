import { FinishReason, GoogleGenAI, type GenerateContentParameters, type GenerateContentResponse } from "@google/genai";
import { describe, expect, it, vi } from "vitest";
import {
  adaptiveCareerIntakeResponseSchema,
  contextualAssistantResponseSchema,
  diagnosticResponseSchema,
  missionBriefResponseSchema,
  progressSummaryResponseSchema,
  proofCoachingResponseSchema,
  questPlanResponseSchema
} from "../src/contracts.js";
import {
  LiveGenerationInvalidOutputError,
  makeVertexStructuredGenerator,
  type StructuredGenerationRequest
} from "../src/liveGeneration.js";

const model = "private-model-ref";
const request: StructuredGenerationRequest = {
  systemInstruction: "system",
  userPrompt: "user",
  schema: diagnosticResponseSchema,
  maxOutputTokens: 900,
  signal: new AbortController().signal
};

describe("Vertex structured generation", () => {
  it("sends the JSON schema to the configured Vertex endpoint through the SDK", async () => {
    const fetch = vi.fn(async (_url: string | URL | Request, _init?: RequestInit) =>
      Response.json({ candidates: [{ finishReason: "STOP", content: { parts: [{ text: '{"score":1}' }] } }] })
    );
    const client = new GoogleGenAI({
      vertexai: true, project: "offline-test-project", location: "global", apiVersion: "v1",
      apiKey: "offline-test-fixture", httpOptions: { fetch }
    });
    const generator = makeVertexStructuredGenerator((options) => client.models.generateContent(options), model);

    await expect(generator.generate(request)).resolves.toMatchObject({ output: { score: 1 } });

    expect(fetch).toHaveBeenCalledTimes(1);
    const [url, options] = fetch.mock.calls[0]!;
    expect(String(url)).toBe("https://aiplatform.googleapis.com/v1/projects/offline-test-project/locations/global/publishers/google/models/private-model-ref:generateContent");
    const body = JSON.parse(String(options?.body));
    expect(body.generationConfig.responseJsonSchema.required).toContain("score");
    expect(body.generationConfig.responseMimeType).toBe("application/json");
    expect(body.generationConfig.maxOutputTokens).toBe(request.maxOutputTokens);
    expect(body.systemInstruction.parts).toEqual([{ text: "system" }]);
    expect(body.tools).toBeUndefined();
  });

  it("sends one bounded text-only request and counts answer and thought tokens", async () => {
    const generate = vi.fn(async (_options: GenerateContentParameters) => ({
      candidates: [{
        finishReason: FinishReason.STOP,
        content: { parts: [{ thought: true, text: "private reasoning" }, { text: '{"score":1}' }] }
      }],
      usageMetadata: { promptTokenCount: 12, candidatesTokenCount: 8, thoughtsTokenCount: 3 }
    }));

    const response = await makeVertexStructuredGenerator(generate, model).generate(request);

    expect(response).toEqual({ output: { score: 1 }, inputTokens: 12, outputTokens: 11 });
    expect(generate).toHaveBeenCalledExactlyOnceWith({
      model,
      contents: [{ role: "user", parts: [{ text: "user" }] }],
      config: {
        systemInstruction: "system",
        temperature: 0.2,
        maxOutputTokens: 900,
        candidateCount: 1,
        automaticContinuation: false,
        responseMimeType: "application/json",
        responseJsonSchema: expect.objectContaining({
          type: "object",
          properties: expect.objectContaining({ score: { type: "integer", minimum: 0, maximum: 100 } }),
          required: expect.arrayContaining(["score", "firstAction"])
        }),
        abortSignal: request.signal,
        httpOptions: { retryOptions: { attempts: 1 } }
      }
    });
  });

  it.each([
    adaptiveCareerIntakeResponseSchema, missionBriefResponseSchema, questPlanResponseSchema,
    proofCoachingResponseSchema, progressSummaryResponseSchema, contextualAssistantResponseSchema
  ])("exports the workflow response shape using Vertex-supported schema keywords", async (schema) => {
    const generate = vi.fn(async (_options: GenerateContentParameters) => ({
      candidates: [{ finishReason: FinishReason.STOP, content: { parts: [{ text: "{}" }] } }]
    }));
    await makeVertexStructuredGenerator(generate, model).generate({ ...request, schema });
    const json = generate.mock.calls[0]?.[0].config?.responseJsonSchema;
    expect(json).toMatchObject({ type: "object", properties: expect.any(Object), required: expect.any(Array) });
    expect(JSON.stringify(json)).not.toMatch(/"(?:\$schema|default|minLength|maxLength|const|pattern)"\s*:/);
    if (schema === missionBriefResponseSchema) {
      expect(json).toMatchObject({
        properties: { sprint: { properties: { dayCount: { enum: [14] }, chapterCount: { enum: [2] } } } }
      });
    }
    if (schema === proofCoachingResponseSchema) {
      expect(json).toHaveProperty("additionalProperties", false);
      expect(schema.safeParse({ reason: "x".repeat(501), improvement: "y" }).success).toBe(false);
    }
  });

  it.each<Pick<GenerateContentResponse, "candidates">>([
    {},
    { candidates: [{ finishReason: FinishReason.SAFETY }] },
    { candidates: [{ finishReason: FinishReason.MAX_TOKENS, content: { parts: [{ text: "{}" }] } }] },
    { candidates: [{ finishReason: FinishReason.STOP, content: { parts: [{ text: "invalid JSON" }] } }] },
    { candidates: [{ finishReason: FinishReason.STOP, content: { parts: [{ functionCall: { name: "unused" } }] } }] }
  ])("rejects missing, blocked, partial, non-JSON, or non-text output", async (response) => {
    await expect(makeVertexStructuredGenerator(async () => response, model).generate(request))
      .rejects.toBeInstanceOf(LiveGenerationInvalidOutputError);
  });

  it("preserves cancellation and transient provider failure classification", async () => {
    const generate = vi.fn().mockRejectedValue(Object.assign(new Error("private provider detail"), { status: 429 }));
    const generator = makeVertexStructuredGenerator(generate, model);
    const controller = new AbortController();
    controller.abort(new Error("cancelled"));
    await expect(generator.generate({ ...request, signal: controller.signal })).rejects.toBe(controller.signal.reason);
    expect(generate).not.toHaveBeenCalled();
    await expect(generator.generate(request)).rejects.toMatchObject({ retryable: true, message: "Error" });
  });
});
