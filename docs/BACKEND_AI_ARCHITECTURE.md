# Backend And AI Architecture

This document defines the recommended Firebase, Genkit, and OpenAI backend foundation for OpenLARP V0. It starts from the current merged `main` branch, where OpenLARP is a local-first SwiftUI app with deterministic local state, local proof attachments, local persistence, and test-covered quest cadence.

## Decision Summary

- Use Firebase first for V0: Firebase Auth, Firestore, Firebase Storage, Cloud Functions for Firebase, Firebase Analytics, and Genkit.
- Use two Firebase projects now: one dev project and one prod project. Firebase recommends separate projects per environment, and V0 will handle sensitive career proof that should not be mixed with development data.
- Use Firestore location `nam5` for the default database and Cloud Functions region `us-central1`. The first expected beta audience is US-centered, `nam5` gives higher availability than a single region, and Firebase maps `nam5`/US multi-region data sources to `us-central1` functions.
- Use Firebase Auth with anonymous sign-in first, then link to Sign in with Apple before cloud sync becomes a beta requirement. This keeps first-run friction low while still protecting user-owned data with `request.auth.uid`.
- Keep all LLM calls on the backend. The iOS app must never hold an OpenAI API key or call OpenAI directly.
- Use Genkit flows behind callable Cloud Functions for cooked diagnostics, quest generation, proof quality checks, and progress summaries.
- Use OpenAI as the first model provider through a provider boundary. The provider model ID must be configuration, not hard-coded product logic.
- Keep the current local engine as the offline fallback and migration source. Cloud is added as sync and AI infrastructure, not as a rewrite of the app loop.
- Do not add Cloud Run, RevenueCat, payments, community, Android, job search, autonomous agents, or production subscriptions in this architecture step.

## Official References Checked

- Firebase project environment guidance: <https://firebase.google.com/docs/projects/dev-workflows/general-best-practices>
- Multiple Firebase projects on Apple platforms: <https://firebase.google.com/docs/projects/multiprojects>
- Firebase Auth anonymous accounts: <https://firebase.google.com/docs/auth/ios/anonymous-auth>
- Firebase Auth Sign in with Apple: <https://firebase.google.com/docs/auth/ios/apple>
- Firestore data model: <https://firebase.google.com/docs/firestore/data-model>
- Firestore security rules structure: <https://firebase.google.com/docs/firestore/security/rules-structure>
- Firestore locations: <https://firebase.google.com/docs/firestore/locations>
- Firebase Storage security rules: <https://firebase.google.com/docs/storage/security>
- Cloud Functions locations: <https://firebase.google.com/docs/functions/locations>
- Genkit on callable Cloud Functions: <https://firebase.google.com/docs/functions/oncallgenkit>
- Genkit flows and Zod schemas: <https://genkit.dev/docs/flows>
- Genkit OpenAI plugin: <https://genkit.dev/docs/plugins/openai>
- Firebase Analytics events on iOS: <https://firebase.google.com/docs/analytics/ios/events>
- OpenAI Structured Outputs: <https://developers.openai.com/api/docs/guides/structured-outputs>
- OpenAI Safety Best Practices: <https://developers.openai.com/api/docs/guides/safety-best-practices>
- OpenAI API deployment checklist: <https://developers.openai.com/api/docs/guides/deployment-checklist>
- OpenAI production best practices: <https://developers.openai.com/api/docs/guides/production-best-practices>

## Current Local State To Preserve

The cloud model should map directly to the current local structures:

- `CareerGoal`: current status, target role, timeline, background, existing proof, confidence, biggest blocker.
- `CookedDiagnostic`: score, label, main gap, strongest signal, fastest fix, readiness baseline.
- `Quest`: day, title, purpose, time estimate, difficulty, gap, proof requirement, XP reward, steps, status.
- `ProofSubmission` and `ProofRecord`: kind, text, link, attachments, submission date, quality result.
- `QualityCheckResult`: accepted flag, quality score, label, reason, improvement, XP earned, readiness delta.
- `ProgressState`: XP, XP goal, streak count, completed quest count, proof count, badges, readiness, recent proof.
- `DailyCadenceState`, `SkippedTodayState`, and `MissedDayRecoveryState`: day locking, skip, and recovery behavior.
- Local proof image storage under app-private `ProofAttachments/`.

The backend should not collapse this into a generic chat history. OpenLARP remains quest-first.

## Firebase Project Structure

Use two projects:

- Dev project display name: `OpenLARP Dev`
- Prod project display name: `OpenLARP Prod`

Recommended project ID prefixes:

- `openlarp-dev`
- `openlarp-prod`

The exact project IDs can differ if those IDs are unavailable. Keep the names obvious and never point debug builds at prod.

Recommended Firebase apps:

- Dev iOS app for debug/internal builds.
- Prod iOS app for TestFlight/App Store builds.
- Web app only when the waitlist or creator application site is being built.

Apple config approach:

- Keep `GoogleService-Info.plist` files out of Git until the team decides how to manage environment config safely.
- Use separate Xcode build configurations or targets for dev/prod Firebase config.
- In the first backend PR, prefer a checked-in sample config manifest that names required files and paths, while real plist files remain local or are injected by CI later.

## Region Recommendation

Use:

- Firestore: `nam5`
- Firebase Storage default bucket: align with the Firebase project's default bucket in the same US multi-region posture when available.
- Cloud Functions: `us-central1`
- Callable functions from iOS: initialize the Functions client with `us-central1`.

Why:

- Firestore location cannot be changed after creation.
- `nam5` is a US multi-region location with higher availability than a regional database.
- Firebase Functions docs recommend colocating functions with Firestore and Storage data sources; `nam5` maps to `us-central1` as the nearest functions region.
- The likely first beta audience is US-centered college students, new grads, and early-career users.

If the founder later chooses an EU-first privacy posture, create a new EU project before real beta data is collected. Do not migrate regions casually after users have uploaded proof.

## Auth Approach For V0

Start with anonymous Firebase Auth at first launch. Link that anonymous account to Sign in with Apple before enabling cross-device sync or cloud proof recovery.

User experience:

- First run: user can start goal setup without creating a visible account.
- Before cloud migration or cloud proof upload: silently create an anonymous Firebase user if one does not exist.
- Before cross-device restore: prompt the user to link Sign in with Apple.
- Later account recovery: support Sign in with Apple as the first permanent provider.

Why:

- Anonymous Auth gives a real `uid` for Firestore and Storage rules with low onboarding friction.
- Firebase supports linking anonymous accounts to permanent providers so existing protected data can remain under the same account.
- Sign in with Apple is the best first permanent provider for an iOS-first app.

Do not add email/password, Google sign-in, username/password screens, or social account UI in V0 unless beta testing proves Sign in with Apple is blocking users.

## Firestore Data Model

Use a user-owned hierarchy. Keep documents small and use subcollections for proof, quests, and event history.

```text
users/{uid}
  activeGoalId: string
  createdAt: timestamp
  updatedAt: timestamp
  authState: "anonymous" | "linkedApple"
  schemaVersion: 1

users/{uid}/settings/privacy
  memoryEnabled: boolean
  sharePrivateDetailsByDefault: false
  analyticsOptOut: boolean
  updatedAt: timestamp

users/{uid}/goals/{goalId}
  currentStatus: "student" | "newGrad" | "careerSwitcher" | "unemployed" | "employed"
  targetRole: string
  timeline: string
  background: string
  existingProof: string
  confidence: integer
  biggestBlocker: string
  status: "active" | "archived"
  createdAt: timestamp
  updatedAt: timestamp
  schemaVersion: 1

users/{uid}/goals/{goalId}/diagnostics/{diagnosticId}
  cookedDiagnostic: CookedDiagnosticResult
  source: "ai" | "localFallback"
  schemaVersion: "cooked_diagnostic.v1"
  model: string
  promptVersion: string
  createdAt: timestamp

users/{uid}/goals/{goalId}/questPlans/{planId}
  horizonDays: integer
  status: "active" | "archived"
  createdAt: timestamp
  updatedAt: timestamp

users/{uid}/goals/{goalId}/quests/{questId}
  planId: string
  day: integer
  title: string
  purpose: string
  timeEstimateMinutes: integer
  difficulty: "starter" | "balanced" | "spicy" | "review" | "adaptive"
  gap: "targetClarity" | "proofStrength" | "confidence" | "consistency" | "networking"
  proofRequired: string
  xpReward: integer
  steps: string[]
  status: "locked" | "available" | "inProgress" | "completed" | "skipped"
  availableOnLocalDate: string
  startedAt: timestamp | null
  completedAt: timestamp | null
  skippedAt: timestamp | null
  createdAt: timestamp
  updatedAt: timestamp

users/{uid}/goals/{goalId}/proof/{proofId}
  questId: string
  questTitle: string
  kind: "proof" | "selfReport"
  text: string
  link: string
  attachments: ProofAttachmentMetadata[]
  submittedAt: timestamp
  quality: ProofQualityResult | null
  visibility: "private"
  schemaVersion: 1

users/{uid}/goals/{goalId}/progress/current
  xp: integer
  xpGoal: integer
  completedQuestCount: integer
  proofCount: integer
  readiness: ReadinessMetrics
  updatedAt: timestamp

users/{uid}/goals/{goalId}/progressSnapshots/{snapshotId}
  readiness: ReadinessMetrics
  xp: integer
  proofCount: integer
  completedQuestCount: integer
  summary: ProgressSummaryResult | null
  createdAt: timestamp

users/{uid}/goals/{goalId}/streak/current
  count: integer
  lastCompletedQuestId: string | null
  completedAt: timestamp | null
  nextQuestId: string | null
  nextUnlockLocalDate: string | null
  skippedToday: map | null
  missedDayRecovery: map | null
  updatedAt: timestamp

users/{uid}/goals/{goalId}/badges/{badgeAwardId}
  badgeType: "firstGoal" | "firstProof" | "strongProof" | "threeDayStreak" | "weeklyStreak"
  label: string
  awardedAt: timestamp
  sourceQuestId: string | null
  sourceProofId: string | null

users/{uid}/goals/{goalId}/aiRuns/{runId}
  flowName: "cookedDiagnostic" | "generateQuestPlan" | "checkProofQuality" | "summarizeProgress"
  status: "succeeded" | "failed" | "refused" | "fallback"
  inputRefs: string[]
  outputRef: string | null
  model: string
  provider: "openai"
  schemaVersion: string
  promptVersion: string
  tokenUsage: map | null
  errorKind: string | null
  createdAt: timestamp
```

Implementation notes:

- Store the active goal under `users/{uid}.activeGoalId`.
- Put future goal changes in separate goal documents instead of mutating historical proof into a new target.
- Store raw proof text only in private user-owned paths.
- Store AI run metadata, not raw full prompts, by default.
- Use Firestore server timestamps for cloud-written `createdAt` and `updatedAt`.

## Firebase Storage Model For Proof Attachments

Use this path shape:

```text
users/{uid}/goals/{goalId}/proof/{proofId}/attachments/{attachmentId}.{extension}
```

Each Storage object should have matching Firestore metadata in the proof document:

```json
{
  "id": "attachmentId",
  "storagePath": "users/uid/goals/goalId/proof/proofId/attachments/attachmentId.jpg",
  "originalFileName": "proof.jpg",
  "contentType": "image/jpeg",
  "byteCount": 420000,
  "sha256": "hexEncodedDigest",
  "createdAt": "server timestamp",
  "uploadState": "uploaded"
}
```

Rules:

- Only the owning `uid` can read or write proof attachments.
- Accept only image content types for V0: `image/jpeg`, `image/png`, `image/heic`, and `image/heif`.
- Use a V0 file-size limit of 8 MB per attachment.
- Store no public proof attachments in V0.
- Generate share cards later from sanitized summary data, not from raw proof images.

Upload flow:

1. iOS saves local proof image as it does today.
2. iOS uploads image to Firebase Storage under the authenticated user's path.
3. iOS sends proof metadata and storage paths to a callable function.
4. Function validates ownership and creates the Firestore proof record.
5. Local attachment remains as an offline cache until a successful cloud sync marker is stored.

## Cloud Functions Layout

Use TypeScript Cloud Functions for Firebase. Keep codebases narrow at first.

```text
functions/
  package.json
  tsconfig.json
  src/
    index.ts
    config/
      regions.ts
      models.ts
    callable/
      authUserBootstrap.ts
      confirmGoal.ts
      startQuest.ts
      skipQuest.ts
      submitProof.ts
      claimProofResult.ts
      migrateLocalState.ts
    ai/
      genkit.ts
      provider.ts
      schemas/
        cookedDiagnostic.ts
        questGeneration.ts
        proofQualityCheck.ts
        progressSummary.ts
      flows/
        cookedDiagnosticFlow.ts
        questGenerationFlow.ts
        proofQualityCheckFlow.ts
        progressSummaryFlow.ts
    repositories/
      usersRepository.ts
      goalsRepository.ts
      questsRepository.ts
      proofRepository.ts
      progressRepository.ts
    domain/
      cadence.ts
      xp.ts
      badges.ts
      safety.ts
    logging/
      aiRunLogger.ts
      analyticsEvents.ts
```

Callable function responsibilities:

- `authUserBootstrap`: create `users/{uid}` and default settings after auth.
- `confirmGoal`: validate goal input, write goal, run diagnostic flow, create quest plan, set active goal.
- `startQuest`: move available quest to in progress.
- `skipQuest`: apply skip/recovery rules server-side.
- `submitProof`: validate proof metadata, run proof quality flow, write proof record, update progress/streak/badges.
- `claimProofResult`: if the product keeps an explicit claim step, make the final XP/progress update server-side.
- `migrateLocalState`: one-time upload of current local V0 state into cloud documents.

Critical state updates should be server-side. The client can read its own docs, upload its own attachments, and submit actions, but XP, streak, readiness, badges, and AI output should be written by functions.

## Genkit Flow Layout

Use Genkit flows wrapped with `onCallGenkit` only for AI jobs. Non-AI state transitions can remain normal callable functions.

Flows:

- `cookedDiagnosticFlow`
  - Input: current user goal and minimal background.
  - Output: `CookedDiagnosticResult`.
  - Writes: diagnostic document and AI run metadata.

- `questGenerationFlow`
  - Input: goal, diagnostic, current progress, and recent proof summaries.
  - Output: seven-day quest plan.
  - Writes: quest plan and quest docs.

- `proofQualityCheckFlow`
  - Input: quest, proof text, link metadata, attachment metadata, and user self-report kind.
  - Output: `ProofQualityResult`.
  - Writes: proof quality, progress delta, badge candidates.

- `progressSummaryFlow`
  - Input: goal, diagnostic, recent proof, progress metrics, streak state.
  - Output: `ProgressSummaryResult`.
  - Writes: progress snapshot summary.

Genkit rules:

- Use Zod schemas as the source of truth in TypeScript.
- Generate or mirror JSON Schema from the same Zod objects for OpenAI structured output calls.
- Version every flow schema, for example `proof_quality_check.v1`.
- Store prompt versions in code and AI run metadata.
- Treat a model refusal or schema validation failure as a recoverable fallback state.

## LLM Provider Boundary

The provider boundary must keep OpenAI replaceable without changing product state.

Recommended interface:

```ts
type LLMTask =
  | "cookedDiagnostic"
  | "questGeneration"
  | "proofQualityCheck"
  | "progressSummary";

interface LLMProvider {
  generateStructured<TInput, TOutput>(args: {
    task: LLMTask;
    input: TInput;
    outputSchemaName: string;
    outputSchema: unknown;
    promptVersion: string;
    safetyIdentifier: string;
    maxOutputTokens: number;
  }): Promise<{
    output: TOutput;
    model: string;
    tokenUsage?: Record<string, number>;
    refusal?: string;
  }>;
}
```

Provider decisions:

- First provider: OpenAI.
- API surface: Responses API when calling OpenAI directly from the provider, because OpenAI positions it as the primary current API for model responses.
- Output mode: Structured Outputs with `json_schema` and `strict: true` when direct OpenAI calls are used.
- Model config: keep per-task model IDs in environment-backed config. Start with the current cost/latency-appropriate OpenAI mini model available to the account, and reserve the strongest current model for evaluation or hard cases.
- Safety identifier: send a stable, privacy-preserving hash of the Firebase UID as `safety_identifier`.
- Secrets: store OpenAI keys in Cloud Secret Manager through Firebase Functions secrets. Never commit or ship OpenAI keys in iOS.
- No model-created writes directly to Firestore. All AI output goes through schema validation and domain validation before writes.

## AI Safety Boundaries

Every AI flow must obey these hard product rules:

- Do not invent employers, schools, certificates, job titles, dates, projects, ownership claims, outcomes, or credentials.
- Do not tell users to pretend a draft, plan, or private exercise is public proof.
- Do not claim proof verifies facts the system cannot verify.
- Do not expose private proof details in share-card text.
- Do not send, publish, message, apply, or contact anyone externally.
- Keep tone direct and playful, but not cruel.

Fallback behavior:

- If AI fails, use the local deterministic engine logic where possible.
- If AI refuses or output fails schema validation, show a calm fallback and keep the user moving.
- Weak proof must produce an improvement path, not a dead end.

## Strict JSON Schemas

These are the V0 output contracts. In implementation, the TypeScript Zod definitions should be the source of truth and these JSON Schemas should be generated or checked from those definitions.

### Cooked Diagnostic

Schema name: `cooked_diagnostic.v1`

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "score",
    "label",
    "readinessBaseline",
    "mainGap",
    "strongestSignal",
    "fastestFix",
    "riskFactors",
    "firstQuestSeed",
    "safetyFlags"
  ],
  "properties": {
    "score": { "type": "integer", "minimum": 0, "maximum": 100 },
    "label": {
      "type": "string",
      "enum": ["notCooked", "lightlyCooked", "mediumCooked", "veryCooked"]
    },
    "readinessBaseline": {
      "type": "object",
      "additionalProperties": false,
      "required": ["overall", "proofStrength", "confidence", "consistency"],
      "properties": {
        "overall": { "type": "integer", "minimum": 0, "maximum": 100 },
        "proofStrength": { "type": "integer", "minimum": 0, "maximum": 100 },
        "confidence": { "type": "integer", "minimum": 0, "maximum": 100 },
        "consistency": { "type": "integer", "minimum": 0, "maximum": 100 }
      }
    },
    "mainGap": { "type": "string", "minLength": 8, "maxLength": 220 },
    "strongestSignal": { "type": "string", "minLength": 8, "maxLength": 220 },
    "fastestFix": { "type": "string", "minLength": 8, "maxLength": 220 },
    "riskFactors": {
      "type": "array",
      "minItems": 1,
      "maxItems": 5,
      "items": { "type": "string", "minLength": 4, "maxLength": 140 }
    },
    "firstQuestSeed": {
      "type": "object",
      "additionalProperties": false,
      "required": ["gap", "actionTheme", "proofType"],
      "properties": {
        "gap": {
          "type": "string",
          "enum": ["targetClarity", "proofStrength", "confidence", "consistency", "networking"]
        },
        "actionTheme": { "type": "string", "minLength": 4, "maxLength": 120 },
        "proofType": {
          "type": "string",
          "enum": ["text", "link", "screenshot", "photo", "selfReport"]
        }
      }
    },
    "safetyFlags": {
      "type": "array",
      "maxItems": 6,
      "items": {
        "type": "string",
        "enum": [
          "overclaimingRisk",
          "fakeCredentialRisk",
          "privacySensitive",
          "needsMoreContext",
          "none"
        ]
      }
    }
  }
}
```

### Quest Generation

Schema name: `quest_generation.v1`

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["planTitle", "quests"],
  "properties": {
    "planTitle": { "type": "string", "minLength": 4, "maxLength": 80 },
    "quests": {
      "type": "array",
      "minItems": 7,
      "maxItems": 7,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "day",
          "title",
          "purpose",
          "timeEstimateMinutes",
          "difficulty",
          "gap",
          "proofRequired",
          "xpReward",
          "steps",
          "ethicsCheck"
        ],
        "properties": {
          "day": { "type": "integer", "minimum": 1, "maximum": 7 },
          "title": { "type": "string", "minLength": 6, "maxLength": 90 },
          "purpose": { "type": "string", "minLength": 12, "maxLength": 220 },
          "timeEstimateMinutes": { "type": "integer", "minimum": 5, "maximum": 90 },
          "difficulty": {
            "type": "string",
            "enum": ["starter", "balanced", "spicy", "review", "adaptive"]
          },
          "gap": {
            "type": "string",
            "enum": ["targetClarity", "proofStrength", "confidence", "consistency", "networking"]
          },
          "proofRequired": { "type": "string", "minLength": 6, "maxLength": 180 },
          "xpReward": { "type": "integer", "minimum": 50, "maximum": 250 },
          "steps": {
            "type": "array",
            "minItems": 3,
            "maxItems": 5,
            "items": { "type": "string", "minLength": 4, "maxLength": 140 }
          },
          "ethicsCheck": {
            "type": "object",
            "additionalProperties": false,
            "required": ["requiresOnlyRealExperience", "bannedClaims"],
            "properties": {
              "requiresOnlyRealExperience": { "type": "boolean", "enum": [true] },
              "bannedClaims": {
                "type": "array",
                "items": {
                  "type": "string",
                  "enum": [
                    "fakeEmployer",
                    "fakeSchool",
                    "fakeCertificate",
                    "fakeTitle",
                    "fakeDate",
                    "fakeProject",
                    "fakeOwnership",
                    "fakeOutcome"
                  ]
                }
              }
            }
          }
        }
      }
    }
  }
}
```

### Proof Quality Check

Schema name: `proof_quality_check.v1`

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "isAccepted",
    "qualityScore",
    "label",
    "reason",
    "improvement",
    "xpEarned",
    "readinessDelta",
    "detectedSignals",
    "limitations",
    "nextAction"
  ],
  "properties": {
    "isAccepted": { "type": "boolean" },
    "qualityScore": { "type": "integer", "minimum": 0, "maximum": 100 },
    "label": {
      "type": "string",
      "enum": ["strongProof", "usefulStart", "needsStrongerProof", "selfReportOnly", "cannotEvaluate"]
    },
    "reason": { "type": "string", "minLength": 8, "maxLength": 240 },
    "improvement": { "type": "string", "minLength": 8, "maxLength": 220 },
    "xpEarned": { "type": "integer", "minimum": 0, "maximum": 250 },
    "readinessDelta": { "type": "integer", "minimum": 0, "maximum": 10 },
    "detectedSignals": {
      "type": "array",
      "maxItems": 6,
      "items": {
        "type": "string",
        "enum": [
          "specificArtifact",
          "validLink",
          "imageAttached",
          "clearAction",
          "targetRoleConnection",
          "reflectionOnly",
          "insufficientDetail"
        ]
      }
    },
    "limitations": {
      "type": "array",
      "maxItems": 4,
      "items": { "type": "string", "minLength": 4, "maxLength": 140 }
    },
    "nextAction": {
      "type": "object",
      "additionalProperties": false,
      "required": ["type", "title"],
      "properties": {
        "type": {
          "type": "string",
          "enum": ["claimXp", "improveProof", "acceptLowerXp", "tryAgainLater"]
        },
        "title": { "type": "string", "minLength": 4, "maxLength": 80 }
      }
    }
  }
}
```

### Progress Summary

Schema name: `progress_summary.v1`

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "headline",
    "summary",
    "readiness",
    "strongestImprovement",
    "weakestArea",
    "proofHighlights",
    "recommendedNextQuestTheme",
    "privacySafeShareText"
  ],
  "properties": {
    "headline": { "type": "string", "minLength": 4, "maxLength": 80 },
    "summary": { "type": "string", "minLength": 20, "maxLength": 300 },
    "readiness": {
      "type": "object",
      "additionalProperties": false,
      "required": ["overall", "proofStrength", "confidence", "consistency"],
      "properties": {
        "overall": { "type": "integer", "minimum": 0, "maximum": 100 },
        "proofStrength": { "type": "integer", "minimum": 0, "maximum": 100 },
        "confidence": { "type": "integer", "minimum": 0, "maximum": 100 },
        "consistency": { "type": "integer", "minimum": 0, "maximum": 100 }
      }
    },
    "strongestImprovement": {
      "type": "string",
      "enum": ["targetClarity", "proofStrength", "confidence", "consistency", "networking"]
    },
    "weakestArea": {
      "type": "string",
      "enum": ["targetClarity", "proofStrength", "confidence", "consistency", "networking"]
    },
    "proofHighlights": {
      "type": "array",
      "maxItems": 3,
      "items": { "type": "string", "minLength": 4, "maxLength": 140 }
    },
    "recommendedNextQuestTheme": { "type": "string", "minLength": 4, "maxLength": 140 },
    "privacySafeShareText": { "type": "string", "minLength": 4, "maxLength": 160 }
  }
}
```

## Privacy And Memory Controls

V0 memory means structured app memory, not a free-form long-term chat memory.

Store:

- Goal, diagnostic, quests, proof receipts, progress, streak, badges, and privacy settings.
- AI output needed to show the product state.
- AI run metadata needed for debugging and cost tracking.

Do not store by default:

- Raw full prompts with all user background and proof text.
- Raw model reasoning.
- Memory-off chat content.
- Public share-card details that expose private career insecurity, schools, employers, proof URLs, or screenshots.

Controls:

- `memoryEnabled` gates future long-term chat memory. For V0, it controls whether optional helper chat context can be saved later.
- `sharePrivateDetailsByDefault` must remain false.
- Add account deletion and data export before a broad public beta, even if implemented as support-assisted tooling first.
- Deleting a goal should archive or delete its nested proof according to the user-facing choice. Avoid silent partial deletion because Firestore parent deletion does not automatically delete subcollections.

## Security Rules Approach

Firestore:

- Default deny.
- Allow authenticated users to read their own `users/{uid}` tree.
- Allow client writes only for low-risk user-owned inputs: profile/settings drafts and goal intake before confirmation.
- Require Cloud Functions for writes that affect diagnostic output, quest plan, quest status, proof quality, XP, readiness, streaks, and badges.
- Use explicit nested subcollection rules. Firestore rules for a parent document do not automatically secure subcollections.
- Use rules version 2 if collection group queries are introduced later.

Storage:

- Default deny.
- Allow only authenticated user-private proof paths.
- Enforce `request.auth.uid == uid`.
- Enforce V0 image MIME types and file-size limits.
- Do not allow public reads for proof attachments.

App Check:

- Enable App Check enforcement on callable Genkit functions before broad beta if it does not materially block TestFlight users.
- Do not depend on App Check as the only security layer. Auth and rules still carry ownership checks.

## Analytics Events

Use Firebase Analytics for product behavior. Do not log raw proof text, target role text, employer names, school names, links, filenames, or attachment paths.

Recommended custom events:

| Event | When | Safe parameters |
|---|---|---|
| `goal_started` | Goal setup starts | `source` |
| `goal_confirmed` | Goal saved | `current_status`, `timeline_bucket` |
| `diagnostic_requested` | AI diagnostic starts | `source` |
| `diagnostic_completed` | Diagnostic returned | `label`, `score_bucket` |
| `quest_started` | Quest enters in progress | `day`, `gap`, `difficulty` |
| `proof_added` | User adds text/link/image locally | `proof_kind`, `attachment_count_bucket` |
| `proof_submitted` | Proof sent to backend | `proof_kind`, `has_link`, `has_attachment` |
| `proof_check_completed` | Quality check returns | `label`, `accepted`, `score_bucket` |
| `xp_claimed` | XP applied | `xp_bucket` |
| `quest_completed` | Quest completed | `day`, `gap` |
| `quest_skipped` | User intentionally skips | `day`, `previous_streak_bucket` |
| `recovery_started` | Missed-day state appears | `missed_days_bucket` |
| `recovery_completed` | User resumes from recovery | `missed_days_bucket` |
| `map_viewed` | Map tab opens | `active_day` |
| `progress_viewed` | Progress tab opens | `readiness_bucket` |
| `proof_archive_viewed` | Proof archive opens | `proof_count_bucket` |
| `share_card_previewed` | Share preview opens | `card_type` |
| `share_card_shared` | User shares or saves | `card_type`, `destination_type` |
| `sync_completed` | Local-to-cloud sync completes | `object_count_bucket` |
| `sync_failed` | Sync fails | `error_kind` |

## Local-First To Cloud Migration

Migration should be reversible and cautious because current V0 users may have valuable local proof.

Phased plan:

1. Add Firebase SDK and anonymous Auth without changing product behavior.
2. Bootstrap `users/{uid}` and privacy settings after auth.
3. Add a sync adapter that maps `OpenLARPState` to Firestore schema version 1.
4. Add `migrateLocalState` callable to validate and write the local state server-side.
5. Upload local attachments to Firebase Storage and update proof metadata only after upload success.
6. Keep local JSON and local attachments as the offline cache after migration.
7. Add cloud reads on app launch. If cloud state exists, hydrate local state from Firestore.
8. Add simple conflict policy for V0: latest server-confirmed action wins, with a user-facing recovery message if local unsynced actions exist.
9. Add a one-time local backup file before first cloud migration.

Migration mapping:

- Local `OpenLARPState.goal` maps to `users/{uid}/goals/{goalId}`.
- Local `diagnostic` maps to `diagnostics/{diagnosticId}` with `source: "localFallback"` if it was generated locally.
- Local `plan` maps to `quests/{questId}`.
- Local `progress` maps to `progress/current`, `streak/current`, `badges/{badgeAwardId}`, and recent proof docs.
- Local `recentProof` maps to `proof/{proofId}`.
- Local `ProofAttachment.localRelativePath` maps to Storage after upload and remains local cache metadata.

## What Remains Local-Only For Now

- Pending proof drafts before submission.
- Local image files until cloud upload confirms.
- Offline cache of `OpenLARPState`.
- Local-only deterministic fallback diagnostic, quest generation, proof check, XP, cadence, skip, and recovery behavior.
- Agent helper draft text, especially when memory is off.
- UI-only state such as selected tab, open sheets, and local form drafts.

## What Should Not Be Built Yet

- RevenueCat, App Store payments, subscriptions, paywalls, or student-discount logic.
- Cloud Run.
- Real autonomous background agents.
- Job search, LinkedIn integration, auto-apply, external messaging, or job-board scraping.
- Android or full web app.
- Community feed, public profiles, school dashboards, employer dashboards, or human review queues.
- Resume builder, interview prep, or agent search.
- Complex multi-goal planning beyond storing archived goals.
- Public proof pages or public proof attachments.

## First Backend Implementation PR

Recommended first PR title:

`Add Firebase foundation for cloud-backed V0`

Scope:

- Create a feature branch from `main`.
- Add Firebase iOS SDK dependencies for Auth, Firestore, Storage, Functions, Analytics, and App Check only if App Check setup is practical in dev.
- Add dev/prod Firebase config loading structure without committing real secrets or private plist files.
- Add Firebase initialization in the SwiftUI app with a small adapter that does not replace `OpenLARPStore`.
- Add anonymous Auth bootstrap and a user settings document write in dev.
- Add initial `firebase.json`, Firestore rules, Storage rules, and emulator config.
- Add TypeScript `functions/` skeleton with callable `authUserBootstrap`.
- Add emulator tests or rules tests for basic owner-only Firestore/Storage access.
- Keep current local engine behavior as the app source of truth.
- Do not add OpenAI calls in this first PR.

Validation for that PR:

- Existing iOS tests pass.
- Unsigned iOS build passes.
- Firebase emulators start for Auth, Firestore, Storage, and Functions.
- Rules tests prove users cannot read or write another user's private data.
- Secret scan proves no API keys, plist secrets, tokens, private keys, or local environment files were committed.

## Exact Next Prompt For Firebase Setup

Use this prompt for the next implementation turn:

```text
Use the current merged main branch of OpenLARP as source of truth.

Create the Firebase foundation PR only. Before creating any Firebase project, show me the exact project display names, proposed project IDs, Firebase services, Firestore location, Functions region, Auth providers, and files that will be added. Wait for my confirmation before project creation.

Use official Firebase MCP/docs for all setup. Create separate Firebase projects for dev and prod. Use Firestore location nam5 and Cloud Functions region us-central1 unless official docs or Firebase console constraints block that. Enable Firebase Auth with Anonymous and Sign in with Apple. Initialize Firestore, Storage, Cloud Functions for Firebase, Analytics, and local emulators. Do not add OpenAI keys or AI calls yet. Do not add RevenueCat, payments, auth providers beyond Anonymous and Apple, Cloud Run, Android, community, job search, or subscriptions.

Implement the first PR as:
- Firebase config loading structure for iOS without committing private plist secrets.
- Firebase SDK dependencies needed for Auth, Firestore, Storage, Functions, Analytics, and optional App Check.
- Anonymous auth bootstrap that creates users/{uid} and users/{uid}/settings/privacy.
- Initial Firestore and Storage rules with owner-only access.
- TypeScript functions skeleton with authUserBootstrap.
- Emulator/rules validation where practical.

Run iOS tests, unsigned iOS build, Firebase rules/emulator checks, git diff --check, and a secret scan. Commit, push, open a draft PR, and keep the working tree clean.
```

## Concise Recommendation

Build Firebase foundation first, then add AI. The next PR should prove account bootstrap, user-owned Firestore paths, private Storage paths, emulator validation, and safe config handling. After that is stable, add Genkit and OpenAI flows one at a time behind callable functions, starting with the cooked diagnostic because it creates the user's baseline and first quest plan.
