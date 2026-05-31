# Proof Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Proof Archive so users can browse every saved proof receipt and open the existing proof detail view.

**Architecture:** Keep proof history in the existing local `ProgressState.recentProof` array, but stop trimming it to the recent UI limit. Add a small `ProofArchiveContent` helper for newest-first ordering and archive copy, then add a SwiftUI sheet that reuses `ProofReceiptRow` and `ProofDetailView`.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XcodeBuildMCP, local JSON persistence.

---

### Task 1: Archive Behavior Tests

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Models/OpenLARPEngine.swift`

- [x] **Step 1: Write failing tests**

Add tests for `ProofArchiveContent` ordering/copy and for retaining more than the recent UI limit.

- [x] **Step 2: Run focused tests and verify red**

Run:

```bash
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARP -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /private/tmp/OpenLARPDerivedData CODE_SIGNING_ALLOWED=NO -only-testing:OpenLARPTests/V0EngineTests
```

Expected: fails because `ProofArchiveContent` does not exist and claim still caps proof history.

- [x] **Step 3: Implement minimal model behavior**

Add `ProofArchiveContent` near `ProofDetailContent` and remove the `prefix(12)` cap after inserting a claimed proof record.

- [x] **Step 4: Run focused tests and verify green**

Run the same focused test command. Expected: `V0EngineTests` pass.

### Task 2: Archive UI

**Files:**
- Create: `OpenLARP/Views/ProofArchiveView.swift`
- Modify: `OpenLARP/Views/ProofDetailView.swift`
- Modify: `OpenLARP/Views/ProgressTabView.swift`
- Modify: `OpenLARP/Views/ProfileView.swift`
- Modify: `OpenLARP.xcodeproj/project.pbxproj`

- [x] **Step 1: Add archive sheet**

Create `ProofArchiveView` with empty state, newest-first receipt list, and nested `ProofDetailView` presentation.

- [x] **Step 2: Add obvious entry points**

Add an “All proof receipts” button in Progress and a “Proof archive” button in Profile when receipts exist. Keep existing recent proof rows intact.

- [x] **Step 3: Show archive metadata in rows**

Extend `ProofReceiptRow` with an optional metadata line so archive rows show submitted date and proof type while preserving recent-row defaults.

- [x] **Step 4: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `ProofArchiveView.swift` is included in the app target.

### Task 3: Verification And Publish

**Files:**
- Inspect: changed Swift files, plan file, project file

- [x] **Step 1: Run tests**

Run simulator tests with signing disabled. Expected: all tests pass.

- [x] **Step 2: Run unsigned build**

Run the `AGENTS.md` build command. Expected: build succeeds.

- [x] **Step 3: Simulator check**

Launch the app, open Proof Archive, tap a receipt, and verify `ProofDetailView` opens.

- [x] **Step 4: Inspect diff and secrets**

Run `git diff --check`, inspect staged diff, and scan for likely secrets before commit.

- [ ] **Step 5: Commit, push, PR, merge, cleanup**

Commit a focused change, push the branch, open a PR, verify checks/review, merge when green, delete the merged branch, and return to clean `main`.
