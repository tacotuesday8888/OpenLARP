# OpenLARP AI Backend

This package owns OpenLARP's server-side Genkit contracts, grounded prompts,
structured Gemini generation, post-generation truth checks, deterministic
fallbacks, and provider-safe usage accounting. The iOS app never imports a
model SDK or receives provider credentials, model IDs, prompts, pricing, or
budget configuration.

## Current Runtime

- Genkit: `genkit` with `@genkit-ai/google-genai`
- Provider: Vertex AI (`vertex-ai`)
- Default model: `gemini-3.5-flash`
- Default location: `global`
- Authentication: Google Application Default Credentials through workload
  identity; no API key or service-account key is required by the runtime
- Live generation: disabled unless every server-side runtime, policy, quota,
  and budget gate enables it

Google lists `gemini-3.5-flash` as generally available, with structured output,
system instructions, the global endpoint, and availability through at least
May 19, 2027. It remains the controlled-beta default because OpenLARP needs
stable structured career output more than agentic tool execution. The newer
`gemini-3.6-flash` has a shorter lifecycle commitment and ignores custom
sampling values, while this runtime deliberately uses a bounded temperature.
Re-evaluate it through the truthfulness evaluation set before changing the
default.

Official references:

- [Gemini 3.5 Flash model card](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-5-flash)
- [Gemini model lifecycle](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/model-versions)

## Backend Environment

```text
OPENLARP_GEMINI_MODEL_ID=gemini-3.5-flash
OPENLARP_AI_PROVIDER=vertex-ai
OPENLARP_VERTEX_LOCATION=global
OPENLARP_ENABLE_LIVE_AI=false
OPENLARP_AI_MAX_OUTPUT_TOKENS=1200
OPENLARP_AI_INPUT_TOKEN_MICROS_PER_1K=<current provider price>
OPENLARP_AI_OUTPUT_TOKEN_MICROS_PER_1K=<current provider price>
OPENLARP_AI_DAILY_BUDGET_MICROS=<explicit daily ceiling>
```

Provider pricing is intentionally not hardcoded because it changes over time.
Live dispatch fails closed unless all three pricing and budget values are
present. `configFromEnvironment()` validates runtime configuration and never
logs private values.

## Trust Boundary

The Firebase callable authenticates the user, validates the public envelope,
applies account-deletion, quota, runtime-policy, and budget gates, then invokes
the IAM-private Cloud Run service. This package runs only inside that private
service. It uses one bounded structured request with no tools and no external
actions, rejects malformed or unsafe output, and returns a deterministic result
for supported provider failures.

Live structured generation covers:

- Adaptive career intake
- Cooked diagnostic
- Editable mission brief
- Chapter-one and chapter-two quest plans
- Proof coaching with provider-independent rewards
- Day 7 and Day 14 progress summaries
- Contextual Ask OpenLARP assistance

Deterministic helpers also cover career briefs, privacy-safe share text,
opportunity ranking, and approved-source agent scan contracts; those future
surfaces are not silently treated as live-model jobs.

## Verification

From the repository root:

```bash
npm run typecheck:backend
npm run test:backend
npm run test:evals
npm run audit:production
npm run build:backend
```

Live deployment additionally requires project billing, Vertex/Agent Platform
access, least-privilege service identities, the private Cloud Run deployment,
callable configuration, a short-lived runtime policy, and an authenticated
`scripts/live-ai-smoke.sh --require-live` pass.
