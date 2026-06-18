# OpenLARP Firebase Functions

This package is the deployable Firebase Functions boundary for OpenLARP AI workflows and server-owned proof upload trust.

The iOS app should call Firebase Auth-protected callable functions, not provider APIs. This package validates the existing `backend/ai` request envelope, enforces auth and external-action guardrails, then dispatches to deterministic backend workflow handlers while live model calls are disabled.

## Current Status

- Callable export: `runOpenLARPWorkflow`
- Callable export: `reconcileProofUploads`
- Callable export: `promoteProofUploadReceipt`
- Runtime: Node.js 22
- Firebase Admin: pinned to `13.10.0` to satisfy
  `firebase-functions@7.2.5` peer dependencies
- Live model calls: disabled
- Provider secrets: not required locally and must never be committed
- Workflow contracts: imported from `backend/ai`
- Deploy package: intentionally does not depend on Genkit while live model calls
  are disabled
- Deploy lockfile: `backend/functions/package-lock.json` is committed so
  Firebase Cloud Build installs the same deploy-source dependency graph
- Dev deploy: `runOpenLARPWorkflow`, `reconcileProofUploads`, and
  `promoteProofUploadReceipt` are expected active Gen 2 callables in
  `openlarp-dev-langqi` / `us-central1`
- Live endpoint smoke: unsigned workflow requests return `UNAUTHENTICATED`
- Artifact cleanup: `gcf-artifacts` keeps the most recent 5 versions and deletes
  artifacts older than 7 days

The deployable Functions runtime validates shared request/response contracts with
direct Zod imports. Genkit stays isolated in `backend/ai` so deterministic
callable functions can be built and deployed without bundling the current
Genkit/OpenTelemetry dependency tree.

## Proof Upload Promotion

`promoteProofUploadReceipt` is an authenticated Firebase callable that turns an
iOS Storage upload into a server-trusted Firestore proof attachment receipt.

The callable:

- requires Firebase Auth
- accepts only deterministic `users/{uid}/proofAttachments/{attachmentId}` paths
- validates proof ID, attachment ID, owner metadata, content type, byte count,
  idempotency key, and Storage object existence with the Admin SDK
- rejects extra Storage custom metadata, including local file paths
- writes the Firestore `users/{uid}/proofAttachments/{attachmentId}` document
  with `uploadStatus: uploaded` and a matching receipt
- returns the uploaded receipt to iOS without provider secrets or local file
  paths

Firestore rules now allow clients to create only `pendingUpload` proof
attachment metadata. Uploaded receipts are server-owned.

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
npm run firebase:live-readiness
npm audit --workspace backend/functions --omit=dev --json
```

## Deploy Notes

This package is wired into Firebase deployment config for deterministic callable
workflows with live AI disabled.

Before live AI is enabled, configure backend secrets outside the repository,
review prompts and safety evaluations, set rate limits, budget monitoring, and
observability, and run a fresh audit for both `backend/functions` and
`backend/ai`.
