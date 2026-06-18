# Firebase Backend Setup

OpenLARP now has a Firebase-ready backend boundary without requiring the iOS client to call AI providers directly.

## Current Dev Project

- Firebase project ID: `openlarp-dev-langqi`
- iOS bundle ID: `com.openlarp.app`
- Firestore database: default database in `nam5`
- Tracked config files: `.firebaserc`, `firebase.json`, `firestore.rules`, `storage.rules`
- Local-only config file: `OpenLARP/GoogleService-Info.plist`

`OpenLARP/GoogleService-Info.plist` is intentionally ignored by Git. The generated Xcode project also excludes it so private local config is not accidentally committed or required in CI. When Firebase SDKs are linked for live auth testing, add a local-only Debug copy step or another non-committed configuration path before expecting Firebase to configure at runtime.

## What Exists In iOS

- `BackendSessionProviding` abstracts the current signed-in account/session.
- `LocalMockBackendSessionProvider` keeps local builds unauthenticated and safe.
- `FirebaseBackendSessionProvider` is compile-gated behind Firebase SDK imports and can expose the current Firebase Auth user when the SDK is linked.
- `FirebaseFirestoreBackendEventSyncService` is compile-gated and writes backend event outbox records to `users/{uid}/backendEvents/{eventId}` when Firebase Firestore is linked.
- `FirebaseReadyBackendEventSyncService` routes authenticated sessions to Firestore and keeps events pending when Firebase Auth needs sign-in or Firebase runtime config is missing.
- `FirebaseGoogleSignInAuthenticationService` provides a Google Sign-In boundary for restore, sign-in, sign-out, and URL handling without faking success when setup is incomplete.
- `OpenLARPFirebaseBootstrap.configureIfAvailable()` configures Firebase only when the SDK and plist are both available.

The Firebase adapters also check that `FirebaseApp` is configured before touching Auth or Firestore. This lets CI and local mock builds continue safely when Firebase SDKs are linked but private runtime configuration has not been bundled.

Firebase Apple SDK products are now linked through Swift Package Manager via `project.yml`:

- `FirebaseCore`
- `FirebaseAuth`
- `FirebaseFirestore`
- `FirebaseStorage`

Google Sign-In packages are also linked as the next auth UI integration point:

- `GoogleSignIn`
- `GoogleSignInSwift`

`GoogleService-Info.plist` remains ignored by Git and excluded from normal XcodeGen sources. The generated Xcode project includes an optional post-build copy script that copies the local plist into the app bundle only when the ignored local file exists.

## Security Rules

Firestore rules currently allow signed-in users to read/write only under their own `users/{uid}` tree and prevent client writes that claim external actions were taken.

Storage rules currently reserve this path:

```text
users/{uid}/proofAttachments/{attachmentId}
```

Only the signed-in owner can read/write proof attachments, and uploads are limited to images, PDFs, and plain text under 10 MB.

## Current Setup Status

- Firestore rules deploy successfully.
- Storage rules are tracked locally, but Firebase CLI currently reports that Firebase Storage still needs product setup in the Firebase console before rules can be released.
- The Firebase MCP environment is authenticated for `langqizhao1@gmail.com`, billing is enabled on `openlarp-dev-langqi`, and the iOS app `com.openlarp.app` exists in the Firebase project.
- Security rules validate through Firebase MCP.
- Emulator-based rules tests now exist under `firebase-rules/`. This workstation has OpenJDK 21 installed through Homebrew for local emulator verification.
- Firebase Functions config points to `backend/functions` with Node.js 22 and `runOpenLARPWorkflow` as the callable AI workflow boundary.

## Next Backend Steps

1. Enable Firebase Auth providers in the Firebase console, starting with Sign in with Apple and Google Sign-In.
2. Add Google Sign-In UI presentation and `.onOpenURL` forwarding in the app.
3. Add Firestore career graph document uploads and Storage proof attachment uploads behind the existing sync boundaries.
4. Deploy Cloud Functions only after backend dependency advisories, prompts, evaluations, budget controls, and secrets are resolved.
5. Keep provider model IDs and API keys only on the backend.
6. Add App Check enforcement after local device and TestFlight auth flows are verified.

## Local Commands

```bash
firebase deploy --only firestore:rules --project openlarp-dev-langqi
firebase deploy --only storage:rules --project openlarp-dev-langqi
npm run build:backend
firebase emulators:start --only auth,firestore,storage
npm run test:rules:emulators
```
