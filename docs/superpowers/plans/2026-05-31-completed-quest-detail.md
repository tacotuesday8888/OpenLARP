# Completed Quest Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a completed quest detail sheet from the Map so completed days show what happened and the attached proof receipt.

**Architecture:** Keep quest and proof data in the existing local `OpenLARPState` model. Add a small `CompletedQuestDetailContent` display helper for quest fields and `questID` to proof lookup, then add a SwiftUI detail sheet that reuses `ProofReceiptRow` and `ProofDetailView`.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XcodeBuildMCP, local JSON persistence.

---

### Task 1: Quest-To-Proof Display Helper

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`

- [x] **Step 1: Write failing tests**

Add tests for `CompletedQuestDetailContent` matching a proof receipt by `questID`, deriving quest display fields, and returning the required no-receipt fallback message when no proof is saved.

- [x] **Step 2: Run focused tests and verify red**

Run focused `V0EngineTests` with signing disabled. Expected: fails because `CompletedQuestDetailContent` is not defined.

- [x] **Step 3: Implement minimal helper**

Add `CompletedQuestDetailContent` near the proof display helpers in `OpenLARPModels.swift`.

- [x] **Step 4: Run focused tests and verify green**

Run the same focused test command. Expected: all `V0EngineTests` pass.

### Task 2: Completed Quest Detail UI

**Files:**
- Create: `OpenLARP/Views/CompletedQuestDetailView.swift`
- Modify: `OpenLARP/Views/QuestMapView.swift`
- Modify: `OpenLARP/AppRootView.swift`
- Modify: `OpenLARP.xcodeproj/project.pbxproj`

- [x] **Step 1: Add detail sheet view**

Create a sheet with quest summary, objective/action text, proof required, gap/category, XP reward, and proof metadata when available.

- [x] **Step 2: Wire completed map rows**

Make completed quest rows tappable in `QuestMapView` and present the detail sheet using `.sheet(item:)`. Keep non-completed row behavior unchanged.

- [x] **Step 3: Nest proof receipt detail**

Inside the completed quest detail sheet, make the compact proof receipt summary open the existing `ProofDetailView`.

- [x] **Step 4: Regenerate Xcode project**

Run `xcodegen generate` so the new Swift file is included in the target.

### Task 3: Verification And Publish

**Files:**
- Inspect: changed Swift files, tests, plan file, project file

- [x] **Step 1: Run tests**

Run simulator tests with signing disabled. Expected: all tests pass.

- [x] **Step 2: Run unsigned build**

Run the `AGENTS.md` signing-disabled build command. Expected: build succeeds.

- [x] **Step 3: Simulator check**

Launch the app, open Map, tap a completed quest, verify detail opens, tap attached proof receipt, verify `ProofDetailView` opens.

- [x] **Step 4: Inspect diff and secrets**

Run `git diff --check`, inspect staged diff, and scan for likely secrets before commit.

- [ ] **Step 5: Commit, push, PR, merge, cleanup**

Commit the focused branch, push it, open a PR, verify checks/review, merge when green, delete the merged branch, and return to clean `main`.
