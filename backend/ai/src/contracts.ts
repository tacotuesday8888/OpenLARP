import { z } from "genkit";

export const implementedWorkflowKinds = [
  "cookedDiagnostic",
  "questPlan",
  "proofQualityCheck",
  "progressSummary",
  "careerBrief",
  "safeShareCardText",
  "opportunityRanking",
  "agentScan"
] as const;

export const workflowKindSchema = z.enum(implementedWorkflowKinds);

export const providerRouteSchema = z.enum([
  "localMock",
  "firebaseCallableGenkit",
  "cloudRunGenkit"
]);

export const safetyRulesSchema = z.object({
  hardBannedClaims: z.array(z.string()).min(1),
  requiredBehaviors: z.array(z.string()).min(1),
  privacyRequirements: z.array(z.string()).min(1)
});

export const privacySchema = z.object({
  memoryMode: z.enum(["localOnly", "cloudReady", "off"]),
  allowsLongTermMemoryWrite: z.boolean(),
  requiresUserApprovalForExternalActions: z.boolean(),
  shareWins: z.boolean()
});

export const runMetadataSchema = z.object({
  schemaVersion: z.literal(1),
  kind: workflowKindSchema,
  providerRoute: providerRouteSchema,
  requestedAt: z.string().datetime(),
  requestID: z.string().uuid(),
  privacy: privacySchema
});

export const requestEnvelopeSchema = z.object({
  schemaVersion: z.literal(1),
  run: runMetadataSchema,
  safetyRules: safetyRulesSchema,
  payload: z.unknown()
});

export const careerGoalSchema = z.object({
  currentStatus: z.string(),
  targetRole: z.string().min(1).max(120),
  timeline: z.string().min(1).max(120),
  background: z.string().max(4000).default(""),
  existingProof: z.string().max(4000).default(""),
  confidence: z.number().int().min(1).max(5),
  biggestBlocker: z.string().max(1000).default("")
});

export const readinessMetricsSchema = z.object({
  overall: z.number().int().min(0).max(100),
  proofStrength: z.number().int().min(0).max(100),
  confidence: z.number().int().min(0).max(100),
  consistency: z.number().int().min(0).max(100),
  skillProof: z.number().int().min(0).max(100),
  networkStrength: z.number().int().min(0).max(100)
});

export const questSchema = z.object({
  id: z.string().uuid().optional(),
  day: z.number().int().min(1).max(14),
  title: z.string().min(1).max(120),
  purpose: z.string().min(1).max(500),
  timeEstimateMinutes: z.number().int().min(5).max(180),
  difficulty: z.string().min(1).max(40),
  gap: z.string().min(1).max(80),
  proofRequired: z.string().min(1).max(300),
  xpReward: z.number().int().min(0).max(1000),
  steps: z.array(z.string().min(1).max(220)).min(1).max(6)
});

export const proofSubmissionSchema = z.object({
  kind: z.string(),
  text: z.string().max(8000).default(""),
  link: z.string().max(1000).default(""),
  submittedAt: z.string().datetime().optional(),
  attachments: z.array(z.object({
    contentType: z.string(),
    byteCount: z.number().int().nonnegative()
  })).max(8).default([])
});

export const progressContextSchema = z.object({
  readiness: readinessMetricsSchema,
  completedQuestCount: z.number().int().nonnegative(),
  proofCount: z.number().int().nonnegative(),
  streakCount: z.number().int().nonnegative(),
  xp: z.number().int().nonnegative(),
  xpGoal: z.number().int().positive()
});

export const workflowContextSchema = z.object({
  schemaVersion: z.literal(1),
  targetRoleTitle: z.string().min(1).max(120),
  currentQuest: questSchema.optional().nullable(),
  progress: progressContextSchema,
  privacy: privacySchema,
  allowsLongTermMemoryWrite: z.boolean()
});

export const diagnosticPayloadSchema = z.object({
  goal: careerGoalSchema,
  requestedAt: z.string().datetime().optional()
});

export const questPlanPayloadSchema = z.object({
  goal: careerGoalSchema,
  diagnostic: z.object({
    score: z.number().int().min(0).max(100),
    label: z.string(),
    mainGap: z.string(),
    strongestSignal: z.string(),
    fastestFix: z.string(),
    readinessBaseline: z.number().int().min(0).max(100)
  }),
  requestedAt: z.string().datetime().optional()
});

export const proofQualityPayloadSchema = z.object({
  context: workflowContextSchema,
  proof: proofSubmissionSchema,
  requestedAt: z.string().datetime().optional(),
  targetRoleTitle: z.string().min(1).max(120)
});

export const progressSummaryPayloadSchema = z.object({
  context: workflowContextSchema,
  requestedAt: z.string().datetime().optional(),
  targetRoleTitle: z.string().min(1).max(120)
});

export const careerBriefPayloadSchema = z.object({
  context: workflowContextSchema,
  requestedAt: z.string().datetime().optional(),
  targetRoleTitle: z.string().min(1).max(120),
  opportunities: z.array(z.lazy(() => opportunitySchema)).max(20).default([])
});

export const safeShareCardTextPayloadSchema = z.object({
  context: workflowContextSchema,
  proof: proofSubmissionSchema.optional().nullable(),
  requestedAt: z.string().datetime().optional(),
  targetRoleTitle: z.string().min(1).max(120),
  maxCharacters: z.number().int().min(120).max(500).default(280)
});

export const opportunitySchema = z.object({
  type: z.enum(["Job", "Internship", "Project", "Course", "Certificate", "Networking"]),
  title: z.string().min(1).max(160),
  sourceName: z.string().min(1).max(120),
  fitScore: z.number().int().min(0).max(100),
  urgencyScore: z.number().int().min(0).max(100),
  missingProofScore: z.number().int().min(0).max(100),
  impactScore: z.number().int().min(0).max(100),
  whyItMatters: z.string().min(1).max(500),
  missingProof: z.string().min(1).max(240),
  recommendedAction: z.string().min(1).max(300),
  deadline: z.string().datetime().optional().nullable(),
  approvalRequired: z.boolean().default(true)
});

export const rankedOpportunitySchema = opportunitySchema.extend({
  compositeScore: z.number().int().min(0).max(100),
  rank: z.number().int().positive()
});

export const diagnosticResponseSchema = z.object({
  score: z.number().int().min(0).max(100),
  label: z.string().min(1).max(80),
  mainGap: z.string().min(1).max(500),
  strongestSignal: z.string().min(1).max(500),
  fastestFix: z.string().min(1).max(500),
  readinessBaseline: z.number().int().min(0).max(100)
});

export const questPlanResponseSchema = z.object({
  quests: z.array(questSchema).min(1).max(14)
});

export const proofQualityResponseSchema = z.object({
  isAccepted: z.boolean(),
  qualityScore: z.number().int().min(0).max(100),
  label: z.string().min(1).max(80),
  reason: z.string().min(1).max(500),
  improvement: z.string().min(1).max(500),
  xpEarned: z.number().int().min(0).max(1000),
  readinessDelta: z.number().int().min(0).max(20)
});

export const progressSummaryResponseSchema = z.object({
  summary: z.string().min(1).max(800),
  readiness: readinessMetricsSchema,
  nextQuestTitle: z.string().max(140).optional().nullable()
});

export const careerBriefResponseSchema = z.object({
  title: z.string().min(1).max(120),
  summary: z.string().min(1).max(1000),
  opportunities: z.array(rankedOpportunitySchema).max(10),
  nextSteps: z.array(z.object({
    title: z.string().min(1).max(120),
    detail: z.string().min(1).max(400)
  })).min(1).max(6)
});

export const opportunityRankingPayloadSchema = z.object({
  targetRole: z.object({
    title: z.string().min(1).max(120),
    keywords: z.array(z.string()).max(40)
  }),
  opportunities: z.array(opportunitySchema).max(30)
});

export const agentScanPayloadSchema = z.object({
  targetRole: z.object({
    title: z.string().min(1).max(120),
    keywords: z.array(z.string()).max(40)
  }),
  approvedSources: z.array(z.object({
    type: z.enum(["jobBoard", "schoolPortal", "courseCatalog", "network", "projectBoard", "custom"]),
    name: z.string().min(1).max(120),
    url: z.string().url().optional().nullable()
  })).max(20),
  opportunities: z.array(opportunitySchema).max(30).default([]),
  requestedAt: z.string().datetime().optional()
});

export const opportunityRankingResponseSchema = z.object({
  opportunities: z.array(rankedOpportunitySchema).max(30)
});

export const safeShareCardTextResponseSchema = z.object({
  headline: z.string().min(1).max(120),
  body: z.string().min(1).max(500),
  disclosure: z.string().min(1).max(200),
  shareable: z.boolean()
});

export const agentScanResponseSchema = z.object({
  scannedSourceCount: z.number().int().nonnegative(),
  findings: z.array(rankedOpportunitySchema).max(10),
  briefTitle: z.string().min(1).max(120),
  briefSummary: z.string().min(1).max(800),
  recommendedNextActions: z.array(z.string().min(1).max(240)).min(1).max(5)
});

export type RequestEnvelope = z.infer<typeof requestEnvelopeSchema>;
export type WorkflowKind = z.infer<typeof workflowKindSchema>;
export type DiagnosticPayload = z.infer<typeof diagnosticPayloadSchema>;
export type QuestPlanPayload = z.infer<typeof questPlanPayloadSchema>;
export type ProofQualityPayload = z.infer<typeof proofQualityPayloadSchema>;
export type ProgressSummaryPayload = z.infer<typeof progressSummaryPayloadSchema>;
export type CareerBriefPayload = z.infer<typeof careerBriefPayloadSchema>;
export type SafeShareCardTextPayload = z.infer<typeof safeShareCardTextPayloadSchema>;
export type OpportunityRankingPayload = z.infer<typeof opportunityRankingPayloadSchema>;
export type AgentScanPayload = z.infer<typeof agentScanPayloadSchema>;
export type RankedOpportunity = z.infer<typeof rankedOpportunitySchema>;
