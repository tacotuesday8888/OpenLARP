import { describe, expect, it, vi } from "vitest";
import { diagnosticResponseSchema } from "../src/contracts.js";
import {
  LiveGenerationInvalidOutputError,
  makeGenkitStructuredGenerator
} from "../src/liveGeneration.js";

describe("makeGenkitStructuredGenerator", () => {
  it("uses one bounded structured request with no tools", async () => {
    const generate = vi.fn(async () => ({
      output: { score: 1 },
      usage: { inputTokens: 12, outputTokens: 8 }
    }));
    const generator = makeGenkitStructuredGenerator(generate, { model: "private-model-ref" });
    const controller = new AbortController();

    const response = await generator.generate({
      systemInstruction: "system",
      userPrompt: "user",
      schema: diagnosticResponseSchema,
      maxOutputTokens: 900,
      signal: controller.signal
    });

    expect(response).toEqual({ output: { score: 1 }, inputTokens: 12, outputTokens: 8 });
    expect(generate).toHaveBeenCalledWith({
      model: "private-model-ref",
      system: "system",
      prompt: "user",
      output: { schema: diagnosticResponseSchema },
      config: { temperature: 0.2, maxOutputTokens: 900 },
      tools: [],
      maxTurns: 1,
      abortSignal: controller.signal
    });
  });

  it("rejects a missing structured output", async () => {
    const generator = makeGenkitStructuredGenerator(
      async () => ({ output: null, usage: {} }),
      { model: "private-model-ref" }
    );

    await expect(generator.generate({
      systemInstruction: "system",
      userPrompt: "user",
      schema: diagnosticResponseSchema,
      maxOutputTokens: 900,
      signal: new AbortController().signal
    })).rejects.toBeInstanceOf(LiveGenerationInvalidOutputError);
  });
});
