# Beta And TestFlight Path

This document tracks the practical path from the current local product foundation to a credible TestFlight beta.

## Done In The Current Foundation

- Native SwiftUI app architecture remains local-first and testable.
- Backend session and event-sync interfaces exist.
- Firebase bootstrap and Firestore sync scaffolding are compile-gated so the app still builds without Firebase SDKs.
- Firestore and Storage security rules are tracked in the repo.
- AI workflow request envelopes keep private identifiers, model IDs, and provider credentials out of the iOS client.
- RevenueCat-shaped subscription contracts support free sprint, entitlement, restore, offline access, and expired states.
- RevenueCat iOS SDK `5.79.0` is linked through XcodeGen/SPM behind `OpenLARPSubscriptionServicing`, with ignored local plist configuration and a no-key fallback that keeps local beta mode working.
- Beta measurement exports include AI, backend, quest, and payment readiness signals without private proof or billing identifiers.
- GitHub Actions now has an iOS build/test workflow.
- Firebase Auth, Sign in with Apple capability, and Google Sign-In packages are declared through XcodeGen/SPM while private plist config remains ignored.
- App composition uses Firebase-ready backend session and backend event sync services without breaking local/no-auth mode.
- Genkit backend package scaffolding exists with schemas, safety validation, deterministic testable flows, and backend-only Gemini model config.
- Firebase Callable Functions package exists for auth-required AI workflow dispatch while live model calls remain disabled, and its deploy package is kept free of Genkit runtime dependencies.
- Deterministic Firebase Callable Functions are deployed to the `openlarp-dev-langqi` dev project in `us-central1` with Node.js 22: `runOpenLARPWorkflow`, `setPrivateEvidenceCloudSyncConsent`, `promoteProofUploadReceipt`, `reconcileProofUploads`, `cleanupRevokedPrivateEvidenceUploads`, `acknowledgeBackendEvents`, and `deleteOpenLARPAccount`.
- The live callable endpoint is reachable and rejects unsigned workflow requests with `UNAUTHENTICATED`.
- Functions Artifact Registry cleanup policies are installed for the dev project so old deployment images do not accumulate without a retention policy.
- The iOS app now tries the Firebase callable Genkit route for core V0 AI workflows and falls back to local mock output when Firebase is missing, signed out, or unavailable.
- Authenticated proof upload reconciliation callable exists for report-only scans and explicit safe deletion of orphaned Storage proof uploads.
- Firebase Auth service boundary exists for restore, Google sign-in, Apple sign-in, sign-out, missing-config states, callback URL handling, and Apple token revocation preparation before account deletion.
- Google Sign-In is enabled in the Firebase dev project, the ignored local iOS plist has OAuth client IDs, and the XcodeGen project declares the public reversed client ID URL scheme.
- Firebase Storage is initialized in the Firebase dev project, and Storage rules are deployed for owner-scoped proof attachments.
- Firebase Storage proof attachment upload adapter exists and uploads owner-scoped proof bytes before server receipt promotion.
- `promoteProofUploadReceipt` verifies Storage object metadata with the Admin SDK and writes uploaded proof attachment receipts server-side.
- Firebase security rules tests exist for Firestore and Storage owner boundaries, upload metadata, server-owned proof attachment receipt protection, and nested local-path leak prevention.
- Firestore rules now deny arbitrary recursive user-subcollection writes, limit client writes to named beta sync collections, prevent clients from writing or downgrading uploaded proof attachment receipts, and keep backend event acknowledgement server-owned through `acknowledgeBackendEvents`.
- Authenticated callable functions now have per-user daily server-side quota units that reject with `resource-exhausted` before AI workflow dispatch, proof upload promotion, proof upload reconciliation, or backend event acknowledgement side effects.
- Signed-in Firebase CLI smoke tooling exists to verify workflow callable auth, proof Storage object verification, proof receipt promotion, proof upload reconciliation, backend event acknowledgement, and cleanup of temporary smoke data in the dev project.
- Private proof records, proof attachment metadata, and proof attachment Storage uploads are gated behind explicit server-owned private evidence cloud sync consent. Public "share wins" permission no longer allows private proof backup by itself.
- Uploaded proof backup cleanup after revoked consent has a server-owned callable foundation. It defaults to report-only, requires explicit attachment IDs plus deletion confirmation for deletes, and returns per-item skipped/deleted/partial-failure statuses. It is not a full account/private-data deletion feature.
- Account deletion has a server-owned callable foundation. It requires recent Firebase Auth and exact destructive confirmation, writes a minimal retained deletion marker that blocks stale client and Admin callable writes, deletes the user Storage prefix, Firestore user tree, hashed quota tree, and then the Firebase Auth user, and reports partial failures including marker-finalization failures for retry/support handling.
- Profile now exposes account controls for Google/Apple sign-in plus signed-in account data controls: report-only synced private proof backup checks, confirmed eligible backup deletion, exact-phrase cloud account deletion, and partial-failure result visibility for retry/support. Local on-device career progress is intentionally kept separate from cloud account deletion.
- Cloud account deletion now requires provider reauthentication before the destructive callable: Apple sessions request a fresh Apple credential and token revocation, while Google sessions request a fresh Google Sign-In credential and Firebase reauthentication. If the backend response is lost after the request starts, iOS persists an `unknown` deletion result for retry/support instead of hiding the ambiguity behind a transient error.
- iOS App Check provider scaffolding is linked, real-device builds have the production App Attest entitlement, and simulator debug App Check is explicit opt-in to avoid leaking debug tokens in logs. Firebase product enforcement is still off until console registration, debug tokens, and device metrics are verified.
- Subscription refresh, restore, paywall exposure, one-time free sprint measurement, and RevenueCat customer-info mapping are wired through the store boundary.

## Required Before TestFlight

1. Verify live Google Sign-In and Sign in with Apple in the simulator/device with the refreshed ignored local plist, signed Apple capability, Firebase Auth providers enabled, and regenerated provisioning profiles.
2. Run `npm run firebase:signed-in-smoke` before each backend-readiness pass, then test account-backed proof attachment uploads, Firestore career graph writes, and the signed-in deterministic callable AI fallback route on a simulator/device.
3. Test the iOS callable route signed-out fallback behavior.
4. Verify uploaded proof backup cleanup and account deletion controls on signed-in Google and Apple simulator/device sessions, including Google recent reauthentication, Apple token revocation before deletion, lost-response/unknown-result support handling, then finalize privacy/legal/support copy for broad external TestFlight.
5. Create RevenueCat/App Store products, add ignored local `RevenueCat-Info.plist`, implement purchase UI/actions, and complete sandbox purchase verification.
6. Register App Check in Firebase Console, register simulator debug tokens as private secrets, verify device App Attest metrics, update live smoke tooling for App Check tokens, then enable App Check enforcement before treating all cloud data as authoritative or enabling live AI.
7. Decide whether TestFlight ships with deterministic backend AI only or waits for live Genkit/Gemini. Keep LLM providers server-side either way.
8. Add privacy policy, support URL, App Store screenshots, and TestFlight notes.
9. Run a signed archive on the Apple Developer team and upload to App Store Connect.

## Live Dev Readiness Check

Use this command before each TestFlight-readiness pass:

```bash
npm run firebase:live-readiness
```

Expected current result is a clean pass with no missing Google OAuth ID or missing Storage bucket warnings. A clean readiness script does not replace the required signed-in simulator/device smoke test for Google Sign-In, Firestore writes, Storage proof upload/read rules, and callable fallback behavior.

## Backend Dependency Risk

`npm audit --workspace backend/ai --omit=dev --audit-level=high` currently reports upstream Genkit/OpenTelemetry transitive advisories. Keep live Genkit/Gemini AI disabled until the backend dependency tree is upgraded or pinned to advisory-free versions, and run a fresh audit before deployment.

## What Should Wait For Designer HTML

- Full visual redesign
- Marketing polish
- Final paywall presentation
- Pixel-level SwiftUI styling

The current priority remains product foundation, account sync, backend AI boundaries, payment readiness, and verification.
