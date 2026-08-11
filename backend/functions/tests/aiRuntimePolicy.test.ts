import { describe, expect, it, vi } from "vitest";
import { createCachedAIRuntimePolicyReader } from "../src/aiRuntimePolicy.js";

const now = new Date("2026-08-10T10:00:00.000Z");

function validPolicy() {
  return {
    schemaVersion: 1,
    revision: "beta-2026-08-10",
    enabled: true,
    validUntil: "2026-08-10T12:00:00.000Z",
    timeoutMs: 15_000,
    maxOutputTokens: 1200,
    workflows: {
      adaptiveCareerIntake: true,
      cookedDiagnostic: true,
      missionBrief: true,
      questPlan: true,
      proofQualityCheck: false,
      progressSummary: true
    }
  };
}

describe("createCachedAIRuntimePolicyReader", () => {
  it("enables only a workflow explicitly enabled by a valid master policy", async () => {
    const readDocument = vi.fn(async () => validPolicy());
    const reader = createCachedAIRuntimePolicyReader({ readDocument, cacheTTLms: 30_000 });

    await expect(reader.read("cookedDiagnostic", now)).resolves.toEqual({
      enabled: true,
      policyRevision: "beta-2026-08-10",
      timeoutMs: 15_000,
      maxOutputTokens: 1200,
      fallbackReason: null
    });
    await expect(reader.read("proofQualityCheck", now)).resolves.toMatchObject({
      enabled: false,
      fallbackReason: "policy"
    });
    await expect(reader.read("missionBrief", now)).resolves.toMatchObject({
      enabled: true,
      policyRevision: "beta-2026-08-10"
    });
  });

  it("caches a valid policy briefly without caching private workflow input", async () => {
    const readDocument = vi.fn(async () => validPolicy());
    const reader = createCachedAIRuntimePolicyReader({ readDocument, cacheTTLms: 30_000 });

    await reader.read("cookedDiagnostic", now);
    await reader.read("questPlan", new Date(now.getTime() + 10_000));

    expect(readDocument).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(readDocument.mock.calls)).not.toContain("iOS engineer");
  });

  it.each([
    ["missing", null],
    ["malformed", { schemaVersion: 1, enabled: true }],
    ["expired", { ...validPolicy(), validUntil: "2026-08-10T09:59:59.000Z" }]
  ])("fails closed for a %s policy", async (_name, document) => {
    const reader = createCachedAIRuntimePolicyReader({
      readDocument: async () => document,
      cacheTTLms: 30_000
    });

    await expect(reader.read("cookedDiagnostic", now)).resolves.toEqual({
      enabled: false,
      policyRevision: "unavailable",
      timeoutMs: 10_000,
      maxOutputTokens: 1200,
      fallbackReason: "policy"
    });
  });

  it("fails closed when Firestore is unavailable", async () => {
    const reader = createCachedAIRuntimePolicyReader({
      readDocument: async () => { throw new Error("private Firestore outage detail"); },
      cacheTTLms: 30_000
    });

    await expect(reader.read("cookedDiagnostic", now)).resolves.toMatchObject({
      enabled: false,
      policyRevision: "unavailable",
      fallbackReason: "policy"
    });
  });
});
