# OpenLARP AI Backend

This package is the server-side Genkit foundation for OpenLARP AI workflows.

The iOS app must not call model providers directly. iOS sends backend-safe workflow payloads and provider routes; this package owns model/provider selection, schema validation, safety checks, and deployable flow definitions.

## Current Status

- Genkit package: `genkit`
- Gemini provider package: `@genkit-ai/google-genai`
- Default backend model ID: `gemini-3.1-flash-lite`
- Local verification: TypeScript typecheck and Vitest tests
- Live model calls: disabled by default until backend secrets and deployment are configured

## Backend Environment

Do not put provider secrets in the iOS app.

Backend-only config:

```text
OPENLARP_GEMINI_MODEL_ID=gemini-3.1-flash-lite
OPENLARP_AI_PROVIDER=firebase-ai-logic
OPENLARP_ENABLE_LIVE_AI=false
OPENLARP_AI_MAX_OUTPUT_TOKENS=1200
GEMINI_API_KEY=<store as a backend secret, never in Git>
```

`GEMINI_API_KEY` is read only by the provider runtime when live AI is enabled.
`configFromEnvironment()` validates OpenLARP runtime flags and never exposes or
logs provider secret values.

## Local Commands

From the repo root:

```bash
npm run typecheck:backend
npm run test:backend
npm run build:backend
```

`backend/functions` exposes the Firebase callable boundary for these workflows.
It validates the same request envelope, requires Firebase Auth, blocks external
actions, and dispatches to deterministic workflow handlers while live model
calls are disabled.

## Flow Surface

Current V0 flow definitions:

- `openlarp.v0.cookedDiagnostic`
- `openlarp.v0.questPlan`
- `openlarp.v0.proofQualityCheck`
- `openlarp.v0.progressSummary`
- `openlarp.v0.careerBrief`
- `openlarp.v0.safeShareCardText`
- `openlarp.v1.opportunityRanking`
- `openlarp.v1.agentScan`

The mock workflow engine is deterministic so CI can verify contracts without provider credentials. Production Genkit prompts, secrets, rate limits, and deployment config should be added server-side before enabling live AI.
