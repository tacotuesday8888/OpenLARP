# Development Roadmap

This roadmap is for building OpenLARP from the current SwiftUI starter shell into a usable V0. It is intentionally narrower than the long-term product roadmap.

## Current Baseline

OpenLARP is now past the starter-shell baseline. The current app has a local-first V0 loop plus Firebase-ready beta infrastructure. It is suitable for deeper public beta hardening, but not yet for a fully service-backed App Store launch.

OpenLARP currently has:

- A private GitHub repository
- A native SwiftUI iOS app shell with Today, Map, Progress, and Profile tabs
- Guided four-step career onboarding with explicit fact confirmation, at most one material adaptive follow-up, and final approval
- Durable career understanding that separates user-confirmed facts, unconfirmed AI hypotheses, rejected suggestions, and explicit unknowns
- Backward-compatible schema-13 migration that preserves legacy facts, synthesizes an approved mission for existing active plans, and derives the correct active sprint phase without presenting new defaults as prior user claims
- Knownness-aware cloud goal mapping that omits newer legacy defaults when the provenanced understanding still marks them unknown
- Grounded "Am I Cooked?" evaluation with signals, gaps, missing information, uncertainty, and a first legitimate action
- An editable mission brief that keeps confirmed facts and ethical boundaries immutable and requires explicit approval before any quest exists
- Complete seven-day chapter-one quest generation bounded by the user's approved daily commitment
- A durable 14-day lifecycle with a grounded Day 7 report, metadata-only adaptive days 8–14, a Day 14 report, preserved sprint history, and a next-sprint path
- Local quest start, proof/self-report, mock quality check, XP, streak, badge, and readiness rules
- JSON persistence in the app documents directory
- Local text/link proof and app-private screenshot/photo attachment storage
- Proof receipts, proof detail, proof archive, completed quest detail, and map preview screens
- Daily cadence, intentional skip-today, and missed-day recovery behavior
- XCTest coverage for the core local behavior
- Firebase Auth, Firestore, Storage, Functions, Google Sign-In, and callable AI service boundaries behind local-safe adapters
- Optional Apple/Google account entry for service-enabled beta builds with a clearly explained device-only path; public local-only builds skip service controls, and service onboarding waits for the protected account workspace to resolve before accepting answers
- A development Firebase project with deployed Firestore/Storage rules and deterministic Gen 2 callable functions
- Server-trusted proof upload receipt promotion: the client uploads Storage bytes, then a callable verifies Storage metadata and writes the uploaded Firestore receipt
- Backend AI contracts, grounded structured Gemini workflows, post-generation truthfulness checks, a private Cloud Run runtime, authenticated callable dispatch, expiring runtime policy, per-user quota, provider budget ledger, deterministic fallbacks, adversarial evals, and CI/operations gates; deployment and live-development smoke remain pending
- RevenueCat/subscription contracts and local entitlement state, without live App Store products
- GitHub Actions CI plus local backend, rules, simulator, and unsigned iOS build validation gates

OpenLARP does not yet have:

- A deployed and live-smoked Genkit/Gemini path (the implementation remains disabled until the private service, callable configuration, IAM, and short-lived runtime policy are deployed)
- Fully server-authoritative career graph sync
- Push notifications
- Live App Store subscriptions/paywalls
- Production analytics dashboards
- TestFlight/App Store release setup

## Phase 0: Foundation

Goal: make the project safe to develop in.

Status: complete.

Included:

- Initialize Git
- Add iOS/Xcode `.gitignore`
- Commit starter app and docs
- Create private GitHub repo
- Push `main`
- Verify build with signing disabled
- Remove old shell-exported GitHub token from local shell profile

## Phase 1: Design Translation

Goal: turn the chosen Open Design direction into a buildable SwiftUI plan.

Work:

- Choose one V0 visual direction
- Identify screens that must be implemented first
- Map Open Design screens to SwiftUI views/components
- Decide what ShipSwift recipes to use
- Keep only V0 surfaces needed for the core loop

Deliverable:

- A short implementation spec for the V0 app shell

## Phase 2: V0 App Shell

Goal: make the app feel real before the engine is real.

Status: largely complete for the local-first V0. The active app shell now uses the state-driven local loop instead of static sample screens, and first-run setup is a short reviewable career-understanding flow instead of one long form.

Work:

- Replace the current static shell with the chosen visual direction
- Build onboarding screens
- Build cooked diagnostic result screens
- Build Today quest flow
- Build proof submission flow with local/mock data
- Build AI quality check result screen with mock results
- Build XP, streak, badge, and progress feedback
- Build share card preview screen
- Keep data mocked but structured

Success criteria:

- A user can tap through the full V0 loop
- The app has no dead-end screens
- Every primary action has a clear next state
- The UX matches the V0 product loop

## Phase 3: Local Product Engine

Goal: make the mocked app logic coherent before adding cloud services.

Status: largely complete for local beta validation. The app has local state models, deterministic engine rules, JSON persistence, provenanced career facts and explicit unknowns, proof receipts, local proof attachments, daily cadence, skip, missed-day recovery, and XCTest coverage.

Work:

- Add app state models
- Add onboarding state
- Require reviewed career understanding before committing a goal, diagnostic, or plan
- Add quest state
- Add proof state
- Add XP/streak/progress rules
- Add local persistence
- Add deterministic mock diagnostic and quest generation logic

Success criteria:

- The app remembers local progress
- Completing quests changes visible state
- Weak/strong proof paths behave differently
- Streak and progress rules are testable

## Phase 4: AI Integration

Goal: connect AI to narrow, controlled V0 jobs.

Status: partially complete. Narrow grounded Genkit/Gemini workflows, strict schemas, post-generation safety validation, a private Cloud Run service, authenticated Firebase callable routing, per-user quota, provider budget controls, expiring workflow policy, deterministic fallbacks, adversarial truthfulness evals, redacted smoke tooling, and CI gates are implemented locally. Adaptive intake is integrated into first-run review with a one-question limit, explicit unknown handling, and confirm/edit/reject decisions for AI hypotheses. Cooked evaluation now feeds an editable, explicitly approved mission; trusted inputs are exact-echo validated, and only approval can create a complete seven-day first chapter. Day 7 produces a grounded checkpoint and an adaptive second chapter using counters and proof-quality metadata without transmitting private proof bodies, links, or attachment data; Day 14 produces a durable sprint report. Live service behavior still requires deployment and authenticated development smoke validation.

Work:

- Define strict request/response schemas
- Add cooked diagnostic generation
- Add grounded editable mission generation and explicit approval
- Add daily quest generation
- Add proof quality check
- Add progress summary generation
- Add safety rules against fake claims
- Add fallback states when AI fails

Success criteria:

- AI output is structured
- Failed AI calls do not block the user
- The app never encourages fake employers, schools, certificates, titles, dates, projects, or ownership claims

## Phase 5: Backend And Accounts

Goal: make V0 usable across sessions/devices.

Status: partially complete for beta infrastructure. Firebase Auth/Google Sign-In, Firestore, Storage, Cloud Functions, Security Rules, backend events, career graph sync previews, server-owned private evidence cloud sync consent gates, proof upload Storage writes, server-trusted proof upload receipt promotion, server-owned uploaded proof backup cleanup after revoked consent, server-owned backend event acknowledgement, server-owned account deletion, in-app account data controls, server-side per-user callable quotas, backend-only provider token/cost estimates, live readiness checks, signed-in CLI smoke tooling, iOS App Check provider scaffolding, private AI-service implementation, provider budget controls, expiring kill-switch policy, evals, and release gates exist. The remaining trust work includes the private service/IAM/callable deployment and live smoke, signed-in simulator/device account UX testing, account-controls privacy/legal/support copy, Firebase Console App Check registration and enforcement, derived readiness/history writes, and production-grade sync repair UX.

Work:

- Keep Firebase Auth/Google Sign-In as the current backend/auth stack
- Keep the signed-in Firebase CLI smoke passing before backend-readiness passes
- Finish account-backed Google Sign-In and sync smoke tests on simulator/device
- Keep backend event acknowledgement server-owned through Cloud Functions
- Register App Check in Firebase Console, keep simulator debug tokens private, verify metrics from opt-in simulator/debug and App Attest device builds, then enable enforcement
- Deploy with reviewed current provider pricing and a small daily budget, keep metadata-only observability/evals/audits green, and complete an authenticated live smoke before enabling even controlled beta traffic
- Keep explicit server-owned private evidence cloud sync consent separate from public sharing language
- Keep uploaded proof backup cleanup separate from consent revocation, and verify the user-facing account/private-data controls before broad beta

Success criteria:

- User data survives reinstall/device changes
- Sensitive data has clear controls
- Backend is simple enough for V0 but not throwaway

## Phase 6: Monetization And Launch

Goal: prepare the first validation sprint.

Work:

- Add 14-day sprint/subscription flow
- Add student discount logic if needed
- Add share cards
- Add waitlist/website integration
- Add basic analytics
- Prepare App Store/TestFlight path

Success criteria:

- Users can start a free sprint
- Users can understand what they are paying for
- Sharing does not expose private details by default
- The team can measure activation, retention, and conversion

## Engineering Rules

- Keep V0 narrow.
- Build the daily quest loop before the long-term agent.
- Prefer real proof and progress over empty gamification.
- Use ShipSwift for useful UI/motion/payment/share recipes, not core logic.
- Keep secrets out of Git.
- Commit small, reviewable changes.
- Verify with build/tests before claiming work is done.
