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
- `FirebaseFirestoreCareerGraphSyncService` uploads available proof attachment bytes to Firebase Storage before writing account-owned Firestore metadata for profiles, goals, target roles, proof records, proof attachment receipts, outcomes, and readiness snapshots.
- `FirebaseStorageProofAttachmentUploader` writes proof bytes to deterministic `users/{uid}/proofAttachments/{attachmentId}` paths with owner, proof, attachment, and idempotency custom metadata.
- `CareerGraphSyncUploadIntent.localRelativePath` is runtime-only and is intentionally omitted from encoded sync manifests and Firestore documents.
- Cloud proof records do not embed attachment documents. Attachment metadata and upload receipts live under `users/{uid}/proofAttachments/{attachmentId}` so local file paths cannot leak through nested proof-record payloads.

The Firebase adapters also check that `FirebaseApp` is configured before touching Auth, Firestore, or Storage. This lets CI and local mock builds continue safely when Firebase SDKs are linked but private runtime configuration has not been bundled.

Firebase Apple SDK products are now linked through Swift Package Manager via `project.yml`:

- `FirebaseCore`
- `FirebaseAuth`
- `FirebaseFirestore`
- `FirebaseStorage`

Google Sign-In packages are also linked as the next auth UI integration point:

- `GoogleSignIn`
- `GoogleSignInSwift`

`GoogleService-Info.plist` remains ignored by Git and excluded from normal XcodeGen sources. The generated Xcode project includes an optional post-build copy script that copies the local plist into the app bundle only when the ignored local file exists.

The generated project also includes a `GOOGLE_REVERSED_CLIENT_ID` build setting placeholder and a matching URL type entry for Google Sign-In callbacks. Do not commit the real local Firebase plist. For live local sign-in, set `GOOGLE_REVERSED_CLIENT_ID` to the `REVERSED_CLIENT_ID` value from the local plist in a non-committed Xcode setting or local build override before running on device/simulator.

## Security Rules

Firestore rules currently allow signed-in users to read/write only under their own `users/{uid}` tree and prevent client writes that claim external actions were taken.

Storage rules currently reserve this path:

```text
users/{uid}/proofAttachments/{attachmentId}
```

Only the signed-in owner can read/write proof attachments, and uploads are limited to images, PDFs, and plain text under 10 MB. Uploads must include OpenLARP custom metadata: owner ID, proof ID, attachment ID, and idempotency key. Storage rules enforce the owner, attachment ID, and idempotency key against the signed-in user and path; the proof ID is carried forward into the Firestore upload receipt contract.

Top-level proof attachment Firestore documents now require:

- matching `users/{uid}/proofAttachments/{attachmentId}` document and Storage paths
- no local device file path fields
- `pendingUpload` without a receipt, or `uploaded` with a receipt
- uploaded receipts that match the same proof, attachment, content type, byte count, Storage path, and owner-scoped idempotency key

Proof record Firestore documents cannot embed attachment arrays. Attachment metadata must be written through the dedicated proof-attachment collection. The iOS sync adapter replaces proof-record documents instead of merge-writing them so older local beta records with embedded attachments are cleaned up on the next sync.

Firestore rules now prevent backend event documents from bypassing the dedicated `backendEvents` rule through the broad user-tree rule. This keeps career graph metadata flexible while requiring backend event outbox records to use the acknowledged event shape.

## Current Setup Status

- Firestore rules deploy successfully.
- Storage rules are tracked locally, but Firebase CLI currently reports that Firebase Storage still needs product setup in the Firebase console before rules can be released.
- The Firebase MCP environment has been authenticated locally, billing is enabled on `openlarp-dev-langqi`, and the iOS app `com.openlarp.app` exists in the Firebase project.
- Security rules validate through Firebase MCP.
- Emulator-based rules tests now exist under `firebase-rules/` and cover career graph document shapes, backend event spoofing, proof attachment Storage metadata, and upload receipt constraints. This workstation has OpenJDK 21 installed through Homebrew for local emulator verification.
- Firebase Functions config points to `backend/functions` with Node.js 22 and `runOpenLARPWorkflow` as the callable AI workflow boundary.

## Next Backend Steps

1. Enable Firebase Auth providers in the Firebase console, starting with Sign in with Apple and Google Sign-In.
2. Configure the non-committed `GOOGLE_REVERSED_CLIENT_ID` build setting for local live Google Sign-In testing.
3. Finish Firebase Storage product setup in the Firebase console, then deploy Storage rules.
4. Test live Google sign-in, Firestore career graph sync, and Storage proof attachment upload on a simulator or device with the ignored local Firebase plist.
5. Add a backend reconciliation job or callable repair flow for rare orphaned Storage objects if upload succeeds but a later upload or Firestore batch write fails.
6. Deploy Cloud Functions only after backend dependency advisories, prompts, evaluations, budget controls, and secrets are resolved.
7. Keep provider model IDs and API keys only on the backend.
8. Add App Check enforcement after local device and TestFlight auth flows are verified.

## Local Commands

```bash
npx -y firebase-tools@15.21.0 deploy --only firestore:rules --project openlarp-dev-langqi
npx -y firebase-tools@15.21.0 deploy --only storage:rules --project openlarp-dev-langqi
npm run build:backend
npx -y firebase-tools@15.21.0 emulators:start --project openlarp-rules-test --only auth,firestore,storage
npm run test:rules:emulators
```
