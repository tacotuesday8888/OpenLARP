import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const onboardingPath = fileURLToPath(
  new URL("../../OpenLARP/Views/GuidedCareerOnboardingView.swift", import.meta.url),
);

describe("accessible onboarding form contract", () => {
  it("renders single-line examples as persistent accessibility elements", () => {
    const source = readFileSync(onboardingPath, "utf8");
    const persistentExamples = [...source.matchAll(/onboardingFieldHint\("Example: ([^"]+)\."\)/g)]
      .map((match) => match[1])
      .sort();

    expect(persistentExamples).toEqual([
      "Entry-level iOS engineer",
      "Within 90 days",
    ]);
    expect(source).not.toContain("prompt: onboardingFieldPrompt");
    expect(source).not.toContain("private func onboardingFieldPrompt");
  });

  it("keeps visible guidance out of native text-field placeholders", () => {
    const source = readFileSync(onboardingPath, "utf8");
    const emptyPlaceholderFields = [...source.matchAll(/TextField\(\s+"",/g)];

    expect(emptyPlaceholderFields).toHaveLength(8);
    expect(source).not.toContain('TextField(\n                        "Target role or career outcome",');
    expect(source).not.toContain('TextField(\n                    "Career goal timeline",');
    expect(source).not.toContain("TextField(\n                question.question,");
  });
});
