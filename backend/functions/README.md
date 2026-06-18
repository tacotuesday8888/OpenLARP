# OpenLARP Firebase Functions

This package is the deployable Firebase Functions boundary for OpenLARP AI workflows.

The iOS app should call Firebase Auth-protected callable functions, not provider APIs. This package validates the existing `backend/ai` request envelope, enforces auth and external-action guardrails, then dispatches to deterministic backend workflow handlers while live model calls are disabled.

## Current Status

- Callable export: `runOpenLARPWorkflow`
- Callable export: `reconcileProofUploads`
- Runtime: Node.js 22
- Live model calls: disabled
- Provider secrets: not required locally and must never be committed
- Workflow contracts: imported from `backend/ai`

## Proof Upload Reconciliation

`reconcileProofUploads` is an authenticated Firebase callable for the rare case
where proof bytes were uploaded to Storage but the later Firestore metadata write
did not complete.

The callable is conservative by default:

- signed-in user required
- scans only `users/{uid}/proofAttachments/{attachmentId}`
- compares Storage custom metadata against the signed-in owner and attachment ID
- compares existing Firestore proof attachment receipts against Storage metadata
- defaults to `reportOnly`
- refuses to delete very recent uploads while Firestore metadata may still retry; callers may increase but not lower the server age window
- deletes with the inspected Storage generation precondition so a rewritten object is not removed
- deletes only safe orphaned Storage objects when called with
  `mode: "deleteOrphans"` and `confirmDeletion: true`

## Local Commands

From the repo root:

```bash
npm run typecheck:backend
npm run test:backend
npm --workspace backend/functions run build
```

## Deploy Notes

This package is ready to be wired into Firebase deployment config. A deployment follow-up should add the `functions` source entry in `firebase.json`, configure backend secrets, and keep `OPENLARP_ENABLE_LIVE_AI=false` until Genkit prompts, safety evaluations, rate limits, and production monitoring are reviewed.
