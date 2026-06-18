import type { RequestEnvelope } from "./contracts.js";

const bannedFragments = [
  "fake employer",
  "fake school",
  "fake certificate",
  "fake job title",
  "fake date",
  "fake project",
  "fake ownership",
  "invent an employer",
  "invent a school",
  "invent a certificate",
  "invent a job title",
  "claim you built it",
  "say you worked at"
];

export type SafetyValidationResult = {
  ok: boolean;
  blockedReasons: string[];
};

export function validateEnvelopeSafety(envelope: RequestEnvelope): SafetyValidationResult {
  const blockedReasons: string[] = [];

  if (!envelope.safetyRules.hardBannedClaims.some(hasFakeEmployerGuardrail)) {
    blockedReasons.push("missing fake-employer guardrail");
  }

  if (!envelope.safetyRules.privacyRequirements.some(hasExternalActionApprovalGuardrail)) {
    blockedReasons.push("missing external-action approval guardrail");
  }

  if (!envelope.run.privacy.requiresUserApprovalForExternalActions) {
    blockedReasons.push("external actions must require user approval");
  }

  if (!envelope.run.privacy.allowsLongTermMemoryWrite && envelope.run.privacy.memoryMode === "cloudReady") {
    blockedReasons.push("cloud-ready memory must explicitly allow long-term writes");
  }

  if (envelope.run.privacy.allowsLongTermMemoryWrite && envelope.run.privacy.memoryMode !== "cloudReady") {
    blockedReasons.push("long-term memory writes require cloud-ready memory mode");
  }

  return {
    ok: blockedReasons.length === 0,
    blockedReasons
  };
}

export function assertSafeGeneratedText(text: string): void {
  const lowercased = text.toLowerCase();
  const match = bannedFragments.find((fragment) => lowercased.includes(fragment));
  if (match) {
    throw new Error(`Unsafe generated text blocked: ${match}`);
  }
}

function hasFakeEmployerGuardrail(value: string): boolean {
  const normalized = normalizePolicyText(value);
  return (hasTerm(normalized, "fake") || hasTerm(normalized, "fabricat") || hasTerm(normalized, "invent")) &&
    hasTerm(normalized, "employer");
}

function hasExternalActionApprovalGuardrail(value: string): boolean {
  const normalized = normalizePolicyText(value);
  return hasTerm(normalized, "external") &&
    hasTerm(normalized, "action") &&
    (hasTerm(normalized, "approval") || hasTerm(normalized, "approve"));
}

function normalizePolicyText(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function hasTerm(normalized: string, stem: string): boolean {
  return new RegExp(`\\b${stem}[a-z]*\\b`).test(normalized);
}
