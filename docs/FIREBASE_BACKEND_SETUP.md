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
- `FirebaseCallableBackendEventSyncService` is compile-gated and calls `acknowledgeBackendEvents` to promote local backend event outbox records into server-owned `users/{uid}/backendEvents/{eventId}` history.
- `FirebaseReadyBackendEventSyncService` routes authenticated sessions to the callable event acknowledgement boundary and keeps events pending when Firebase Auth needs sign-in or Firebase runtime config is missing.
- `FirebaseGoogleSignInAuthenticationService` provides a Google Sign-In boundary for restore, sign-in, sign-out, and URL handling without faking success when setup is incomplete.
- `OpenLARPFirebaseBootstrap.configureIfAvailable()` configures Firebase only when the SDK and plist are both available, and installs the Firebase App Check provider factory before `FirebaseApp.configure()`.
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
- `FirebaseAppCheck`

Google Sign-In packages are also linked as the next auth UI integration point:

- `GoogleSignIn`
- `GoogleSignInSwift`

`GoogleService-Info.plist` remains ignored by Git and excluded from normal XcodeGen sources. The generated Xcode project includes an optional post-build copy script that copies the local plist into the app bundle only when the ignored local file exists.

The generated project includes the public `GOOGLE_REVERSED_CLIENT_ID` callback URL scheme for the `openlarp-dev-langqi` iOS app. Do not commit the real local Firebase plist; it carries the project SDK config and is copied into local app bundles only when present.

## App Check Readiness

OpenLARP now links `FirebaseAppCheck` and configures an App Check provider factory before Firebase starts:

- simulator builds use no App Check provider by default so local tests do not leak debug tokens
- simulator builds can opt into Firebase's debug App Check provider with `OPENLARP_ENABLE_FIREBASE_APP_CHECK_DEBUG=1`, `AppCheckDebugToken`, or Firebase's deprecated `FIRAAppCheckDebugToken`
- device builds use Apple's App Attest provider with the production App Attest entitlement in `OpenLARP/OpenLARP.entitlements`
- builds without Firebase App Check linked remain local-safe

App Check enforcement is intentionally not enabled yet for Firestore, Storage, or callable Functions. Enabling enforcement now would break the current CLI smoke scripts and any installed app build that does not yet send valid App Check tokens. Before enforcement:

1. Register App Check for the `com.openlarp.app` iOS app in Firebase Console.
2. Register simulator/debug tokens in Firebase Console without committing them or exposing them in shared logs.
3. Verify App Check request metrics from a simulator and a real device.
4. Update live smoke tooling to send or obtain valid App Check tokens.
5. Enable enforcement gradually for Storage, Firestore, and callable Functions only after signed-in simulator/device testing passes.

## Security Rules

Firestore rules currently allow signed-in users to read only their own `users/{uid}` tree. Client writes are limited to the account root, named career graph collections, proof records, and pending proof attachment metadata; arbitrary user subcollections are denied.

Firestore rules enforce owner/path consistency, block client-written external action claims and sync status fields, block embedded proof attachment arrays, and restrict client proof attachment metadata to `pendingUpload`. Proof upload receipt promotion is server-owned through `promoteProofUploadReceipt`, and backend event acknowledgement is server-owned through `acknowledgeBackendEvents`. The callable backend now also records per-user daily quota units before AI workflow dispatch, proof receipt promotion, proof upload reconciliation, or backend event acknowledgement. This is still a beta client-sync model, not a fully server-trusted career graph; production trust still requires derived readiness/history writes, App Check enforcement after provider rollout, provider token/cost accounting, and signed-in simulator/device smoke tests.

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
- exact OpenLARP Storage custom metadata with no extra local/private fields; Firebase-managed Storage metadata such as download tokens may also exist on client uploads
- existing Storage object metadata before the Firestore receipt is promoted

Proof record Firestore documents cannot embed attachment arrays. Attachment metadata must be written through the dedicated proof-attachment collection. The iOS sync adapter replaces proof-record documents instead of merge-writing them so older local beta records with embedded attachments are cleaned up on the next sync.

Current beta limitation: proof upload receipts, backend event acknowledgement, and per-user callable quotas are server-owned, but a fully authoritative career graph still needs derived readiness/history writes, App Check enforcement, provider token/cost accounting, and signed-in simulator/device smoke tests.

Firestore rules now prevent backend event documents from bypassing the dedicated `backendEvents` rule through a broad user-tree rule. The broad recursive user write path has been removed; only named beta sync collections accept client writes. Backend event documents are owner-readable, but client create, update, and delete are denied. The server callable validates exact event shape, matching owner, known event kind, idempotency key, timestamp fields, and known typed summary fields before writing acknowledged history through the Admin SDK.

## Current Setup Status

- Firestore rules are deployed to `openlarp-dev-langqi`.
- Firebase Storage is initialized for `openlarp-dev-langqi` with the default bucket `openlarp-dev-langqi.firebasestorage.app` in `US-CENTRAL1`.
- Storage rules are deployed to `openlarp-dev-langqi`.
- The Firebase CLI environment has been authenticated locally, billing is enabled on `openlarp-dev-langqi`, and the iOS app `com.openlarp.app` exists in the Firebase project.
- Security rules validate through Firebase MCP.
- Emulator-based rules tests now exist under `firebase-rules/` and cover career graph document shapes, backend event spoofing, proof attachment Storage metadata, and upload receipt constraints. This workstation has OpenJDK 21 installed through Homebrew for local emulator verification.
- Firebase Functions config points to `backend/functions` with Node.js 22. `runOpenLARPWorkflow` is the callable AI workflow boundary, `promoteProofUploadReceipt` is the server-trusted proof receipt boundary, `reconcileProofUploads` is the conservative orphan repair/report boundary, and `acknowledgeBackendEvents` is the server-owned backend event acknowledgement boundary.
- The deployable Functions package is intentionally Genkit-free while live model calls are disabled; Genkit/Gemini orchestration remains isolated in `backend/ai`.
- `backend/functions/package-lock.json` is committed because Firebase deploys from that source directory, and the package pins Firebase Admin to the latest 13.x version compatible with `firebase-functions@7.2.5`.
- The iOS app is wired to try `runOpenLARPWorkflow` through Firebase Functions first and preserve local V0 behavior through fallback when live Firebase is unavailable.
- `promoteProofUploadReceipt` exists as an authenticated callable that verifies uploaded proof Storage objects with the Admin SDK and writes Firestore upload receipts server-side.
- `reconcileProofUploads` exists as an authenticated callable repair/report boundary for rare orphaned proof uploads. It defaults to report-only and deletes only older owner-scoped Storage objects whose custom metadata matches the signed-in user and whose Firestore proof attachment document is missing.
- `runOpenLARPWorkflow`, `promoteProofUploadReceipt`, `reconcileProofUploads`, and `acknowledgeBackendEvents` are protected by server-side per-user daily callable quota units. Exhausted calls return `resource-exhausted` before workflow dispatch, Storage scans, Storage reads, Firestore receipt writes, or backend event acknowledgement writes.
- iOS App Check provider scaffolding is linked and configured, but Firebase product enforcement is still off until console registration, debug token handling, metrics, and signed-in simulator/device checks are complete.
- `runOpenLARPWorkflow`, `promoteProofUploadReceipt`, `reconcileProofUploads`, and `acknowledgeBackendEvents` are expected deployed active Gen 2 callables in `us-central1` with Node.js 22 and live model calls disabled.
- The deployed `runOpenLARPWorkflow` callable is reachable and rejects unsigned requests with `UNAUTHENTICATED`, which confirms the auth boundary is active.
- `npm run firebase:signed-in-smoke` creates a temporary Firebase Auth smoke user through a local Admin custom token, calls the live workflow/proof/event callables as that signed-in user, validates Storage and Firestore side effects, and deletes its temporary Auth, Storage, Firestore, and quota data.
- Artifact Registry cleanup policies are installed for the Functions `gcf-artifacts` repository in `us-central1`: delete artifacts older than 7 days while keeping the most recent 5 versions.
- Google Sign-In is enabled in Firebase Auth for `openlarp-dev-langqi`.
- A fresh Firebase iOS SDK config can be retrieved by CLI and now includes `CLIENT_ID` and `REVERSED_CLIENT_ID`. The ignored local `OpenLARP/GoogleService-Info.plist` has been refreshed on this workstation.
- `npm run firebase:live-readiness` now checks Firestore, Functions, callable auth rejection for workflow/proof/event boundaries, iOS config, Google OAuth IDs, Storage bucket existence, and Artifact Registry cleanup policies.

## Live Readiness Check

Run this from the repo root after Firebase login:

```bash
npm run firebase:live-readiness
```

The check verifies:

- Firebase CLI version
- default Firestore database shape
- active deployed callable Functions, including proof upload receipt promotion and backend event acknowledgement
- unauthenticated callable rejection from the live workflow, proof promotion, and backend event acknowledgement endpoints
- local deploy source includes the server-side callable quota guard
- CLI retrieval of the iOS Firebase config without printing secret-bearing plist values
- Storage default bucket existence when `gcloud` is available
- Functions Artifact Registry cleanup policies when `gcloud` is available

A clean run should finish without missing Google OAuth ID or missing Storage bucket warnings. This script confirms the live project shape and local deploy source shape, but it does not replace the signed-in smoke check or a simulator/device smoke test for Google Sign-In UX, Firestore writes, Storage upload/read rules, quota exhaustion, or callable AI fallback behavior.

## Signed-In Smoke Check

Run this from the repo root after Firebase and gcloud login:

```bash
npm run firebase:signed-in-smoke
```

The check uses a temporary Firebase Auth user and does not print ID tokens, API keys, or proof payloads. It verifies:

- local Admin credentials can mint a Firebase custom token for a temporary smoke UID
- the temporary ID token is accepted by `runOpenLARPWorkflow`
- the live proof Storage bucket accepts a temporary proof object written through a signed-in Firebase client session
- `promoteProofUploadReceipt` verifies that object and writes the server receipt
- `reconcileProofUploads` reports the uploaded proof attachment as linked
- `acknowledgeBackendEvents` writes server-owned backend event history
- temporary Auth, Storage, Firestore, and quota data are cleaned up

Prerequisites:

- Firebase CLI access to `openlarp-dev-langqi`
- Google Application Default Credentials, usually from `gcloud auth application-default login`
- IAM Credentials API enabled for the project
- the active Application Default Credentials principal has `iam.serviceAccounts.signBlob` on the Firebase Admin SDK service account, usually via `roles/iam.serviceAccountTokenCreator`

Optional environment overrides:

```bash
OPENLARP_FIREBASE_PROJECT_ID=openlarp-dev-langqi
OPENLARP_FIREBASE_SMOKE_ALLOW_PROJECT=openlarp-dev-langqi
OPENLARP_FIREBASE_IOS_APP_ID=1:795318771575:ios:5315b3cc5b1bff81e30b72
OPENLARP_FUNCTION_REGION=us-central1
OPENLARP_FIREBASE_STORAGE_BUCKET=openlarp-dev-langqi.firebasestorage.app
OPENLARP_FIREBASE_SMOKE_UID=openlarp-smoke-manual
OPENLARP_FIREBASE_SIGNING_SERVICE_ACCOUNT=firebase-adminsdk-...@openlarp-dev-langqi.iam.gserviceaccount.com
```

This CLI smoke test complements but does not replace a real simulator/device Google Sign-In UX pass. After App Check enforcement is enabled, this smoke test must also obtain or send a valid App Check token.

## Next Backend Steps

1. Verify live Google Sign-In on a simulator or device with the ignored local Firebase plist.
2. Keep `npm run firebase:live-readiness` and `npm run firebase:signed-in-smoke` passing after backend deploys.
3. Test Firestore career graph sync, Storage proof attachment upload, server proof receipt promotion, and authenticated Firebase callable AI fallback behavior on a simulator or device.
4. Register App Check in Firebase Console, verify simulator/debug and device App Attest metrics, update smoke tooling for App Check tokens, then enable App Check enforcement.
5. Add Sign in with Apple before broad external TestFlight/App Store review if Google remains a primary sign-in option.
6. Deploy live Genkit/Gemini AI only after backend dependency advisories, prompts, evaluations, budget controls, observability, and secrets are resolved.
7. Keep provider model IDs and API keys only on the backend.

## Local Commands

```bash
npx -y firebase-tools@15.21.0 deploy --only firestore:rules --project openlarp-dev-langqi
npx -y firebase-tools@15.21.0 deploy --only storage --project openlarp-dev-langqi
npx -y firebase-tools@15.21.0 deploy --only functions:openlarp-ai --project openlarp-dev-langqi
npm run firebase:live-readiness
npm run firebase:signed-in-smoke
npm run build:backend
npx -y firebase-tools@15.21.0 emulators:start --project openlarp-rules-test --only auth,firestore,storage
npm run test:rules:emulators
```
