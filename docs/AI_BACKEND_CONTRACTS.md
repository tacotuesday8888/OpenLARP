# AI Backend Contracts

OpenLARP's iOS app uses backend-safe AI envelopes for service-backed workflows. The app never calls an LLM provider directly.

## Request Envelope

Swift request payloads can be wrapped in `V0AIBackendRequestEnvelope<Payload>`.

The envelope contains:

- `schemaVersion`
- `run` metadata
- `safetyRules`
- typed `payload`

The `run` metadata contains only backend-safe routing and audit fields:

- workflow `kind`
- `providerRoute`
- `requestedAt`
- client-generated `requestID`
- privacy flags needed by the backend

It intentionally does not encode owner user IDs, account IDs, session IDs, emails, provider credentials, or direct model names.

## Provider Boundary

iOS contracts carry `V0AIProviderRoute` only, such as `cloudRunGenkit` or `firebaseCallableGenkit`.

The backend owns the mapping from that route to a concrete provider, SDK, deployment, and model. If a server target model is chosen, keep that value in backend configuration and backend docs, not in iOS runtime contracts.

## Safety Rules

Every envelope carries `V0AISafetyRules`. The default rules preserve OpenLARP's product guardrails:

- no fake employers, schools, certificates, job titles, dates, projects, or ownership claims
- frame real experience honestly
- separate proof from self-report
- do not write long-term memory unless the user enabled it
- do not take external actions without approval

## Encoding Stability

`AIBackendContractTests` verifies that the envelope:

- redacts private and session identifiers
- carries provider route only
- includes safety rules
- round-trips stable JSON with ISO-8601 dates
- decodes Firebase callable responses into Swift app models without exposing local proof attachment paths or provider model IDs

## iOS Callable Adapter

`FirebaseCallableV0AIWorkflowService` is the iOS adapter for the authenticated
`runOpenLARPWorkflow` callable. The production app injects it as the primary AI
workflow service behind `FallbackV0AIWorkflowService`, so local V0 behavior still
works when Firebase is not configured, the user is signed out, or the callable
fails.

The adapter:

- calls only the Firebase callable boundary, never an LLM provider SDK
- sends `providerRoute: firebaseCallableGenkit`
- uses narrow callable DTOs instead of raw Swift proof models
- strips local proof attachment filenames, UUIDs, and `localRelativePath` before network dispatch
- validates response schema, workflow kind, request ID, provider route, live-model flag, and external-action flag before recording a run
- supports a local Functions emulator configuration for authenticated development
- relies on backend-only token/cost accounting; model IDs, provider prices, and budget policy stay out of iOS

## Backend Packages

The repo includes:

- `backend/ai/`: shared schemas, deterministic handlers, grounded prompt builders, post-generation safety validation, Genkit/Gemini execution, and backend-only model configuration.
- `backend/ai-service/`: the narrow private Cloud Run HTTP runtime for live workflows.
- `backend/functions/`: the authenticated Firebase Callable Functions boundary, runtime policy reader, per-user quota guard, provider budget ledger, and IAM-authenticated Cloud Run client.

Shared request/response contracts import Zod directly. This keeps the deployable Firebase Functions package free of Genkit runtime dependencies while the Genkit/Gemini orchestration layer remains isolated behind the private AI service.

Current backend verification commands:

```bash
npm run typecheck:backend
npm run test:backend
npm run build:backend
```

The backend package defines server-side schemas, deterministic mock workflow handlers, safety validation, and Genkit flow definitions for:

- cooked diagnostic generation
- quest plan generation
- proof quality checks
- progress summaries
- career briefs
- safe share-card text
- future opportunity ranking
- future approved-source agent scans

The default backend target model is kept in backend config only. The iOS app still carries only `V0AIProviderRoute` values and does not encode model IDs, API keys, provider credentials, pricing, budgets, service URLs, or direct prompts.

The callable exports are `runOpenLARPWorkflow`, `setPrivateEvidenceCloudSyncConsent`, `promoteProofUploadReceipt`, `reconcileProofUploads`, `cleanupRevokedPrivateEvidenceUploads`, `acknowledgeBackendEvents`, and `deleteOpenLARPAccount`, configured in `firebase.json` under `backend/functions`. The existing dev deployment still uses deterministic fallback; the private AI service and updated callable configuration have not yet been deployed or live-smoked.

The deterministic callable package includes server-side per-user daily quota units for all authenticated callables. `runOpenLARPWorkflow` is capped before deterministic AI dispatch, records provider token/cost estimate metadata without prompt or proof text, and the proof/event callables are capped before Storage or Firestore side effects. Exhausted users receive `resource-exhausted` with safe quota details only.

The backend AI package estimates provider token pressure without persisting prompt or proof text. Live model calls require explicit backend pricing and daily budget config via `OPENLARP_AI_INPUT_TOKEN_MICROS_PER_1K`, `OPENLARP_AI_OUTPUT_TOKEN_MICROS_PER_1K`, and `OPENLARP_AI_DAILY_BUDGET_MICROS`; partial config is rejected, and budget-exceeded requests are blocked before dispatch. No provider price is hardcoded because provider pricing changes over time.

## Private Live AI Execution

The live path is deliberately split across two trust boundaries:

1. The signed-in app calls `runOpenLARPWorkflow`. Firebase Auth identifies the user; the callable validates the envelope, safety rules, provider route, per-user quota, runtime policy, and provider budget.
2. The callable changes the internal route to `cloudRunGenkit` and calls the private Cloud Run service with a Google-signed ID token. The token audience is the exact Cloud Run service origin. Only the Functions runtime service account receives `roles/run.invoker`.
3. Cloud Run accepts only `GET /healthz` and `POST /v1/workflows:run`, validates the internal schema, runs bounded structured generation, validates grounding and truthfulness rules after generation, and returns a schema-checked result.

Cloud Run IAM provides service authentication. There is no second application token, API key, service-account key file, or client-visible secret. Workload identities use Application Default Credentials. The AI service account should receive only the Vertex AI permissions required to generate content; the Functions identity receives only Cloud Run invocation permission.

### Runtime controls

Live execution is fail-closed and requires every control below:

- `OPENLARP_ENABLE_LIVE_AI=true` on both the callable and AI-service runtimes.
- A valid HTTPS `OPENLARP_AI_SERVICE_URL` on Functions.
- All three Functions pricing/budget values: `OPENLARP_AI_INPUT_TOKEN_MICROS_PER_1K`, `OPENLARP_AI_OUTPUT_TOKEN_MICROS_PER_1K`, and `OPENLARP_AI_DAILY_BUDGET_MICROS`.
- A current `_serverConfig/aiRuntimePolicy` document with `schemaVersion: 1`, a safe `revision`, `enabled`, a future `validUntil`, `timeoutMs` from 1,000 through 45,000, `maxOutputTokens` from 128 through 8,192, and explicit booleans for `adaptiveCareerIntake`, `cookedDiagnostic`, `missionBrief`, `questPlan`, `proofQualityCheck`, and `progressSummary`.

The runtime policy is cached for at most 30 seconds and becomes disabled when missing, malformed, expired, globally off, or off for the requested workflow. The provider budget ledger lives under `_serverAIUsage/providerDaily/days/{UTC-day}` with hashed, expiring request reservations. Duplicate request IDs do not repeat provider work. The ledger reconciles estimated cost to actual token cost after the service responds and releases a reservation when dispatch cannot proceed.

Fallback reasons are intentionally bounded to `disabled`, `policy`, `quota`, `budget`, `timeout`, `provider`, `invalidOutput`, and `unsafeOutput`. The callable returns the deterministic result rather than leaving the primary product flow dead-ended. The client validates request ID, workflow kind, provider route, execution metadata, and result schema before accepting a response.

Operational output is metadata-only: status, workflow kind, live/fallback flags, bounded fallback reason, latency bucket, prompt version, and token counts. Prompts, profile/proof text, model IDs, service URLs, pricing, budget values, user identifiers, and policy contents are not emitted by the smoke tool or returned to iOS.

### Deployment and rollback

Build and deploy the private service only from a clean reviewed revision:

```bash
scripts/deploy-ai-service.sh \
  --project PROJECT \
  --region REGION \
  --service SERVICE \
  --ai-service-account AI_SERVICE_ACCOUNT \
  --functions-service-account FUNCTIONS_SERVICE_ACCOUNT
```

The helper builds through Cloud Build, deploys with `--no-allow-unauthenticated`, bounds instance count and request timeout, and adds Cloud Run invocation for the supplied Functions service account without adding public access. Review existing IAM separately so no unintended invoker remains. The helper intentionally does not create identities, assign Vertex roles, set Functions configuration, create policy documents, or handle secrets.

After configuring Functions and writing a short-lived policy that enables only the workflow being checked, verify the private service using an ADC principal permitted to invoke it:

```bash
scripts/live-ai-smoke.sh --service-url CLOUD_RUN_ORIGIN --require-live
```

To stop live traffic, set the Firestore runtime policy `enabled` field to `false`; allow up to the 30-second cache TTL. For immediate defense in depth, also set `OPENLARP_ENABLE_LIVE_AI=false` on Functions or the AI service. Restore a previous Cloud Run revision only after dispatch is disabled.

### Controlled-beta dependency risk

`npm run audit:production` currently accepts exactly six enumerated high-severity findings in the shipped production dependency graph, all transitive through Genkit/OpenTelemetry. It rejects critical findings, direct high-severity findings, malformed audit output, or any unenumerated high finding. The development/tooling dependency graph has separate Firebase CLI advisories and is not part of the deployed service image.

This is an explicit controlled-beta risk acceptance, not approval for broad production traffic. Keep the allowlist narrow, rerun the audit in CI, review upstream fixes, and remove each exception as soon as compatible patched releases are available. Live deployment and the authenticated `--require-live` smoke remain pending operator actions.
