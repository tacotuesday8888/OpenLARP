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
- Deterministic Firebase Callable Functions are deployed to the `openlarp-dev-langqi` dev project in `us-central1` with Node.js 22: `runOpenLARPWorkflow` and `reconcileProofUploads`.
- The live callable endpoint is reachable and rejects unsigned workflow requests with `UNAUTHENTICATED`.
- Functions Artifact Registry cleanup policies are installed for the dev project so old deployment images do not accumulate without a retention policy.
- The iOS app now tries the Firebase callable Genkit route for core V0 AI workflows and falls back to local mock output when Firebase is missing, signed out, or unavailable.
- Authenticated proof upload reconciliation callable exists for report-only scans and explicit safe deletion of orphaned Storage proof uploads.
- Google Sign-In auth service boundary exists for restore, sign-in, sign-out, missing-config states, and future URL handling.
- Firebase Storage proof attachment upload adapter exists and writes owner-scoped upload receipts before Firestore metadata sync.
- Firebase security rules tests exist for Firestore and Storage owner boundaries, upload metadata, proof attachment receipt shape, and nested local-path leak prevention.
- Subscription refresh, restore, paywall exposure, and one-time free sprint measurement are wired through the store boundary.

## Required Before TestFlight

1. Enable Firebase Auth providers, refresh the ignored local iOS plist, set the non-committed `GOOGLE_REVERSED_CLIENT_ID`, and verify live Google Sign-In in the simulator.
2. Finish Firebase Storage product setup, deploy Storage rules, and test account-backed proof attachment uploads plus Firestore career graph writes.
3. Test the iOS callable route against live Firebase Auth, including signed-in deterministic AI fallback behavior and signed-out fallback behavior.
4. Add RevenueCat SDK, real entitlement IDs, purchase UI, and sandbox purchase verification.
5. Decide whether TestFlight ships with deterministic backend AI only or waits for live Genkit/Gemini. Keep LLM providers server-side either way.
6. Add privacy policy, support URL, App Store screenshots, and TestFlight notes.
7. Run a signed archive on the Apple Developer team and upload to App Store Connect.

## Live Dev Readiness Check

Use this command before each TestFlight-readiness pass:

```bash
npm run firebase:live-readiness
```

Expected current warnings are missing Google OAuth IDs in the downloaded iOS config and missing Firebase Storage initialization. Those warnings must be cleared before a true account-backed beta smoke test.

## Backend Dependency Risk

`npm audit --workspace backend/ai --omit=dev --audit-level=high` currently reports upstream Genkit/OpenTelemetry transitive advisories. Keep live Genkit/Gemini AI disabled until the backend dependency tree is upgraded or pinned to advisory-free versions, and run a fresh audit before deployment.

## What Should Wait For Designer HTML

- Full visual redesign
- Marketing polish
- Final paywall presentation
- Pixel-level SwiftUI styling

The current priority remains product foundation, account sync, backend AI boundaries, payment readiness, and verification.
