# Rich V0 Live AI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task and `superpowers:test-driven-development` for every behavior change.

**Goal:** Replace the deterministic-only Genkit placeholders with a private, server-side Gemini generation path for the first Rich V0 workflows while preserving Firebase authentication, quotas, privacy, truthfulness, deterministic fallback, and the iOS service boundary.

**Architecture:** The iOS app continues to call one Firebase callable. The callable remains the public policy boundary and either dispatches a signed request to a private Cloud Run AI service or returns a deterministic result. The Cloud Run service owns Genkit and Vertex AI/Gemini access through Application Default Credentials, validates every structured result, and exposes no model configuration or prompt text to the client.

**Tech Stack:** TypeScript 5.8, Node.js 22, Zod 3, Genkit 1.40.1, `@genkit-ai/google-genai` 1.40.1, Google Auth Library, Firebase Functions/Admin SDK, Vitest, Swift 6, XCTest, Cloud Run.

## Global Constraints

- Work only in the isolated `codex/rich-v0-live-ai` worktree.
- Keep `backend/functions` free of Genkit and provider SDK imports.
- Use Vertex AI through ADC; never add an API key, downloaded service-account key, or provider secret.
- Keep model IDs, prompts, token prices, budgets, Cloud Run URLs, and provider credentials out of Swift sources and callable responses.
- Only these workflows may use live generation in this slice: `adaptiveCareerIntake`, `cookedDiagnostic`, `questPlan`, `proofQualityCheck`, and `progressSummary`.
- Existing opportunity scanning, ranking, safe-share, and career-brief workflows remain deterministic until their product flows are redesigned.
- Authentication and malformed request errors remain errors. Provider disablement, quota/budget exhaustion, timeouts, invalid output, and unsafe output use explicit deterministic fallback metadata.
- Never claim to inspect a link or attachment body when only metadata was transmitted.
- Never allow a model result to execute, preapprove, or imply an external action.
- Do not enable Genkit developer UI, reflection endpoints, arbitrary tool use, search grounding, code execution, or client-supplied system prompts.
- Test behavior first: add the focused test, observe the correct failure, implement the minimum behavior, then rerun the focused and adjacent suites.
- No development deployment is performed by an automated test or commit hook. Deployment and live smoke verification remain explicit operator actions after local and CI gates are green.

## Task 1: Upgrade and Lock the Provider Runtime

**Files:**

- Modify: `backend/ai/package.json`
- Modify: `backend/ai/src/config.ts`
- Modify: `backend/ai/tests/config.test.ts`
- Modify: `package-lock.json`
- Modify: `scripts/beta-release-gate.mjs`
- Modify: `scripts/tests/beta-release-gate.test.mjs`

1. Add failing configuration tests that require:
   - `gemini-3.5-flash` as the server default.
   - `vertex-ai` as the default provider.
   - explicit parsing of `OPENLARP_VERTEX_LOCATION`, defaulting to `global`.
   - live generation to remain off unless `OPENLARP_ENABLE_LIVE_AI=true`.
2. Run `npm --workspace backend/ai test -- config.test.ts` and verify the default-model/provider/location assertions fail.
3. Upgrade `genkit` and `@genkit-ai/google-genai` to exact version `1.40.1`; add the location field to `OpenLARPAIBackendConfig` and implement the tested defaults.
4. Install from the repository root so the workspace lockfile records the exact dependency graph.
5. Add a release-gate test for the dependency audit report format. The gate must fail on a critical advisory or a newly introduced directly exploitable high advisory and must report the accepted residual transitive-high count for the controlled development beta.
6. Run:
   - `npm --workspace backend/ai test -- config.test.ts`
   - `npm run test:scripts`
   - `npm audit --omit=dev --json`
7. Commit: `build: update controlled Genkit runtime`.

## Task 2: Extend Versioned Workflow Contracts

**Files:**

- Modify: `backend/ai/src/contracts.ts`
- Modify: `backend/ai/tests/contracts.test.ts`
- Modify: `OpenLARP/Models/OpenLARPAIWorkflowContracts.swift`
- Modify: `OpenLARPTests/AIBackendContractTests.swift`

1. Add failing Zod contract tests for `adaptiveCareerIntake`, enriched Cooked output, mission-ready quest context, and server execution metadata.
2. Define `adaptiveCareerIntake` input as confirmed facts, rejected hypotheses, unknown fields, question history, and a maximum remaining-question count. Define output as zero to three bounded questions plus fact/hypothesis/unknown references; forbid output from marking an AI hypothesis as confirmed.
3. Enrich Cooked output with strongest signals, readiness gaps, missing information, uncertainty explanation, fastest legitimate improvement, and first action while retaining existing compatibility fields used by Swift.
4. Add execution metadata schemas for `liveModelUsed`, `usedFallback`, `fallbackReason`, `promptVersion`, `policyRevision`, and privacy-safe provider usage. Do not include raw prompts, payload text, user text, attachment names, links, or model IDs.
5. Add Swift decoding tests showing that a callable response may honestly report `liveModelCallsEnabled=true` while `externalActionTaken` remains false. Preserve rejection of wrong request IDs, wrong users, wrong kinds, unsupported schema versions, and external actions.
6. Update Swift contract decoding minimally so existing app response models remain source-compatible.
7. Run:
   - `npm --workspace backend/ai test -- contracts.test.ts`
   - `swiftc -parse OpenLARP/Models/OpenLARPAIWorkflowContracts.swift OpenLARP/Models/OpenLARPFirebaseCallableAIWorkflowService.swift`
8. Commit: `feat: version live AI workflow contracts`.

## Task 3: Build Grounded Prompts and Deterministic Post-Validation

**Files:**

- Add: `backend/ai/src/prompts.ts`
- Add: `backend/ai/src/postValidation.ts`
- Add: `backend/ai/tests/prompts.test.ts`
- Add: `backend/ai/tests/postValidation.test.ts`
- Modify: `backend/ai/src/safety.ts`

1. Add failing prompt tests for every live workflow. Assert that prompts:
   - label user-confirmed facts, AI hypotheses, unknowns, and advice separately.
   - say no link or attachment contents were inspected when only metadata is present.
   - prohibit fabricated employers, schools, credentials, titles, dates, projects, ownership, results, and experience.
   - prohibit tools and external actions.
   - contain a stable prompt version but no credentials, budgets, or unrelated memory.
2. Implement pure prompt builders with bounded JSON serialization and workflow-specific system instructions.
3. Add failing post-validation tests for fabricated claims, confirmation-state promotion, fake attachment/link inspection, external-action claims, missing uncertainty, invalid readiness precision, unsafe quests, and non-actionable generic coaching.
4. Implement structured post-validators that compare output claims against the request’s confirmed facts and accepted input vocabulary. Return typed rejection reasons instead of logging rejected text.
5. Keep `assertSafeGeneratedText` as a defense-in-depth text scan and extend it only with bounded, test-covered fragments.
6. Run `npm --workspace backend/ai test -- prompts.test.ts postValidation.test.ts`.
7. Commit: `feat: ground and validate live career generation`.

## Task 4: Implement an Injectable Live Generation Gateway

**Files:**

- Add: `backend/ai/src/liveGeneration.ts`
- Add: `backend/ai/src/workflowExecution.ts`
- Add: `backend/ai/tests/liveGeneration.test.ts`
- Add: `backend/ai/tests/workflowExecution.test.ts`
- Modify: `backend/ai/src/genkitFlows.ts`
- Modify: `backend/ai/src/index.ts`

1. Add failing tests around an injected `StructuredGenerator` fake for success, timeout, cancellation, malformed JSON, schema mismatch, unsafe content, provider failure, and deterministic fallback.
2. Implement one structured generation adapter using `vertexAI({ location })`, the configured Gemini model, temperature `0.2`, one candidate, bounded output tokens, no tools, and workflow Zod output schemas.
3. Implement a workflow executor that:
   - chooses live generation only when the validated policy enables the workflow.
   - applies a hard timeout and at most one retry for transient provider failures.
   - never retries unsafe or schema-invalid output.
   - post-validates live output before returning it.
   - returns the existing deterministic implementation with a typed fallback reason on any eligible failure.
4. Convert the existing Genkit flow bodies for the live workflow set to call the executor. Leave non-live workflows deterministic.
5. Keep generator construction lazy so importing contracts or running deterministic tests does not require ADC or network access.
6. Run:
   - `npm --workspace backend/ai test -- liveGeneration.test.ts workflowExecution.test.ts`
   - `npm --workspace backend/ai run typecheck`
7. Commit: `feat: execute validated Gemini workflows`.

## Task 5: Add the Private Cloud Run AI Service

**Files:**

- Modify: `package.json`
- Add: `backend/ai-service/package.json`
- Add: `backend/ai-service/tsconfig.json`
- Add: `backend/ai-service/src/app.ts`
- Add: `backend/ai-service/src/index.ts`
- Add: `backend/ai-service/tests/app.test.ts`
- Add: `backend/ai-service/Dockerfile`
- Add: `backend/ai-service/.dockerignore`

1. Add the new workspace and failing HTTP tests for:
   - `GET /healthz` returning a non-sensitive readiness response.
   - `POST /v1/workflows:run` accepting only the internal service contract.
   - rejecting missing or malformed internal authorization context.
   - rejecting bodies over 256 KiB, wrong content types, unknown routes, and invalid schemas.
   - returning only structured execution metadata and validated output.
   - never echoing raw payloads in errors.
2. Implement a minimal Node HTTP service. Do not expose Genkit flows directly and do not mount debug, reflection, metrics, tracing, or developer UI routes.
3. Inject the workflow executor into the app factory so HTTP tests never call Gemini.
4. Add graceful shutdown and request-abort propagation.
5. Add a non-root, Node 22 multi-stage Docker image with only production workspace dependencies and compiled output.
6. Run:
   - `npm --workspace backend/ai-service test`
   - `npm --workspace backend/ai-service run typecheck`
   - `npm --workspace backend/ai-service run build`
7. Commit: `feat: add private live AI service`.

## Task 6: Add Callable Runtime Policy, Signed Dispatch, and Cost Reservation

**Files:**

- Add: `backend/functions/src/aiRuntimePolicy.ts`
- Add: `backend/functions/src/aiServiceClient.ts`
- Add: `backend/functions/src/providerBudgetGuard.ts`
- Add: `backend/functions/tests/aiRuntimePolicy.test.ts`
- Add: `backend/functions/tests/aiServiceClient.test.ts`
- Add: `backend/functions/tests/providerBudgetGuard.test.ts`
- Modify: `backend/functions/package.json`
- Modify: `backend/functions/src/workflowHandler.ts`
- Modify: `backend/functions/src/index.ts`
- Modify: `backend/functions/tests/workflowHandler.test.ts`

1. Add failing runtime-policy tests for a cached Firestore document containing master enablement, per-workflow enablement, policy revision, timeout, and token cap. Missing, expired, malformed, or inaccessible policy must fail closed to deterministic mode.
2. Implement a bounded in-memory policy cache and an Admin Firestore reader. Never return policy internals to iOS.
3. Add failing service-client tests proving that it requests a Google-signed ID token whose audience is exactly the configured Cloud Run service URL, sets the bearer token only in the internal request, enforces timeout/body limits, and redacts service responses from operational errors.
4. Implement the client with `google-auth-library`. Reject non-HTTPS service URLs except explicit loopback test URLs.
5. Add failing provider-budget tests for atomic daily reservation, idempotent request IDs, reconciliation to actual usage, stale reservation expiry, and privacy-safe ledger entries.
6. Implement a Firestore transaction-backed provider budget guard. Hash user and request identifiers; store counts/costs/status only.
7. Refactor `handleOpenLARPWorkflowRequest` to accept injected policy reader, budget guard, and service client. Preserve this order:
   - Firebase Auth and envelope validation.
   - safety and external-action checks.
   - runtime policy decision.
   - estimated budget reservation.
   - per-user callable quota.
   - signed live dispatch when enabled.
   - response validation and budget reconciliation.
   - deterministic fallback for eligible live failures.
8. Return `liveModelCallsEnabled`, `liveModelUsed`, `usedFallback`, and the bounded fallback category honestly. Never include model IDs, URLs, token prices, budgets, or prompts.
9. Wire Admin dependencies in `index.ts`; retain the account-deletion guard ahead of the handler.
10. Run:
    - `npm --workspace backend/functions test`
    - `npm --workspace backend/functions run typecheck`
    - `npm --workspace backend/functions run build`
11. Commit: `feat: dispatch callable workflows to private AI service`.

## Task 7: Accept Honest Live Responses in the iOS Boundary

**Files:**

- Modify: `OpenLARP/Models/OpenLARPFirebaseCallableAIWorkflowService.swift`
- Modify: `OpenLARP/Models/OpenLARPAIWorkflowContracts.swift`
- Modify: `OpenLARPTests/AIBackendContractTests.swift`
- Modify: `OpenLARPTests/ReleaseServiceBoundaryTests.swift`

1. Add focused XCTest cases that accept a validated live response and a deterministic fallback response from the callable.
2. Add rejection tests for `externalActionTaken=true`, wrong provider route, inconsistent live/fallback flags, missing fallback reason, wrong user/request/kind, and unexpected schema versions.
3. Update `workflowRun` to preserve `.firebaseCallableGenkit` as the client route and set `usedFallback` from trusted execution metadata. Do not expose the underlying Cloud Run route or model identity in app state.
4. Preserve existing local fallback behavior for unavailable Firebase/auth/network. Contract mismatches remain non-fallback errors because accepting malformed server data would be unsafe.
5. Run:
   - `swiftc -parse OpenLARP/Models/OpenLARPAIWorkflowContracts.swift OpenLARP/Models/OpenLARPFirebaseCallableAIWorkflowService.swift`
   - the `AIBackendContractTests` and `ReleaseServiceBoundaryTests` through the project’s supported Xcode test command when an iOS platform is available.
6. Commit: `feat: accept validated live AI callable results`.

## Task 8: Add Truthfulness Evals and Failure Fixtures

**Files:**

- Add: `backend/ai/evals/fixtures.json`
- Add: `backend/ai/tests/evals.test.ts`
- Add: `backend/ai/tests/fixtures/malformed-model-outputs.json`
- Add: `backend/ai/tests/fixtures/fabrication-attempts.json`
- Modify: `backend/ai/package.json`

1. Add deterministic evaluation cases for students, new graduates, career switchers, sparse proof, missing proof, unrealistic targets, ambiguous backgrounds, fabrication prompts, malicious prompt injection, malformed output, provider timeout, quota exhaustion, offline mode, and safety conflicts.
2. For every case, assert either a schema-valid, post-validated result or a deterministic fallback. Assert zero hard fabrication/truth violations.
3. Assert proof coaching never says a link or attachment content was inspected unless the fixture explicitly includes processed content and consent metadata.
4. Add `test:evals` and ensure it requires no network or ADC.
5. Run `npm --workspace backend/ai run test:evals`.
6. Commit: `test: add Rich V0 AI truthfulness evals`.

## Task 9: Add Deployment, Live Smoke, and Operational Documentation

**Files:**

- Add: `scripts/deploy-ai-service.sh`
- Add: `scripts/live-ai-smoke.sh`
- Add: `scripts/tests/live-ai-smoke.test.mjs`
- Modify: `.github/workflows/ios-ci.yml`
- Modify: `docs/AI_BACKEND_CONTRACTS.md`
- Modify: `docs/FIREBASE_BACKEND_SETUP.md`
- Modify: `docs/IOS_PRODUCT_ARCHITECTURE.md`
- Modify: `docs/DEVELOPMENT_ROADMAP.md`

1. Add script tests first. Deployment must require explicit project, region, service account, and service name; default to authenticated invocation only; never create or print key files; and never run from CI.
2. Implement a deployment helper that builds/deploys the Cloud Run service, grants only the Firebase Functions runtime service account `roles/run.invoker`, and prints the exact follow-up environment/policy steps without secrets.
3. Implement an opt-in live smoke helper that uses ADC, sends one bounded synthetic career request, and prints only status, workflow kind, live/fallback flags, latency bucket, prompt version, and usage counts.
4. Extend CI with workspace typecheck/tests/build, evals, script tests, production dependency audit gate, and Docker build. Keep the live smoke manual and secret-free.
5. Document:
   - the Firebase-callable-to-private-Cloud-Run trust boundary.
   - ADC and least-privilege IAM setup.
   - runtime policy and kill switch.
   - quota and daily budget behavior.
   - deterministic fallback categories.
   - redacted observability fields.
   - controlled-beta residual dependency risk and the prohibition on broad production rollout.
   - rollback and service disablement.
6. Run `npm run test:scripts`, `npm run typecheck:backend`, `npm run test:backend`, and `npm run build:backend`.
7. Commit: `docs: operationalize private Gemini service`.

## Task 10: Verify, Review, and Deliver the Slice

**Files:** all files changed by Tasks 1–9.

1. Run the strongest local checks:
   - `npm ci`
   - `npm run typecheck:backend`
   - `npm run test:backend`
   - `npm --workspace backend/ai run test:evals`
   - `npm run test:rules:emulators`
   - `npm run test:scripts`
   - `npm run build:backend`
   - `npm --workspace backend/ai-service run build`
   - `npm run public:safety`
   - `npm run beta:gate`
   - unsigned service-enabled iOS build.
   - unsigned local-only App Store build.
2. Inspect `git status`, the complete diff, staged file list, dependency audit, and public safety output. Confirm no secret, service URL, private config, prompt fixture with user data, build output, or Xcode user state is included.
3. Run the manual live development smoke only after a configured development project and ADC are available. Then disable the live workflow policy and repeat the same synthetic journey to prove deterministic fallback.
4. Push the feature branch and open a focused PR describing the trust boundary, controlled-beta risk, tested fallbacks, and anything not live-verified.
5. Wait for fresh CI, address actionable failures/review, and merge only when every required check is green.
6. Fetch `origin`, synchronize canonical `main`, remove the completed worktree/branch, and verify canonical `main` equals `origin/main` with a clean tree.

## Slice Acceptance

- The iOS client can receive a genuinely live Cooked, quest-plan, proof-quality, or progress-summary result through the Firebase callable without knowing the model, service URL, prompt, credential, price, or budget.
- Adaptive career-intake live contracts are ready for the next onboarding UI slice without allowing unconfirmed inferences to become confirmed facts.
- Invalid, unsafe, timed-out, disabled, over-budget, quota-exhausted, or unavailable live generation yields an honest deterministic fallback where policy permits.
- Authentication failures and malformed client requests remain explicit errors.
- The eval set has zero hard fabrication/truth violations.
- The service exposes only its health and internal workflow routes, requires IAM-authenticated invocation, and has no unauthenticated Genkit developer surface.
- Automated verification is green, the focused PR is merged, and canonical `main` is clean and synchronized.
