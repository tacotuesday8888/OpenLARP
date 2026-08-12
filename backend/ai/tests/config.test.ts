import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  DEFAULT_GEMINI_MODEL_ID,
  configFromEnvironment,
  providerBudgetPolicyFromEnvironment
} from "../src/config.js";

describe("configFromEnvironment", () => {
  it("keeps backend operator guidance aligned with the supported Vertex default", () => {
    const readme = readFileSync(new URL("../README.md", import.meta.url), "utf8");

    expect(readme).toContain("`gemini-3.5-flash`");
    expect(readme).toContain("`vertex-ai`");
    expect(readme).toContain("`global`");
    expect(readme).toContain("Application Default Credentials");
    expect(readme).not.toContain("gemini-3.1-flash-lite");
    expect(readme).not.toContain("GEMINI_API_KEY");
    expect(readme).not.toContain("OPENLARP_AI_PROVIDER=firebase-ai-logic");
  });

  it("uses the controlled Vertex AI defaults with live generation disabled", () => {
    const config = configFromEnvironment({});

    expect(DEFAULT_GEMINI_MODEL_ID).toBe("gemini-3.5-flash");
    expect(config).toEqual({
      modelId: "gemini-3.5-flash",
      provider: "vertex-ai",
      vertexLocation: "global",
      enableLiveGeneration: false,
      maxOutputTokens: 1200
    });
  });

  it("enables live generation only for the exact true flag", () => {
    expect(configFromEnvironment({ OPENLARP_ENABLE_LIVE_AI: "true" }).enableLiveGeneration).toBe(true);
    expect(configFromEnvironment({ OPENLARP_ENABLE_LIVE_AI: "TRUE" }).enableLiveGeneration).toBe(false);
    expect(configFromEnvironment({ OPENLARP_ENABLE_LIVE_AI: "1" }).enableLiveGeneration).toBe(false);
  });

  it("accepts an explicit Vertex location without exposing it to clients", () => {
    expect(configFromEnvironment({ OPENLARP_VERTEX_LOCATION: "us-central1" }).vertexLocation)
      .toBe("us-central1");
  });

  it("rejects malformed provider and output-token configuration", () => {
    expect(() => configFromEnvironment({ OPENLARP_AI_PROVIDER: "unknown" })).toThrow(
      "Unsupported OPENLARP_AI_PROVIDER"
    );
    expect(() => configFromEnvironment({ OPENLARP_AI_MAX_OUTPUT_TOKENS: "9000" })).toThrow(
      "OPENLARP_AI_MAX_OUTPUT_TOKENS"
    );
  });
});

describe("providerBudgetPolicyFromEnvironment", () => {
  it("requires all provider pricing and daily budget values together", () => {
    expect(providerBudgetPolicyFromEnvironment({})).toBeNull();
    expect(() => providerBudgetPolicyFromEnvironment({
      OPENLARP_AI_INPUT_TOKEN_MICROS_PER_1K: "20"
    })).toThrow("requires input, output, and daily budget micros");
  });
});
