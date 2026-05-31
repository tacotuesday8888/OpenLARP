# V0 Local Core Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first local-first OpenLARP V0 loop: goal setup, cooked diagnostic, today quest, proof or self-report, mock quality check, XP/streak/progress, connected tabs, and local persistence.

**Architecture:** Keep one root SwiftUI-owned `OpenLARPStore` as the source of truth. Put deterministic domain rules in small model/engine files so the UI stays thin and tests can cover the core behavior without launching the app.

**Tech Stack:** SwiftUI, Observation, XCTest, JSON file persistence in the app documents directory, XcodeGen-managed project settings.

---

### Task 1: Project Test Harness

**Files:**
- Modify: `project.yml`
- Create: `OpenLARPTests/V0EngineTests.swift`

- [ ] Add an XCTest target named `OpenLARPTests` that hosts the app target.
- [ ] Write failing tests for first-run state creation, diagnostic generation, quest start/proof submission, XP/streak/readiness awards, weak self-report handling, and JSON persistence round-trip.
- [ ] Run tests and confirm they fail because the V0 state and engine do not exist yet.

### Task 2: Local Domain And Engine

**Files:**
- Replace: `OpenLARP/Models/OpenLARPModels.swift`
- Create: `OpenLARP/Models/OpenLARPStore.swift`
- Create: `OpenLARP/Models/OpenLARPEngine.swift`
- Create: `OpenLARP/Models/OpenLARPPersistence.swift`
- Remove from production usage: `OpenLARP/Models/SampleData.swift`

- [ ] Define codable models for `CareerGoal`, `CookedDiagnostic`, `Quest`, `QuestPlanDay`, `ProofSubmission`, `QualityCheckResult`, `ReadinessMetrics`, `ProgressState`, `Badge`, and `OpenLARPState`.
- [ ] Implement deterministic local rules that never invent credentials or fake claims.
- [ ] Implement JSON load/save with a default state for brand-new users.
- [ ] Make store methods cover goal confirmation, quest start, proof draft, quality check, XP claim, quest swapping, and goal reset.
- [ ] Run tests and keep changes minimal until green.

### Task 3: SwiftUI Workflow Wiring

**Files:**
- Modify: `OpenLARP/OpenLARPApp.swift`
- Modify: `OpenLARP/AppRootView.swift`
- Replace: `OpenLARP/Views/TodayView.swift`
- Modify: `OpenLARP/Views/QuestMapView.swift`
- Create: `OpenLARP/Views/ProgressView.swift`
- Modify: `OpenLARP/Views/ProfileView.swift`
- Modify: `OpenLARP/Views/AgentChatView.swift`
- Modify as needed: `OpenLARP/Style/OpenLARPStyle.swift`

- [ ] Own `OpenLARPStore` at app root and inject it into the tab shell.
- [ ] Show goal setup first when no goal has been confirmed.
- [ ] Show diagnostic immediately after goal setup with a primary action to start the first quest.
- [ ] Keep Today quest-first: start quest, submit proof/self-report, run mock check, claim XP, preview next quest.
- [ ] Connect Map, Progress, Profile, and Agent Helper to the same store state.
- [ ] Keep Chat as helper support, not a primary product surface.

### Task 4: Validation And Commit

**Files:**
- Review all changed files.

- [ ] Regenerate the Xcode project from `project.yml`.
- [ ] Run the XCTest suite on simulator.
- [ ] Run the unsigned iOS build check with signing disabled.
- [ ] Inspect `git diff` and `git status`.
- [ ] Check that no secrets, local config, build output, or user state are staged.
- [ ] Commit the V0 local core loop.
