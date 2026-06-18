import type {
  AgentScanPayload,
  CareerBriefPayload,
  DiagnosticPayload,
  OpportunityRankingPayload,
  ProofQualityPayload,
  ProgressSummaryPayload,
  QuestPlanPayload,
  RankedOpportunity,
  SafeShareCardTextPayload
} from "./contracts.js";
import { assertSafeGeneratedText } from "./safety.js";

export function makeDiagnostic(payload: DiagnosticPayload) {
  const targetRole = payload.goal.targetRole;
  const hasProof = payload.goal.existingProof.trim().length > 0;
  const response = {
    score: hasProof ? 62 : 52,
    label: hasProof ? "Some proof, not enough signal" : "Clear target, thin proof",
    mainGap: `Your ${targetRole} goal needs stronger evidence tied to real role requirements.`,
    strongestSignal: hasProof
      ? "You already have starting proof that can be sharpened."
      : "You named a target clearly enough to build a first proof sprint.",
    fastestFix: "Create one small artifact that demonstrates a real target-role requirement.",
    readinessBaseline: hasProof ? 48 : 38
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}

export function makeQuestPlan(payload: QuestPlanPayload) {
  const targetRole = payload.goal.targetRole;
  return {
    quests: [
      {
        day: 1,
        title: `Map 3 requirements for ${targetRole}`,
        purpose: "Turn vague career anxiety into a concrete proof target.",
        timeEstimateMinutes: 25,
        difficulty: "Starter",
        gap: "proofStrength",
        proofRequired: "Paste the requirement notes or link to the document.",
        xpReward: 120,
        steps: [
          "Find two current role descriptions.",
          "List three repeated requirements.",
          "Pick the requirement you can prove fastest this week."
        ]
      },
      {
        day: 2,
        title: "Create one tiny proof artifact",
        purpose: "A small real artifact is more useful than a broad unsupported claim.",
        timeEstimateMinutes: 30,
        difficulty: "Starter",
        gap: "skillProof",
        proofRequired: "Add a link, screenshot, or notes showing what you made.",
        xpReward: 130,
        steps: [
          "Choose the smallest artifact that proves one requirement.",
          "Make the first version.",
          "Write exactly what it proves."
        ]
      },
      {
        day: 3,
        title: "Turn proof into one honest profile bullet",
        purpose: "Better wording should clarify real work, not invent facts.",
        timeEstimateMinutes: 20,
        difficulty: "Balanced",
        gap: "confidence",
        proofRequired: "Paste the before and after bullet.",
        xpReward: 100,
        steps: [
          "Choose one true thing you have done.",
          "Write the plain version.",
          "Rewrite it with impact while keeping every claim defensible."
        ]
      }
    ]
  };
}

export function checkProofQuality(payload: ProofQualityPayload) {
  const proofText = payload.proof.text.trim();
  const hasLink = payload.proof.link.trim().length > 0;
  const hasAttachment = payload.proof.attachments.length > 0;
  const qualityScore = Math.min(94, proofText.length >= 80 ? 78 + (hasLink ? 7 : 0) + (hasAttachment ? 6 : 0) : 46);
  const isAccepted = qualityScore >= 65;
  const response = {
    isAccepted,
    qualityScore,
    label: isAccepted ? "Credible proof" : "Needs stronger evidence",
    reason: isAccepted
      ? "The proof describes a concrete action and can be tied to the target role."
      : "The submission is still too thin to support a strong career claim.",
    improvement: isAccepted
      ? "Add one measurable detail or a linkable artifact next."
      : "Describe what you actually made, sent, analyzed, or improved.",
    xpEarned: isAccepted ? 120 : 40,
    readinessDelta: isAccepted ? 6 : 1
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}

export function summarizeProgress(payload: ProgressSummaryPayload) {
  const progress = payload.context.progress;
  const nextQuestTitle = payload.context.currentQuest?.title ?? null;
  const response = {
    summary: `For ${payload.targetRoleTitle}, readiness is ${progress.readiness.overall}%. You have ${progress.proofCount} proof receipts, ${progress.completedQuestCount} completed quests, and a ${progress.streakCount}-day streak.`,
    readiness: progress.readiness,
    nextQuestTitle
  };
  assertSafeGeneratedText(response.summary);
  return response;
}

export function makeCareerBrief(payload: CareerBriefPayload) {
  const ranked = payload.opportunities.length > 0
    ? rankOpportunities({
        targetRole: {
          title: payload.targetRoleTitle,
          keywords: payload.targetRoleTitle.split(/[^A-Za-z0-9]+/).filter(Boolean)
        },
        opportunities: payload.opportunities
      }).opportunities.slice(0, 5)
    : [];

  const response = {
    title: `${payload.targetRoleTitle} readiness brief`,
    summary: `Readiness is ${payload.context.progress.readiness.overall}%. The next best move is to convert today's work into one concrete proof receipt before broadening the search.`,
    opportunities: ranked,
    nextSteps: [
      {
        title: "Complete today's proof action",
        detail: payload.context.currentQuest?.title
          ? `Finish "${payload.context.currentQuest.title}" and save proof before starting a new search task.`
          : "Create a small artifact that proves one target-role requirement."
      },
      {
        title: "Review the top ranked opportunity",
        detail: ranked[0]
          ? `Prioritize ${ranked[0].title} because it scores highest on fit, urgency, proof gap, and expected impact.`
          : "Add approved opportunity sources so the agent can rank relevant openings and projects."
      }
    ]
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}

export function makeSafeShareCardText(payload: SafeShareCardTextPayload) {
  const proofKind = payload.proof?.kind.trim() || "career action";
  const body = payload.proof
    ? `Working toward ${payload.targetRoleTitle}: saved a private ${proofKind} proof receipt.`
    : `Working toward ${payload.targetRoleTitle}: completed a focused career action and saved the proof privately.`;
  const trimmedBody = body.length > payload.maxCharacters
    ? `${body.slice(0, Math.max(0, payload.maxCharacters - 1)).trim()}`
    : body;
  const response = {
    headline: "Career proof saved",
    body: trimmedBody,
    disclosure: "Generated from user-approved proof. Review before sharing.",
    shareable: true
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}

export function rankOpportunities(payload: OpportunityRankingPayload) {
  const keywords = new Set(payload.targetRole.keywords.map((keyword) => keyword.toLowerCase()));
  const opportunities = payload.opportunities
    .map((opportunity): RankedOpportunity => {
      const titleTokens = new Set(opportunity.title.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean));
      const keywordBoost = [...keywords].some((keyword) => titleTokens.has(keyword)) ? 4 : 0;
      const typeBoost = opportunity.type === "Project" ? 5 : opportunity.type === "Networking" ? 3 : 1;
      const compositeScore = Math.min(
        100,
        Math.floor(opportunity.fitScore * 0.35) +
          Math.floor(opportunity.urgencyScore * 0.25) +
          Math.floor(opportunity.missingProofScore * 0.2) +
          Math.floor(opportunity.impactScore * 0.2) +
          keywordBoost +
          typeBoost
      );
      return {
        ...opportunity,
        compositeScore,
        rank: 0
      };
    })
    .sort((left, right) => right.compositeScore - left.compositeScore || right.fitScore - left.fitScore)
    .map((opportunity, index) => ({
      ...opportunity,
      rank: index + 1
    }));

  return { opportunities };
}

export function makeAgentScan(payload: AgentScanPayload) {
  const ranked = rankOpportunities({
    targetRole: payload.targetRole,
    opportunities: payload.opportunities
  }).opportunities.slice(0, 10);
  const topFinding = ranked[0];
  const response = {
    scannedSourceCount: payload.approvedSources.length,
    findings: ranked,
    briefTitle: topFinding ? `Top ${payload.targetRole.title} opportunity found` : "No ranked opportunities yet",
    briefSummary: topFinding
      ? `${topFinding.title} is the strongest current match because it combines role fit, urgency, proof-gap coverage, and expected career impact.`
      : "The agent has approved sources but needs returned opportunities before it can produce a ranked brief.",
    recommendedNextActions: [
      topFinding
        ? topFinding.recommendedAction
        : "Add or reconnect approved sources that can return jobs, internships, projects, courses, certificates, or networking leads.",
      "Save any completed action as proof so readiness can update from evidence instead of intent."
    ]
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}
