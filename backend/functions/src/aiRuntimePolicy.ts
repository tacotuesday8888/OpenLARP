import { getFirestore } from "firebase-admin/firestore";
import { z } from "zod";
import type { WorkflowKind } from "../../ai/src/contracts.js";

const LIVE_WORKFLOW_KINDS = [
  "adaptiveCareerIntake",
  "cookedDiagnostic",
  "questPlan",
  "proofQualityCheck",
  "progressSummary"
] as const;

const runtimePolicySchema = z.object({
  schemaVersion: z.literal(1),
  revision: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/),
  enabled: z.boolean(),
  validUntil: z.union([
    z.string().datetime(),
    z.date(),
    z.object({ toDate: z.function().returns(z.date()) })
  ]).transform((value) => {
    if (typeof value === "string") return new Date(value);
    if (value instanceof Date) return value;
    return value.toDate();
  }),
  timeoutMs: z.number().int().min(1_000).max(45_000),
  maxOutputTokens: z.number().int().min(128).max(8_192),
  workflows: z.object({
    adaptiveCareerIntake: z.boolean(),
    cookedDiagnostic: z.boolean(),
    questPlan: z.boolean(),
    proofQualityCheck: z.boolean(),
    progressSummary: z.boolean()
  })
});

type AIRuntimePolicy = z.infer<typeof runtimePolicySchema>;

export type AIRuntimePolicyDecision = {
  enabled: boolean;
  policyRevision: string;
  timeoutMs: number;
  maxOutputTokens: number;
  fallbackReason: "policy" | null;
};

export type AIRuntimePolicyReader = {
  read: (kind: WorkflowKind, now: Date) => Promise<AIRuntimePolicyDecision>;
};

export function createCachedAIRuntimePolicyReader(input: {
  readDocument: () => Promise<unknown>;
  cacheTTLms: number;
}): AIRuntimePolicyReader {
  let cached: AIRuntimePolicy | null = null;
  let cachedAt = 0;

  return {
    async read(kind, now) {
      let policy = cached;
      if (!policy || now.getTime() - cachedAt >= input.cacheTTLms || policy.validUntil <= now) {
        try {
          const parsed = runtimePolicySchema.safeParse(await input.readDocument());
          policy = parsed.success && parsed.data.validUntil > now ? parsed.data : null;
          cached = policy;
          cachedAt = policy ? now.getTime() : 0;
        } catch {
          policy = null;
          cached = null;
          cachedAt = 0;
        }
      }

      if (!policy) return unavailableDecision();
      const workflowEnabled = isLiveWorkflowKind(kind) && policy.workflows[kind];
      return {
        enabled: policy.enabled && workflowEnabled,
        policyRevision: policy.revision,
        timeoutMs: policy.timeoutMs,
        maxOutputTokens: policy.maxOutputTokens,
        fallbackReason: policy.enabled && workflowEnabled ? null : "policy"
      };
    }
  };
}

export function adminAIRuntimePolicyReader(): AIRuntimePolicyReader {
  return createCachedAIRuntimePolicyReader({
    readDocument: async () => {
      const snapshot = await getFirestore().doc("_serverConfig/aiRuntimePolicy").get();
      return snapshot.exists ? snapshot.data() : null;
    },
    cacheTTLms: 30_000
  });
}

function unavailableDecision(): AIRuntimePolicyDecision {
  return {
    enabled: false,
    policyRevision: "unavailable",
    timeoutMs: 10_000,
    maxOutputTokens: 1200,
    fallbackReason: "policy"
  };
}

function isLiveWorkflowKind(kind: WorkflowKind): kind is typeof LIVE_WORKFLOW_KINDS[number] {
  return (LIVE_WORKFLOW_KINDS as readonly string[]).includes(kind);
}
