# OpenLARP Firebase Functions

This package is the deployable Firebase Functions boundary for OpenLARP AI workflows.

The iOS app should call Firebase Auth-protected callable functions, not provider APIs. This package validates the existing `backend/ai` request envelope, enforces auth and external-action guardrails, then dispatches to deterministic backend workflow handlers while live model calls are disabled.

## Current Status

- Callable export: `runOpenLARPWorkflow`
- Runtime: Node.js 22
- Live model calls: disabled
- Provider secrets: not required locally and must never be committed
- Workflow contracts: imported from `backend/ai`

## Local Commands

From the repo root:

```bash
npm run typecheck:backend
npm run test:backend
npm --workspace backend/functions run build
```

## Deploy Notes

This package is ready to be wired into Firebase deployment config. A deployment follow-up should add the `functions` source entry in `firebase.json`, configure backend secrets, and keep `OPENLARP_ENABLE_LIVE_AI=false` until Genkit prompts, safety evaluations, rate limits, and production monitoring are reviewed.
