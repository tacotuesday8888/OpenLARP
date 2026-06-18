# Development Roadmap

This roadmap is for building OpenLARP from the current SwiftUI starter shell into a usable V0. It is intentionally narrower than the long-term product roadmap.

## Current Baseline

OpenLARP is now past the starter-shell baseline. The current app has a local-first V0 loop plus Firebase-ready beta infrastructure. It is suitable for deeper public beta hardening, but not yet for a fully service-backed App Store launch.

OpenLARP currently has:

- A private GitHub repository
- A native SwiftUI iOS app shell with Today, Map, Progress, and Profile tabs
- Local goal setup
- Deterministic local "Am I Cooked?" diagnostic logic
- Local seven-day quest generation
- Local quest start, proof/self-report, mock quality check, XP, streak, badge, and readiness rules
- JSON persistence in the app documents directory
- Local text/link proof and app-private screenshot/photo attachment storage
- Proof receipts, proof detail, proof archive, completed quest detail, and map preview screens
- Daily cadence, intentional skip-today, and missed-day recovery behavior
- XCTest coverage for the core local behavior
- Firebase Auth, Firestore, Storage, Functions, Google Sign-In, and callable AI service boundaries behind local-safe adapters
- A development Firebase project with deployed Firestore/Storage rules and deterministic Gen 2 callable functions
- Server-trusted proof upload receipt promotion: the client uploads Storage bytes, then a callable verifies Storage metadata and writes the uploaded Firestore receipt
- Backend AI contracts and a deterministic callable workflow boundary, with live model calls disabled until Genkit/Gemini safety, budget, and dependency work is ready
- RevenueCat/subscription contracts and local entitlement state, without live App Store products
- GitHub Actions CI plus local backend, rules, simulator, and unsigned iOS build validation gates

OpenLARP does not yet have:

- Live Genkit/Gemini model calls
- Fully server-authoritative career graph sync
- Server-owned backend event acknowledgement
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

Status: largely complete for the local-first V0. The active app shell now uses the state-driven local loop instead of static sample screens.

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

Status: largely complete for local beta validation. The app has local state models, deterministic engine rules, JSON persistence, proof receipts, local proof attachments, daily cadence, skip, missed-day recovery, and XCTest coverage.

Work:

- Add app state models
- Add onboarding state
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

Status: partially complete as a backend-ready boundary. Current diagnostic, quest, proof check, and progress behavior is deterministic local/mock logic; authenticated Firebase callable routing exists, but live model calls remain disabled.

Work:

- Define strict request/response schemas
- Add cooked diagnostic generation
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

Status: partially complete for beta infrastructure. Firebase Auth/Google Sign-In, Firestore, Storage, Cloud Functions, Security Rules, backend events, career graph sync previews, proof upload Storage writes, server-trusted proof upload receipt promotion, server-owned backend event acknowledgement, server-side per-user callable quotas, live readiness checks, signed-in CLI smoke tooling, and iOS App Check provider scaffolding exist. The remaining trust work is signed-in simulator/device Google Sign-In UX testing, Firebase Console App Check registration and enforcement, provider-level token/cost accounting, derived readiness/history writes, and production-grade sync repair UX.

Work:

- Keep Firebase Auth/Google Sign-In as the current backend/auth stack
- Keep the signed-in Firebase CLI smoke passing before backend-readiness passes
- Finish account-backed Google Sign-In and sync smoke tests on simulator/device
- Keep backend event acknowledgement server-owned through Cloud Functions
- Register App Check in Firebase Console, keep simulator debug tokens private, verify metrics from opt-in simulator/debug and App Attest device builds, then enable enforcement
- Add provider-level token/cost accounting before live AI or broad beta traffic
- Add explicit cloud backup consent separate from public sharing language

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
