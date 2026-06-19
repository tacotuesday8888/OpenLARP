# OpenLARP Firebase Functions

This package is the deployable Firebase Functions boundary for OpenLARP AI workflows, proof upload trust, and server-owned backend event acknowledgement.

The iOS app should call Firebase Auth-protected callable functions, not provider APIs. This package validates the existing `backend/ai` request envelope, enforces auth and external-action guardrails, then dispatches to deterministic backend workflow handlers while live model calls are disabled.

## Current Status

- Callable export: `runOpenLARPWorkflow`
- Callable export: `setPrivateEvidenceCloudSyncConsent`
- Callable export: `reconcileProofUploads`
- Callable export: `promoteProofUploadReceipt`
- Callable export: `acknowledgeBackendEvents`
- Callable quota: per-user daily Firestore-backed units for work-producing
  authenticated callables
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
- Dev deploy: `runOpenLARPWorkflow`, `setPrivateEvidenceCloudSyncConsent`,
  `reconcileProofUploads`, `promoteProofUploadReceipt`, and
  `acknowledgeBackendEvents` are expected active Gen 2 callables in
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
- requires accepted server-owned private evidence cloud sync consent
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

## Private Evidence Cloud Sync Consent

`setPrivateEvidenceCloudSyncConsent` is an authenticated Firebase callable that
records whether the signed-in user accepts or revokes private evidence cloud
sync.

The callable:

- requires Firebase Auth
- accepts only schema version 1 requests with a boolean `enabled` flag
- writes `users/{uid}/consents/privateEvidenceCloudSync` with Admin SDK
- records `status: accepted` plus `acceptedAt` when enabled
- records `status: revoked` plus `revokedAt` when disabled
- returns the server-owned document path and consent text version without
  exposing tokens, proof text, provider metadata, prompts, or local file paths

Firestore and Storage rules require `status: accepted` and
`allowsPrivateEvidenceCloudSync: true` before private proof records, proof
attachment metadata, or proof bytes can be written. Client create, update, and
delete are denied for consent documents.

## Callable Quota / Budget Guard

Work-producing authenticated callables use `callableQuotaGuard.ts` before
expensive or server-writing side effects. The guard records one Admin Firestore
transaction per request under `_serverUsage/{hashedUid}/days/{yyyy-MM-dd}` and
writes a charge receipt under that day document. Guarded callable invocations
consume quota units; request IDs and idempotency keys are audit hints only, not
free replay tokens. Consent toggles are intentionally outside the daily quota
guard so users can always revoke private evidence cloud sync.

Current beta daily unit limits:

- `runOpenLARPWorkflow`: 60 units
- `promoteProofUploadReceipt`: 150 units
- `reconcileProofUploads`: 30 units
- `acknowledgeBackendEvents`: 500 units

Quota exhaustion returns Firebase callable error code `resource-exhausted` with
safe details: callable name, user-daily scope, limit units, used units,
requested units, and reset time. The response does not include UID, email,
proof text, proof paths, provider metadata, prompts, or audit keys.

This is a beta request-unit guard. Live Genkit/Gemini still needs provider token
accounting, App Check enforcement, observability, and alerting before broad
traffic.

## Backend Event Acknowledgement

`acknowledgeBackendEvents` is an authenticated Firebase callable that promotes
the local iOS backend event outbox into server-owned Firestore history.

The callable:

- requires Firebase Auth
- accepts only redacted Firebase sessions whose owner matches the signed-in UID
- accepts only `inFlight` local outbox events with schema version 1
- validates supported event kinds, UUID event IDs, owner IDs, entity IDs,
  idempotency keys, ISO timestamps, retry counts, and allowlisted summary fields
- rejects duplicate event IDs or duplicate idempotency keys in one request
- writes acknowledged history under `users/{uid}/backendEvents/{eventId}` using
  Admin SDK server time for `acceptedAt`
- treats exact repeated submissions as idempotent and rejects conflicting
  documents instead of overwriting server history
- returns acknowledgement receipts to iOS without raw proof payloads, provider
  secrets, local file paths, account IDs, or email addresses

Firestore rules allow users to read only their own backend event history. Client
create, update, and delete are denied for backend events; only Admin-backed
server code can write acknowledgements.

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
review prompts and safety evaluations, add provider token accounting, App Check,
budget monitoring, and observability, and run a fresh audit for both
`backend/functions` and `backend/ai`.
