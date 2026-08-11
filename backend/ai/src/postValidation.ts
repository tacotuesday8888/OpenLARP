import {
  adaptiveCareerIntakePayloadSchema,
  adaptiveCareerIntakeResponseSchema,
  diagnosticResponseSchema,
  progressSummaryResponseSchema,
  proofQualityResponseSchema,
  questPlanResponseSchema,
  type WorkflowKind
} from "./contracts.js";
import { checkProofQuality } from "./mockWorkflows.js";
import { assertSafeGeneratedText } from "./safety.js";

export type GeneratedOutputRejectionReason = "invalidOutput" | "unsafeOutput";

export type GeneratedOutputValidation =
  | { ok: true; result: unknown }
  | { ok: false; reason: GeneratedOutputRejectionReason };

export function validateGeneratedWorkflowResult(
  kind: WorkflowKind,
  payload: unknown,
  candidate: unknown
): GeneratedOutputValidation {
  const parsed = responseSchemaFor(kind).safeParse(candidate);
  if (!parsed.success) {
    return { ok: false, reason: "invalidOutput" };
  }

  const outputText = stringsFrom(parsed.data).join("\n");
  try {
    assertSafeGeneratedText(outputText);
  } catch {
    return { ok: false, reason: "unsafeOutput" };
  }

  if (claimsUnsupportedInspection(outputText) || claimsCompletedExternalAction(outputText)) {
    return { ok: false, reason: "unsafeOutput" };
  }
  if (containsUnsupportedSubstantialClaim(outputText, payload)) {
    return { ok: false, reason: "unsafeOutput" };
  }

  if (kind === "cookedDiagnostic") {
    const diagnostic = diagnosticResponseSchema.parse(parsed.data);
    if (Math.abs(diagnostic.score - diagnostic.readinessBaseline) > 20) {
      return { ok: false, reason: "invalidOutput" };
    }
  }

  if (kind === "adaptiveCareerIntake") {
    const intakePayload = adaptiveCareerIntakePayloadSchema.safeParse(payload);
    const intakeResult = adaptiveCareerIntakeResponseSchema.parse(parsed.data);
    if (!intakePayload.success) {
      return { ok: false, reason: "invalidOutput" };
    }
    const unknownKinds = new Set(intakePayload.data.unknownKinds);
    const questionKinds = intakeResult.questions.map((question) => question.factKind);
    if (
      intakeResult.questions.length > intakePayload.data.maxQuestions ||
      questionKinds.some((kind) => !unknownKinds.has(kind)) ||
      new Set(questionKinds).size !== questionKinds.length ||
      intakeResult.hypotheses.some((hypothesis) => !unknownKinds.has(hypothesis.kind))
    ) {
      return { ok: false, reason: "invalidOutput" };
    }
  }

  if (kind === "proofQualityCheck") {
    const expectedReward = checkProofQuality(payload as Parameters<typeof checkProofQuality>[0]);
    const proofResult = proofQualityResponseSchema.parse(parsed.data);
    if (
      proofResult.xpEarned !== expectedReward.xpEarned ||
      proofResult.readinessDelta !== expectedReward.readinessDelta
    ) {
      return { ok: false, reason: "invalidOutput" };
    }
  }

  return { ok: true, result: parsed.data };
}

function responseSchemaFor(kind: WorkflowKind) {
  switch (kind) {
    case "adaptiveCareerIntake":
      return adaptiveCareerIntakeResponseSchema;
    case "cookedDiagnostic":
      return diagnosticResponseSchema;
    case "questPlan":
      return questPlanResponseSchema;
    case "proofQualityCheck":
      return proofQualityResponseSchema;
    case "progressSummary":
      return progressSummaryResponseSchema;
    default:
      return {
        safeParse: () => ({ success: false as const })
      };
  }
}

function stringsFrom(value: unknown): string[] {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap(stringsFrom);
  }
  if (value && typeof value === "object") {
    return Object.values(value).flatMap(stringsFrom);
  }
  return [];
}

function claimsUnsupportedInspection(text: string): boolean {
  return /\b(?:i|we|openlarp|the system)\s+(?:inspected|opened|viewed|reviewed|read|fetched|accessed)\s+(?:the\s+)?(?:link|attachment|screenshot|photo|image|file)s?\b/i.test(text);
}

function claimsCompletedExternalAction(text: string): boolean {
  return /\b(?:i|we|openlarp|the system)\s+(?:sent|submitted|published|applied|messaged|emailed|contacted|scheduled)\b/i.test(text);
}

function containsUnsupportedSubstantialClaim(text: string, payload: unknown): boolean {
  const source = normalize(JSON.stringify(payload));
  const patterns = [
    /\bworked at\s+[^.!?,;\n]{1,80}/gi,
    /\bgraduated from\s+[^.!?,;\n]{1,80}/gi,
    /\b(?:earned|obtained)\s+(?:a\s+)?(?:certificate|certification|credential|degree)\s+[^.!?,;\n]{0,80}/gi,
    /\b(?:owned|led|shipped|built)\s+[^.!?,;\n]{1,80}/gi
  ];

  return patterns.some((pattern) =>
    [...text.matchAll(pattern)].some((match) => !source.includes(normalize(match[0])))
  );
}

function normalize(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}
