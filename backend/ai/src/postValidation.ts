import {
  adaptiveCareerIntakePayloadSchema,
  adaptiveCareerIntakeResponseSchema,
  contextualAssistantPayloadSchema,
  contextualAssistantResponseSchema,
  diagnosticResponseSchema,
  missionBriefPayloadSchema,
  missionBriefResponseSchema,
  progressSummaryResponseSchema,
  proofCoachingResponseSchema,
  proofQualityPayloadSchema,
  proofQualityResponseSchema,
  questPlanPayloadSchema,
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
    const pendingHypothesisKinds = new Set(
      intakePayload.data.pendingHypotheses.map((hypothesis) => hypothesis.kind)
    );
    const hypothesisKinds = intakeResult.hypotheses.map((hypothesis) => hypothesis.kind);
    if (
      intakeResult.questions.length > intakePayload.data.maxQuestions ||
      intakeResult.hypotheses.length + intakePayload.data.pendingHypotheses.length > 2 ||
      questionKinds.some((kind) => !unknownKinds.has(kind)) ||
      new Set(questionKinds).size !== questionKinds.length ||
      hypothesisKinds.some((kind) => !unknownKinds.has(kind) || pendingHypothesisKinds.has(kind)) ||
      new Set(hypothesisKinds).size !== hypothesisKinds.length
    ) {
      return { ok: false, reason: "invalidOutput" };
    }
  }

  if (kind === "missionBrief") {
    const missionPayload = missionBriefPayloadSchema.safeParse(payload);
    const mission = missionBriefResponseSchema.parse(parsed.data);
    if (
      !missionPayload.success ||
      mission.targetOutcome !== missionPayload.data.goal.targetRole ||
      mission.constraints !== missionPayload.data.goal.constraints ||
      mission.dailyCommitmentMinutes !== missionPayload.data.goal.dailyCommitmentMinutes ||
      JSON.stringify(mission.confirmedCurrentState) !== JSON.stringify(missionPayload.data.confirmedFacts) ||
      JSON.stringify(mission.ethicalBoundaries) !== JSON.stringify(missionPayload.data.requiredEthicalBoundaries)
    ) {
      return { ok: false, reason: "invalidOutput" };
    }
  }

  if (kind === "questPlan") {
    const questPayload = questPlanPayloadSchema.safeParse(payload);
    const questPlan = questPlanResponseSchema.parse(parsed.data);
    if (!questPayload.success) {
      return { ok: false, reason: "invalidOutput" };
    }
    const startingDay = questPayload.data.chapterTwoContext ? 8 : 1;
    const expectedDays = Array.from({ length: 7 }, (_, index) => startingDay + index);
    const dailyCommitment = questPayload.data.mission?.dailyCommitmentMinutes ??
      questPayload.data.goal.dailyCommitmentMinutes;
    if (
      questPlan.quests.length !== 7 ||
      questPlan.quests.some((quest, index) => quest.day !== expectedDays[index]) ||
      questPlan.quests.some((quest) => quest.timeEstimateMinutes > dailyCommitment)
    ) {
      return { ok: false, reason: "invalidOutput" };
    }
  }

  if (kind === "proofQualityCheck") {
    const proofPayload = proofQualityPayloadSchema.safeParse(payload);
    if (!proofPayload.success) {
      return { ok: false, reason: "invalidOutput" };
    }
    const coaching = proofCoachingResponseSchema.parse(parsed.data);
    const expectedResult = proofQualityResponseSchema.parse(checkProofQuality(proofPayload.data));
    return {
      ok: true,
      result: {
        ...expectedResult,
        reason: coaching.reason,
        improvement: coaching.improvement
      }
    };
  }

  if (kind === "contextualAssistant") {
    const assistantPayload = contextualAssistantPayloadSchema.safeParse(payload);
    const assistant = contextualAssistantResponseSchema.parse(parsed.data);
    if (!assistantPayload.success) {
      return { ok: false, reason: "invalidOutput" };
    }
    const confirmedFactIDs = new Set(assistantPayload.data.confirmedFacts.map((fact) => fact.id));
    if (assistant.factIDsUsed.some((id) => !confirmedFactIDs.has(id))) {
      return { ok: false, reason: "unsafeOutput" };
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
    case "missionBrief":
      return missionBriefResponseSchema;
    case "questPlan":
      return questPlanResponseSchema;
    case "proofQualityCheck":
      return proofCoachingResponseSchema;
    case "progressSummary":
      return progressSummaryResponseSchema;
    case "contextualAssistant":
      return contextualAssistantResponseSchema;
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
