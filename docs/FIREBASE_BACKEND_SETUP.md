# Firebase Backend Setup

OpenLARP now has a Firebase-ready backend boundary without requiring the iOS client to call AI providers directly.

## Current Dev Project

- Firebase project ID: `openlarp-dev-langqi`
- iOS bundle ID: `com.openlarp.app`
- Firestore database: default database in `nam5`
- Tracked config files: `.firebaserc`, `firebase.json`, `firestore.rules`, `storage.rules`
- Local-only config file: `OpenLARP/GoogleService-Info.plist`

`OpenLARP/GoogleService-Info.plist` is intentionally ignored by Git. The generated Xcode project excludes it from source membership and uses an optional post-build copy script so private local config is not accidentally committed or required in CI.

## What Exists In iOS

- `BackendSessionProviding` abstracts the current signed-in account/session.
- `LocalMockBackendSessionProvider` keeps local builds unauthenticated and safe.
- `FirebaseBackendSessionProvider` is compile-gated behind Firebase SDK imports and can expose the current Firebase Auth user when the SDK is linked.
- `FirebaseFirestoreBackendEventSyncService` is compile-gated and writes backend event outbox records to `users/{uid}/backendEvents/{eventId}` when Firebase Firestore is linked.
- `FirebaseReadyBackendEventSyncService` routes authenticated sessions to Firestore and keeps events pending when Firebase Auth needs sign-in or Firebase runtime config is missing.
- `FirebaseGoogleSignInAuthenticationService` provides a Google Sign-In boundary for restore, sign-in, sign-out, and URL handling without faking success when setup is incomplete.
- `OpenLARPFirebaseBootstrap.configureIfAvailable()` configures Firebase only when the SDK and plist are both available.
- `OpenLARPStore` now owns authentication state through `OpenLARPAuthenticationServicing`, restores previous sessions on app launch/foreground, forwards auth callback URLs, updates local profile account fields, and uses the same authenticated session source for backend events and career graph previews.
- `ProfileView` exposes account status, Google sign-in, restore, and sign-out controls while preserving local/mock mode.
- `FirebaseReadyCareerGraphSyncService` routes signed-in users to a Firestore-backed career graph metadata sync and keeps signed-out users in local preview mode.
- `FirebaseFirestoreCareerGraphSyncService` uploads available proof attachment bytes to Firebase Storage before writing account-owned Firestore metadata for profiles, goals, target roles, proof records, outcomes, and readiness snapshots.
- `FirebaseStorageProofAttachmentUploader` writes proof bytes to deterministic `users/{uid}/proofAttachments/{attachmentId}` paths with owner, proof, attachment, and idempotency custom metadata.
- `FirebaseCallableProofAttachmentReceiptPromoter` calls `promoteProofUploadReceipt` after Storage upload so the backend verifies the Storage object with the Admin SDK and writes uploaded proof attachment receipts server-side.
- `CareerGraphSyncUploadIntent.localRelativePath` is runtime-only and is intentionally omitted from encoded sync manifests and Firestore documents.
- Cloud proof records do not embed attachment documents. Attachment metadata and upload receipts live under `users/{uid}/proofAttachments/{attachmentId}` so local file paths cannot leak through nested proof-record payloads.
- `FirebaseCallableV0AIWorkflowService` calls the authenticated `runOpenLARPWorkflow` Firebase callable for diagnostic, quest-plan, proof-quality, and progress-summary workflows, then falls back to local mock AI only for known recoverable setup/auth states such as missing SDK/configuration or signed-out Firebase Auth.
- The callable AI adapter sends narrow backend DTOs and does not send local proof attachment filenames, UUIDs, or `localRelativePath`.

The Firebase adapters also check that `FirebaseApp` is configured before touching Auth, Firestore, or Storage. This lets CI and local mock builds continue safely when Firebase SDKs are linked but private runtime configuration has not been bundled.

Firebase Apple SDK products are now linked through Swift Package Manager via `project.yml`:

- `FirebaseCore`
- `FirebaseAuth`
- `FirebaseFirestore`
- `FirebaseStorage`
- `FirebaseFunctions`

Google Sign-In packages are also linked as the next auth UI integration point:

- `GoogleSignIn`
- `GoogleSignInSwift`

`GoogleService-Info.plist` remains ignored by Git and excluded from normal XcodeGen sources. The generated Xcode project includes an optional post-build copy script that copies the local plist into the app bundle only when the ignored local file exists.

The generated project includes the public `GOOGLE_REVERSED_CLIENT_ID` callback URL scheme for the `openlarp-dev-langqi` iOS app. Do not commit the real local Firebase plist; it carries the project SDK config and is copied into local app bundles only when present.

## Security Rules

Firestore rules currently allow signed-in users to read only their own `users/{uid}` tree. Client writes are limited to the account root, named career graph collections, proof records, proof attachment metadata, and beta backend event history; arbitrary user subcollections are denied.

Firestore rules enforce owner/path consistency, block client-written external action claims, block embedded proof attachment arrays, restrict client proof attachment metadata to `pendingUpload`, and require backend event idempotency keys to match the persisted entity ID. Proof upload receipt promotion is now server-owned through `promoteProofUploadReceipt`. This is still a beta client-sync model, not a fully server-trusted career graph; production trust still requires server-owned backend event acknowledgements and derived readiness/history writes.

Storage rules currently reserve this path:

```text
users/{uid}/proofAttachments/{attachmentId}
```

Only the signed-in owner can read proof attachments and create new proof attachment objects. Client-side proof attachment uploads are write-once: an existing object cannot be overwritten or deleted by the client. Repeated syncs stay safe because the iOS Firebase Storage adapter accepts an existing object only when its path, content type, byte count, owner ID, proof ID, attachment ID, and idempotency key exactly match the intended upload. The server callable then verifies the same Storage metadata before writing the Firestore upload receipt. Uploads are limited to PNG, JPEG, HEIC, HEIF, PDF, and plain text under 10 MB. Uploads must include only OpenLARP custom metadata: owner ID, proof ID, attachment ID, and idempotency key. Storage rules enforce the owner, attachment ID, and idempotency key against the signed-in user and path; the proof ID is carried forward into the Firestore upload receipt contract.

Client-written top-level proof attachment Firestore documents now require:

- matching `users/{uid}/proofAttachments/{attachmentId}` document and Storage paths
- no local device file path fields
- `pendingUpload` without a receipt

Uploaded proof attachment receipts are written by `promoteProofUploadReceipt`,
which verifies:

- matching signed-in owner, proof ID, attachment ID, Storage path, Firestore
  document paths, and idempotency key
- allowed content type and byte count under the Storage limit
- exact Storage custom metadata with no extra local/private fields
- existing Storage object metadata before the Firestore receipt is promoted

Proof record Firestore documents cannot embed attachment arrays. Attachment metadata must be written through the dedicated proof-attachment collection. The iOS sync adapter replaces proof-record documents instead of merge-writing them so older local beta records with embedded attachments are cleaned up on the next sync.

Current beta limitation: proof upload receipts are server-owned, but a fully authoritative career graph still needs backend-owned event acknowledgement, derived readiness/history writes, App Check enforcement, quota controls, and signed-in simulator/device smoke tests.

Firestore rules now prevent backend event documents from bypassing the dedicated `backendEvents` rule through a broad user-tree rule. The broad recursive user write path has been removed; only named beta sync collections accept client writes. Backend event documents require an exact event shape, matching `eventID`, owner, entity ID, known event kind, idempotency key, timestamp fields, and known typed summary fields. Current iOS beta sync still writes acknowledged event history from the client; before production trust, route event acknowledgement through a backend endpoint.

## Current Setup Status

- Firestore rules are deployed to `openlarp-dev-langqi`.
- Firebase Storage is initialized for `openlarp-dev-langqi` with the default bucket `openlarp-dev-langqi.firebasestorage.app` in `US-CENTRAL1`.
- Storage rules are deployed to `openlarp-dev-langqi`.
- The Firebase CLI environment has been authenticated locally, billing is enabled on `openlarp-dev-langqi`, and the iOS app `com.openlarp.app` exists in the Firebase project.
- Security rules validate through Firebase MCP.
- Emulator-based rules tests now exist under `firebase-rules/` and cover career graph document shapes, backend event spoofing, proof attachment Storage metadata, and upload receipt constraints. This workstation has OpenJDK 21 installed through Homebrew for local emulator verification.
- Firebase Functions config points to `backend/functions` with Node.js 22. `runOpenLARPWorkflow` is the callable AI workflow boundary, `promoteProofUploadReceipt` is the server-trusted proof receipt boundary, and `reconcileProofUploads` is the conservative orphan repair/report boundary.
- The deployable Functions package is intentionally Genkit-free while live model calls are disabled; Genkit/Gemini orchestration remains isolated in `backend/ai`.
- `backend/functions/package-lock.json` is committed because Firebase deploys from that source directory, and the package pins Firebase Admin to the latest 13.x version compatible with `firebase-functions@7.2.5`.
- The iOS app is wired to try `runOpenLARPWorkflow` through Firebase Functions first and preserve local V0 behavior through fallback when live Firebase is unavailable.
- `promoteProofUploadReceipt` exists as an authenticated callable that verifies uploaded proof Storage objects with the Admin SDK and writes Firestore upload receipts server-side.
- `reconcileProofUploads` exists as an authenticated callable repair/report boundary for rare orphaned proof uploads. It defaults to report-only and deletes only older owner-scoped Storage objects whose custom metadata matches the signed-in user and whose Firestore proof attachment document is missing.
- `runOpenLARPWorkflow`, `promoteProofUploadReceipt`, and `reconcileProofUploads` are expected deployed active Gen 2 callables in `us-central1` with Node.js 22 and live model calls disabled.
- The deployed `runOpenLARPWorkflow` callable is reachable and rejects unsigned requests with `UNAUTHENTICATED`, which confirms the auth boundary is active.
- Artifact Registry cleanup policies are installed for the Functions `gcf-artifacts` repository in `us-central1`: delete artifacts older than 7 days while keeping the most recent 5 versions.
- Google Sign-In is enabled in Firebase Auth for `openlarp-dev-langqi`.
- A fresh Firebase iOS SDK config can be retrieved by CLI and now includes `CLIENT_ID` and `REVERSED_CLIENT_ID`. The ignored local `OpenLARP/GoogleService-Info.plist` has been refreshed on this workstation.
- `npm run firebase:live-readiness` now passes Firestore, Functions, callable auth rejection, iOS config, Google OAuth IDs, Storage bucket existence, and Artifact Registry cleanup checks.

## Live Readiness Check

Run this from the repo root after Firebase login:

```bash
npm run firebase:live-readiness
```

The check verifies:

- Firebase CLI version
- default Firestore database shape
- active deployed callable Functions, including proof upload receipt promotion
- unauthenticated callable rejection from the live endpoint
- CLI retrieval of the iOS Firebase config without printing secret-bearing plist values
- Storage default bucket existence when `gcloud` is available
- Functions Artifact Registry cleanup policies when `gcloud` is available

A clean run should finish without missing Google OAuth ID or missing Storage bucket warnings. This script confirms the live project shape, but it does not replace a signed-in simulator/device smoke test for Google Sign-In, Firestore writes, Storage upload/read rules, or callable AI fallback behavior.

## Next Backend Steps

1. Verify live Google Sign-In on a simulator or device with the ignored local Firebase plist.
2. Deploy the latest Functions and Firestore rules, then rerun live readiness to confirm `promoteProofUploadReceipt` is active.
3. Test Firestore career graph sync, Storage proof attachment upload, server proof receipt promotion, and authenticated Firebase callable AI fallback behavior on a simulator or device.
4. Move backend event acknowledgement into Cloud Functions or Cloud Run before treating backend event history as authoritative.
5. Add App Check enforcement and per-user callable quota/budget controls before enabling live AI or broad external beta traffic.
6. Add Sign in with Apple before broad external TestFlight/App Store review if Google remains a primary sign-in option.
7. Deploy live Genkit/Gemini AI only after backend dependency advisories, prompts, evaluations, budget controls, observability, and secrets are resolved.
8. Keep provider model IDs and API keys only on the backend.

## Local Commands

```bash
npx -y firebase-tools@15.21.0 deploy --only firestore:rules --project openlarp-dev-langqi
npx -y firebase-tools@15.21.0 deploy --only storage --project openlarp-dev-langqi
npx -y firebase-tools@15.21.0 deploy --only functions:openlarp-ai --project openlarp-dev-langqi
npm run firebase:live-readiness
npm run build:backend
npx -y firebase-tools@15.21.0 emulators:start --project openlarp-rules-test --only auth,firestore,storage
npm run test:rules:emulators
```
