# Daily Cadence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first daily cadence so completing Today's quest shows a done-for-today state and keeps the next quest locked until the next local calendar day.

**Architecture:** Persist a small `DailyCadenceState` inside `OpenLARPState`, record completion metadata during `claim`, and add a refresh function that unlocks the next quest only after the local calendar day changes. Today renders a model-backed completion state while Map continues to show the next quest as locked.

**Tech Stack:** Swift 6, SwiftUI, Foundation `Calendar`, XCTest, local JSON persistence.

---

### Task 1: Daily Cadence State Tests

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Models/OpenLARPEngine.swift`

- [x] **Step 1: Add failing tests**

Add tests proving that claiming a quest keeps the next quest locked the same day, `refreshDailyAvailability` keeps it locked on the same local day, and refresh unlocks it on the next local day.

- [x] **Step 2: Run focused tests and confirm red**

Run: `xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenLARPTests/V0EngineTests/testClaimLocksNextQuestUntilNextLocalDay`

Expected: fails because daily cadence model/functions do not exist yet.

- [x] **Step 3: Implement model and engine changes**

Add `DailyCadenceState`, backward-compatible `OpenLARPState` decoding, claim-time daily completion recording, and `refreshDailyAvailability`.

- [x] **Step 4: Run focused tests and confirm green**

Run the focused daily cadence tests and confirm they pass.

### Task 2: Today Done-For-Today UI

**Files:**
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Views/TodayView.swift`
- Modify: `OpenLARP/Views/AppRootView.swift`

- [x] **Step 1: Add failing content tests**

Add tests for `TodayCompletionContent` showing completed title/result, XP/streak, proof receipt, next quest preview, tomorrow unlock copy, and final-track copy when there is no next quest.

- [x] **Step 2: Implement content helper and Today UI**

Render a done-for-today card when today's quest was completed locally. Include proof receipt access and a next quest preview without any start/proof actions.

- [x] **Step 3: Refresh availability on app/store entry points**

Refresh daily availability when the store loads and when the app shell appears or changes tabs.

### Task 3: Verification And Delivery

**Files:**
- Modify as needed based on implementation

- [x] **Step 1: Run focused tests**

Run focused model/content tests for the daily cadence behavior.

- [x] **Step 2: Run full simulator tests**

Run the full `OpenLARPTests` suite.

- [x] **Step 3: Run signing-disabled build**

Run the `xcodebuild` command from `AGENTS.md`.

- [ ] **Step 4: Simulator smoke check**

Complete a quest, confirm Today shows done for today, confirm Map shows the next quest locked, and confirm next-day unlock is covered by tests.

- [ ] **Step 5: Commit, push, PR, merge, cleanup**

Inspect diff and secrets, commit intentional files, push the branch, open a PR, monitor checks/review, merge when green, delete the branch, and confirm clean `main`.
