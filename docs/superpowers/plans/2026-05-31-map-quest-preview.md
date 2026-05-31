# Map Quest Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a simple Map preview sheet for available and in-progress quests while keeping completed quest receipt behavior intact.

**Architecture:** Keep the action loop owned by Today. Add a small `QuestPreviewContent` display helper for testable quest metadata and CTA rules, then present either completed detail or non-completed preview from one item-driven Map sheet enum. Locked quests remain static and cannot start or submit proof from Map.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XcodeBuildMCP, local JSON persistence.

---

### Task 1: Quest Preview Display Helper

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`

- [x] **Step 1: Write failing tests**

Add tests for `QuestPreviewContent` deriving day, status, title, objective, action steps, proof required, gap, XP, time estimate, difficulty, and CTA behavior for available, in-progress, and locked quests.

- [x] **Step 2: Run focused tests and verify red**

Run focused `V0EngineTests` with signing disabled. Expected: fails because `QuestPreviewContent` does not exist yet.

- [x] **Step 3: Implement minimal helper**

Add `QuestPreviewContent` near the existing proof and quest display helpers in `OpenLARPModels.swift`.

- [x] **Step 4: Run focused tests and verify green**

Run the same focused test command. Expected: the new preview content tests pass.

### Task 2: Map Preview Sheet UI

**Files:**
- Create: `OpenLARP/Views/QuestPreviewView.swift`
- Modify: `OpenLARP/Views/QuestMapView.swift`
- Modify: `OpenLARP.xcodeproj/project.pbxproj`

- [x] **Step 1: Add preview sheet view**

Create `QuestPreviewView` with quest day/status/title, objective, action steps, proof required, gap, XP, time estimate, difficulty, and one CTA that dismisses the sheet and opens Today.

- [x] **Step 2: Wire one Map sheet router**

Replace completed-only Map sheet state with a small `MapQuestSheet` enum so completed quests still open `CompletedQuestDetailView` and available/in-progress quests open `QuestPreviewView`.

- [x] **Step 3: Keep locked rows static**

Leave locked future quests read-only in the Map. They must not present a start CTA or proof flow.

- [x] **Step 4: Regenerate Xcode project**

Run `xcodegen generate` so `QuestPreviewView.swift` is included in the target.

### Task 3: Verification And Publish

**Files:**
- Inspect: changed Swift files, tests, plan file, project file

- [x] **Step 1: Run tests**

Run focused tests, then the full simulator test suite with signing disabled. Expected: all tests pass.

- [x] **Step 2: Run unsigned build**

Run the `AGENTS.md` signing-disabled build command. Expected: build succeeds.

- [x] **Step 3: Simulator check**

Launch the app, open Map, tap an available or in-progress quest preview, use the CTA to return to Today, and confirm completed quest detail still opens from a completed row.

- [x] **Step 4: Inspect diff and secrets**

Run `git diff --check`, inspect the staged diff, and scan for likely secrets before commit.

- [ ] **Step 5: Commit, push, PR, merge, cleanup**

Commit the focused branch, push it, open a PR, verify checks/review, merge when green, delete the merged branch, and return to clean `main`.
