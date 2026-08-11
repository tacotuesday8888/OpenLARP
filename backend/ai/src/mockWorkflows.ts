import type {
  AdaptiveCareerIntakePayload,
  AgentScanPayload,
  CareerBriefPayload,
  DiagnosticPayload,
  MissionBriefPayload,
  OpportunityRankingPayload,
  ProofQualityPayload,
  ProgressSummaryPayload,
  QuestPlanPayload,
  RankedOpportunity,
  SafeShareCardTextPayload
} from "./contracts.js";
import { assertSafeGeneratedText } from "./safety.js";

const adaptiveQuestionCopy = {
  outcomeType: "What kind of outcome are you pursuing?",
  targetOutcome: "What specific career outcome do you want?",
  currentStage: "What is your current career stage?",
  timeline: "When do you want to reach this outcome?",
  urgency: "How urgent is this goal?",
  experience: "What relevant experience have you actually completed?",
  existingProof: "What work can you already show or explain?",
  constraints: "What limits should the plan respect?",
  confidence: "How confident do you feel about this goal today?",
  dailyCommitment: "How much time can you realistically spend each day?",
  biggestBlocker: "What is the biggest blocker right now?"
} as const;

export function makeAdaptiveCareerIntake(payload: AdaptiveCareerIntakePayload) {
  const questions = payload.unknownKinds.slice(0, payload.maxQuestions).map((factKind) => ({
    id: `adaptive-${factKind}`,
    factKind,
    question: adaptiveQuestionCopy[factKind],
    rationale: "This missing detail changes which first action is realistic and useful.",
    responseType: factKind === "confidence"
      ? "confidence" as const
      : factKind === "dailyCommitment"
        ? "duration" as const
        : factKind === "outcomeType" || factKind === "urgency"
          ? "singleChoice" as const
          : "freeText" as const,
    options: factKind === "outcomeType"
      ? ["Job", "Internship", "Promotion", "Career change"]
      : factKind === "urgency"
        ? ["Exploring", "Steady", "Urgent"]
        : []
  }));

  return { questions, hypotheses: [] };
}

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
    readinessBaseline: hasProof ? 48 : 38,
    strongestSignals: [hasProof
      ? "You already have starting proof that can be sharpened."
      : "You named a target clearly enough to build a first proof sprint."],
    readinessGaps: [`The ${targetRole} goal needs stronger evidence tied to real role requirements.`],
    missingInformation: hasProof
      ? ["The strength and relevance of the existing proof have not been independently verified."]
      : ["No existing proof was provided for this baseline."],
    uncertaintyExplanation: "This baseline uses only the information supplied by the user and does not verify unsupported claims.",
    firstAction: `Map three repeated requirements from two current ${targetRole} role descriptions.`
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}

export function makeMissionBrief(payload: MissionBriefPayload) {
  const response = {
    targetOutcome: payload.goal.targetRole,
    confirmedCurrentState: payload.confirmedFacts,
    constraints: payload.goal.constraints,
    mainReadinessGaps: payload.diagnostic.readinessGaps,
    ethicalBoundaries: payload.requiredEthicalBoundaries,
    firstMilestone: payload.diagnostic.firstAction,
    dailyCommitmentMinutes: payload.goal.dailyCommitmentMinutes,
    sprint: {
      dayCount: 14 as const,
      chapterCount: 2 as const,
      summary: "Chapter one builds honest career proof. " +
        "Chapter two adapts the next seven actions using what the first week actually produced."
    }
  };
  assertSafeGeneratedText(JSON.stringify(response));
  return response;
}

export function makeQuestPlan(payload: QuestPlanPayload) {
  const targetRole = payload.goal.targetRole;
  const dailyCommitmentMinutes = payload.mission?.dailyCommitmentMinutes ?? payload.goal.dailyCommitmentMinutes;
  const duration = (suggestedMinutes: number) => Math.max(5, Math.min(suggestedMinutes, dailyCommitmentMinutes));
  if (payload.chapterTwoContext) {
    return {
      quests: [
        {
          day: 8,
          title: "Choose the strongest proof from chapter one",
          purpose: `Use the reviewed evidence to focus the next move: ${payload.chapterTwoContext.nextFocus}`,
          timeEstimateMinutes: duration(20), difficulty: "Adaptive", gap: "proofStrength",
          proofRequired: "Name the proof, its target-role connection, and one honest limitation.", xpReward: 120,
          steps: ["Review the seven evidence scores.", "Choose the strongest proof.", "Record what it proves and does not prove."]
        },
        {
          day: 9, title: "Turn the proof into a concise portfolio story",
          purpose: "Make real work usable in applications and interviews without exaggeration.",
          timeEstimateMinutes: duration(25), difficulty: "Adaptive", gap: "confidence",
          proofRequired: "Save the problem, action, tradeoff, result, and limitation story.", xpReward: 130,
          steps: ["State the real problem.", "Describe only your actions.", "Add the result and one limitation."]
        },
        {
          day: 10, title: `Match the proof to one ${targetRole} requirement`,
          purpose: "Focused evidence is more credible than a generic claim of fit.",
          timeEstimateMinutes: duration(25), difficulty: "Adaptive", gap: "applicationExecution",
          proofRequired: "Save the requirement and exact evidence connection.", xpReward: 130,
          steps: ["Choose one current role description.", "Select one requirement.", "Explain the match without exaggeration."]
        },
        {
          day: 11, title: "Improve one weak edge in the proof",
          purpose: "Make one targeted revision instead of expanding the project without evidence.",
          timeEstimateMinutes: duration(30), difficulty: "Adaptive", gap: "skillProof",
          proofRequired: "Document the before, focused revision, and after.", xpReward: 140,
          steps: ["Choose one limitation.", "Make one bounded improvement.", "Record what changed."]
        },
        {
          day: 12, title: "Use the proof in one honest outreach draft",
          purpose: "Specific work gives a networking message a real reason to exist.",
          timeEstimateMinutes: duration(20), difficulty: "Adaptive", gap: "networkStrength",
          proofRequired: "Save or send a concise message referencing the real artifact.", xpReward: 130,
          steps: ["Choose one relevant person.", "Reference the proof briefly.", "Ask one low-pressure question."]
        },
        {
          day: 13, title: "Use the proof in one focused application action",
          purpose: "Connect evidence to a real opportunity while keeping submission user-controlled.",
          timeEstimateMinutes: duration(25), difficulty: "Adaptive", gap: "applicationExecution",
          proofRequired: "Save the tailored bullet, receipt, or final application-ready draft.", xpReward: 140,
          steps: ["Choose one relevant opportunity.", "Tailor one truthful section.", "Submit or save the final ready-to-send version."]
        },
        {
          day: 14, title: "Run the 14-day evidence review",
          purpose: "Show what changed and choose the next honest focus.",
          timeEstimateMinutes: duration(15), difficulty: "Review", gap: "consistency",
          proofRequired: "Write the strongest result, readiness change, outcome signal, and next focus.", xpReward: 160,
          steps: ["Review all fourteen quests.", "Name the strongest evidence and outcome.", "Choose the next sprint focus."]
        }
      ]
    };
  }
  return {
    quests: [
      {
        day: 1,
        title: `Map 3 requirements for ${targetRole}`,
        purpose: "Turn vague career anxiety into a concrete proof target.",
        timeEstimateMinutes: duration(25),
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
        timeEstimateMinutes: duration(30),
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
        timeEstimateMinutes: duration(20),
        difficulty: "Balanced",
        gap: "confidence",
        proofRequired: "Paste the before and after bullet.",
        xpReward: 100,
        steps: [
          "Choose one true thing you have done.",
          "Write the plain version.",
          "Rewrite it with impact while keeping every claim defensible."
        ]
      },
      {
        day: 4,
        title: "Explain your proof in five bullets",
        purpose: "Clear explanations make real work usable in interviews without exaggerating it.",
        timeEstimateMinutes: duration(25),
        difficulty: "Balanced",
        gap: "confidence",
        proofRequired: "Paste the five-bullet explanation.",
        xpReward: 110,
        steps: [
          "Describe the problem and your action.",
          "Name one tradeoff and the real result.",
          "Name what you would improve next."
        ]
      },
      {
        day: 5,
        title: "Choose one relevant networking target",
        purpose: "A specific, evidence-backed question makes outreach lower pressure and more useful.",
        timeEstimateMinutes: duration(20),
        difficulty: "Spicy",
        gap: "networkStrength",
        proofRequired: "Record the person's role and why their perspective is relevant.",
        xpReward: 120,
        steps: [
          "Find one person whose role is close to your target.",
          "Write why their path is relevant.",
          "Draft one honest question tied to your proof."
        ]
      },
      {
        day: 6,
        title: "Send or save one honest outreach draft",
        purpose: "The action stays user-controlled while turning research into a concrete next move.",
        timeEstimateMinutes: duration(20),
        difficulty: "Spicy",
        gap: "networkStrength",
        proofRequired: "Paste the sent message or the final saved draft.",
        xpReward: 140,
        steps: [
          "Use the target and question from day five.",
          "Write a short message with one clear ask.",
          "Choose whether to send it or keep the final draft."
        ]
      },
      {
        day: 7,
        title: "Run the chapter-one evidence review",
        purpose: "The next chapter should adapt to what this week actually produced.",
        timeEstimateMinutes: duration(15),
        difficulty: "Review",
        gap: "consistency",
        proofRequired: "Write what proof improved and what still blocks the target outcome.",
        xpReward: 160,
        steps: [
          "Review the six completed actions.",
          "Name the strongest honest proof created.",
          "Choose the next readiness gap to shrink."
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
