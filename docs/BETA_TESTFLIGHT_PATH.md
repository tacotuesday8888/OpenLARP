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
- Firebase Callable Functions package exists for auth-required AI workflow dispatch while live model calls remain disabled.
- Google Sign-In auth service boundary exists for restore, sign-in, sign-out, missing-config states, and future URL handling.
- Firebase security rules tests exist for Firestore and Storage owner boundaries.
- Subscription refresh, restore, paywall exposure, and one-time free sprint measurement are wired through the store boundary.

## Required Before TestFlight

1. Enable Firebase Auth providers and add real sign-in UI plus `.onOpenURL` forwarding.
2. Test account-backed event sync, Firestore career graph writes, and Storage proof attachment uploads on device.
3. Deploy the backend Genkit Cloud Functions or Cloud Run service for AI workflows and keep LLM providers server-side.
4. Add RevenueCat SDK, real entitlement IDs, purchase UI, and sandbox purchase verification.
5. Add privacy policy, support URL, App Store screenshots, and TestFlight notes.
6. Run a signed archive on the Apple Developer team and upload to App Store Connect.

## Backend Dependency Risk

`npm audit --omit=dev --audit-level=high` currently reports upstream Genkit/OpenTelemetry transitive advisories. Keep live AI disabled until the backend dependency tree is upgraded or pinned to advisory-free versions, and run a fresh audit before deployment.

## What Should Wait For Designer HTML

- Full visual redesign
- Marketing polish
- Final paywall presentation
- Pixel-level SwiftUI styling

The current priority remains product foundation, account sync, backend AI boundaries, payment readiness, and verification.
