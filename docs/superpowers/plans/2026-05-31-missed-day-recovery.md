# Missed-Day Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first missed-day recovery state so a returning user sees clear streak behavior and can continue the next quest.

**Architecture:** Keep the existing local engine/store architecture. Extend persisted state with a small recovery record, update `refreshDailyAvailability` to distinguish same-day, normal next-day, and skipped-day returns, and let Today render recovery before the normal quest card.

**Tech Stack:** Swift, SwiftUI, XCTest, local JSON persistence, Foundation `Calendar`.

---

### Task 1: Prove Missed-Day Behavior With Tests

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`

- [x] **Step 1: Add tests for same-day, next-day, skipped-day, active streak reset, and continuing**

Add tests that use the existing `completedFirstQuestState(claimTime:)` helper and deterministic Gregorian UTC calendar:

```swift
func testRefreshDailyAvailabilityDoesNotShowMissedDayOnSameLocalDay() throws {
    let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
    let sameDayLater = localDate(year: 2026, month: 5, day: 31, hour: 22)
    let state = try completedFirstQuestState(claimTime: claimTime)

    let refreshed = OpenLARPEngine.refreshDailyAvailability(
        in: state,
        now: sameDayLater,
        calendar: testCalendar
    )

    XCTAssertNil(refreshed.missedDayRecovery.startedAt)
    XCTAssertEqual(refreshed.progress.streakCount, 1)
    XCTAssertNil(MissedDayRecoveryContent(state: refreshed))
}

func testRefreshDailyAvailabilityUnlocksNextDayWithoutMissedDayWarning() throws {
    let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
    let nextDay = localDate(year: 2026, month: 6, day: 1, hour: 8)
    let state = try completedFirstQuestState(claimTime: claimTime)

    let refreshed = OpenLARPEngine.refreshDailyAvailability(
        in: state,
        now: nextDay,
        calendar: testCalendar
    )

    XCTAssertNil(refreshed.missedDayRecovery.startedAt)
    XCTAssertEqual(refreshed.progress.streakCount, 1)
    XCTAssertEqual(refreshed.currentQuest?.id, refreshed.plan[1].id)
}

func testRefreshDailyAvailabilityShowsRecoveryAfterSkippingAvailableQuestDay() throws {
    let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
    let skippedReturn = localDate(year: 2026, month: 6, day: 2, hour: 8)
    let state = try completedFirstQuestState(claimTime: claimTime)

    let refreshed = OpenLARPEngine.refreshDailyAvailability(
        in: state,
        now: skippedReturn,
        calendar: testCalendar
    )

    XCTAssertEqual(refreshed.plan[1].status, .available)
    XCTAssertEqual(refreshed.progress.streakCount, 0)
    XCTAssertEqual(refreshed.missedDayRecovery.missedDayCount, 1)
    XCTAssertEqual(refreshed.missedDayRecovery.nextQuestID, refreshed.plan[1].id)
}

func testMissedDayRecoveryContentExplainsStreakAndNextQuest() throws {
    let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
    let skippedReturn = localDate(year: 2026, month: 6, day: 3, hour: 8)
    let state = OpenLARPEngine.refreshDailyAvailability(
        in: try completedFirstQuestState(claimTime: claimTime),
        now: skippedReturn,
        calendar: testCalendar
    )

    let content = try XCTUnwrap(MissedDayRecoveryContent(state: state))

    XCTAssertEqual(content.title, "Streak reset, track still alive")
    XCTAssertEqual(content.missedDaysText, "You missed 2 quest days.")
    XCTAssertEqual(content.nextQuestTitle, state.plan[1].title)
    XCTAssertEqual(content.primaryActionTitle, "Continue Next Quest")
}

func testStartingCurrentQuestClearsMissedDayRecovery() throws {
    let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
    let skippedReturn = localDate(year: 2026, month: 6, day: 2, hour: 8)
    var state = OpenLARPEngine.refreshDailyAvailability(
        in: try completedFirstQuestState(claimTime: claimTime),
        now: skippedReturn,
        calendar: testCalendar
    )

    state = try OpenLARPEngine.startCurrentQuest(in: state, now: skippedReturn)

    XCTAssertEqual(state.plan[1].status, .inProgress)
    XCTAssertEqual(state.missedDayRecovery, .empty)
    XCTAssertEqual(state.progress.streakCount, 0)
}
```

- [x] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenLARPTests/V0EngineTests
```

Expected: tests fail because `missedDayRecovery`, `MissedDayRecoveryContent`, and missed-day logic do not exist yet.

### Task 2: Add Persisted Recovery State And Engine Rules

**Files:**
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Models/OpenLARPEngine.swift`

- [x] **Step 1: Add `MissedDayRecoveryState` and content model**

Add a Codable state object with optional `startedAt`, `missedDayCount`, `lastCompletedQuestID`, `nextQuestID`, and `previousStreakCount`. Add `missedDayRecovery` to `OpenLARPState`, with custom decoding defaulting to `.empty`.

- [x] **Step 2: Update refresh behavior**

In `refreshDailyAvailability`, keep existing same-day behavior. On the next local calendar day, unlock next quest and clear daily cadence without recovery. If `now` is more than one local day after `nextUnlockDate`, unlock the next quest, set `progress.streakCount` to `0`, persist recovery metadata, and clear `dailyCadence`.

- [x] **Step 3: Clear recovery when the user starts the available quest**

When `startCurrentQuest` succeeds, set `missedDayRecovery = .empty`. This makes the recovery notice a re-entry state, not a permanent penalty banner.

- [x] **Step 4: Run focused tests and verify GREEN**

Run the same focused test command. Expected: missed-day tests pass.

### Task 3: Render Recovery In Today And Streak Surfaces

**Files:**
- Modify: `OpenLARP/Views/TodayView.swift`
- Modify: `OpenLARP/Views/ProfileView.swift`
- Modify: `OpenLARP/Views/ProgressTabView.swift`
- Modify: `OpenLARP/Views/QuestMapView.swift` if map copy needs clarity

- [x] **Step 1: Add recovery card above the normal quest card**

In `TodayView.questCard`, check `MissedDayRecoveryContent(state:)` before `currentQuest`. Render a plain card with:

- "Streak reset, track still alive"
- missed-day text
- supportive body copy
- next quest title/objective
- primary button "Continue Next Quest" that calls `store.startCurrentQuest()`

- [x] **Step 2: Clarify active streak in progress/profile**

Show the current active streak count after reset, and include a small note when recovery is active so the user is not misled by an old streak.

- [x] **Step 3: Build after UI changes**

Run:

```bash
xcodebuild -project OpenLARP.xcodeproj -scheme OpenLARP -destination generic/platform=iOS -derivedDataPath /private/tmp/OpenLARPDerivedData CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

### Task 4: Validate, Commit, Publish, And Merge

**Files:**
- All touched source, tests, and this plan.

- [x] **Step 1: Run focused and full tests**

Run:

```bash
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenLARPTests/V0EngineTests
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [x] **Step 2: Run build, diff check, and secret scan**

Run the signing-disabled build from `AGENTS.md`, `git diff --check`, and a scoped credential search.

- [ ] **Step 3: Commit and publish**

Create branch `codex/missed-day-recovery`, stage only intended files, commit with message `Add missed-day recovery`, push, open PR, monitor checks/review, address actionable issues, merge when green, delete local and remote branch, and end clean on `main`.
