# AI Backend Contracts

OpenLARP's iOS app uses backend-safe AI envelopes for future service-backed workflows. The app should never call an LLM provider directly.

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

## Backend Package

The repo now includes a Genkit-ready backend package in `backend/ai/`.

Current backend verification commands:

```bash
npm run typecheck:backend
npm run test:backend
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

The default backend target model is `gemini-3.1-flash-lite`, kept in backend config only. The iOS app still carries only `V0AIProviderRoute` values and does not encode model IDs, API keys, provider credentials, or direct prompts.

Live model calls remain disabled until backend deployment, secrets, budget controls, and evaluation gates are configured.
