import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const onboardingPath = fileURLToPath(
  new URL("../../OpenLARP/Views/GuidedCareerOnboardingView.swift", import.meta.url),
);

describe("accessible onboarding form contract", () => {
  it("pairs every visible single-line example prompt with the same spoken hint", () => {
    const source = readFileSync(onboardingPath, "utf8");
    const prompts = [...source.matchAll(/prompt: onboardingFieldPrompt\("([^"]+)"\)/g)]
      .map((match) => match[1])
      .sort();
    const spokenHints = [...source.matchAll(/\.accessibilityHint\("Example: ([^"]+)\."\)/g)]
      .map((match) => match[1])
      .sort();

    expect(prompts.length).toBeGreaterThan(0);
    expect(spokenHints).toEqual(prompts);
  });
});
