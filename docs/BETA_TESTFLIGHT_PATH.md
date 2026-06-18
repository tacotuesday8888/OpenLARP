# Beta And TestFlight Path

This document tracks the practical path from the current local product foundation to a credible TestFlight beta.

## Done In The Current Foundation

- Native SwiftUI app architecture remains local-first and testable.
- Backend session and event-sync interfaces exist.
- Firebase bootstrap and Firestore sync scaffolding are compile-gated so the app still builds without Firebase SDKs.
- Firestore and Storage security rules are tracked in the repo.
- AI workflow request envelopes keep private identifiers, model IDs, and provider credentials out of the iOS client.
- RevenueCat-shaped subscription contracts support free sprint, entitlement, restore, offline access, and expired states without importing the SDK.
- Beta measurement exports include AI, backend, quest, and payment readiness signals without private proof or billing identifiers.
- GitHub Actions now has an iOS build/test workflow.
- Firebase Apple SDKs and Google Sign-In packages are declared through XcodeGen/SPM while private plist config remains ignored.
- App composition uses Firebase-ready backend session and backend event sync services without breaking local/no-auth mode.
- Genkit backend package scaffolding exists with schemas, safety validation, deterministic testable flows, and backend-only Gemini model config.
- Firebase Callable Functions package exists for auth-required AI workflow dispatch while live model calls remain disabled, and its deploy package is kept free of Genkit runtime dependencies.
- Deterministic Firebase Callable Functions are deployed to the `openlarp-dev-langqi` dev project in `us-central1` with Node.js 22: `runOpenLARPWorkflow`, `promoteProofUploadReceipt`, `reconcileProofUploads`, and `acknowledgeBackendEvents`.
- The live callable endpoint is reachable and rejects unsigned workflow requests with `UNAUTHENTICATED`.
- Functions Artifact Registry cleanup policies are installed for the dev project so old deployment images do not accumulate without a retention policy.
- The iOS app now tries the Firebase callable Genkit route for core V0 AI workflows and falls back to local mock output when Firebase is missing, signed out, or unavailable.
- Authenticated proof upload reconciliation callable exists for report-only scans and explicit safe deletion of orphaned Storage proof uploads.
- Google Sign-In auth service boundary exists for restore, sign-in, sign-out, missing-config states, and callback URL handling.
- Google Sign-In is enabled in the Firebase dev project, the ignored local iOS plist has OAuth client IDs, and the XcodeGen project declares the public reversed client ID URL scheme.
- Firebase Storage is initialized in the Firebase dev project, and Storage rules are deployed for owner-scoped proof attachments.
- Firebase Storage proof attachment upload adapter exists and uploads owner-scoped proof bytes before server receipt promotion.
- `promoteProofUploadReceipt` verifies Storage object metadata with the Admin SDK and writes uploaded proof attachment receipts server-side.
- Firebase security rules tests exist for Firestore and Storage owner boundaries, upload metadata, server-owned proof attachment receipt protection, and nested local-path leak prevention.
- Firestore rules now deny arbitrary recursive user-subcollection writes, limit client writes to named beta sync collections, prevent clients from writing or downgrading uploaded proof attachment receipts, and keep backend event acknowledgement server-owned through `acknowledgeBackendEvents`.
- Authenticated callable functions now have per-user daily server-side quota units that reject with `resource-exhausted` before AI workflow dispatch, proof upload promotion, proof upload reconciliation, or backend event acknowledgement side effects.
- Subscription refresh, restore, paywall exposure, and one-time free sprint measurement are wired through the store boundary.

## Required Before TestFlight

1. Verify live Google Sign-In in the simulator/device with the refreshed ignored local plist, then add Sign in with Apple before broad external TestFlight/App Store review if Google remains a primary account option.
2. Test account-backed proof attachment uploads, Firestore career graph writes, and the signed-in deterministic callable AI fallback route.
3. Test the iOS callable route signed-out fallback behavior.
4. Add RevenueCat SDK, real entitlement IDs, purchase UI, and sandbox purchase verification.
5. Add App Check, signed-in quota exhaustion smoke tests, and provider-level token/cost accounting before treating all cloud data as authoritative or enabling live AI.
6. Decide whether TestFlight ships with deterministic backend AI only or waits for live Genkit/Gemini. Keep LLM providers server-side either way.
7. Add privacy policy, support URL, App Store screenshots, and TestFlight notes.
8. Run a signed archive on the Apple Developer team and upload to App Store Connect.

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
