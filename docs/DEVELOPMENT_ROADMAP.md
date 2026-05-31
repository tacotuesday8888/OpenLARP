# Development Roadmap

This roadmap is for building OpenLARP from the current SwiftUI starter shell into a usable V0. It is intentionally narrower than the long-term product roadmap.

## Current Baseline

OpenLARP currently has:

- A private GitHub repository
- A clean initial commit
- A native SwiftUI starter app
- Static sample data
- Planning and architecture docs
- A passing unsigned iOS build check

OpenLARP does not yet have:

- Real app state
- Real onboarding
- Real AI calls
- Backend/auth
- Persistence
- Proof uploads
- Subscriptions
- CI

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

Work:

- Choose backend/auth stack
- Add user accounts
- Store goals, quests, proof records, streaks, and progress
- Add privacy/memory controls
- Add basic request logging and rate limits

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
