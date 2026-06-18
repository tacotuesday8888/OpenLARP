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

## Required Before TestFlight

1. Add Firebase SDK packages and real sign-in UI.
2. Enable Firebase Auth providers and test account sync on device.
3. Add the backend Genkit/Cloud Run service for AI workflows and keep LLM providers server-side.
4. Add RevenueCat SDK, real entitlement IDs, restore purchases, and sandbox purchase verification.
5. Add privacy policy, support URL, App Store screenshots, and TestFlight notes.
6. Run a signed archive on the Apple Developer team and upload to App Store Connect.

## What Should Wait For Designer HTML

- Full visual redesign
- Marketing polish
- Final paywall presentation
- Pixel-level SwiftUI styling

The current priority remains product foundation, account sync, backend AI boundaries, payment readiness, and verification.
