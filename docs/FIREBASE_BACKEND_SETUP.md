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
- `OpenLARPFirebaseBootstrap.configureIfAvailable()` configures Firebase only when the SDK and plist are both available.

The Firebase adapters also check that `FirebaseApp` is configured before touching Auth or Firestore. This lets CI and local mock builds continue safely when Firebase SDKs are linked but private runtime configuration has not been bundled.

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

## Next Backend Steps

1. Add Firebase SDKs through Swift Package Manager: `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`, and `FirebaseStorage`.
2. Enable Firebase Auth providers in the Firebase console, starting with Sign in with Apple and Google Sign-In.
3. Wire the app root to use `FirebaseBackendSessionProvider` and `FirebaseFirestoreBackendEventSyncService` once sign-in exists.
4. Add Cloud Run or Cloud Functions endpoints for Genkit-backed AI workflows.
5. Keep provider model IDs and API keys only on the backend.
6. Add App Check enforcement after local device and TestFlight auth flows are verified.

## Local Commands

```bash
firebase deploy --only firestore:rules --project openlarp-dev-langqi
firebase deploy --only storage:rules --project openlarp-dev-langqi
firebase emulators:start --only auth,firestore,storage
```
