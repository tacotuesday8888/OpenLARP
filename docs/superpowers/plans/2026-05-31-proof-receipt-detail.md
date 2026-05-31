# Proof Receipt Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users tap past proof receipts in Progress or Profile and inspect the full local proof detail.

**Architecture:** Reuse `ProofRecord` and `ProofAttachment` as the source of truth. Add a small testable display summary for proof detail formatting, then present a reusable SwiftUI `ProofDetailView` from Progress and Profile using `.sheet(item:)`.

**Tech Stack:** SwiftUI sheets, SwiftUI `openURL`, Foundation URL/date formatting, XCTest.

---

### Task 1: Detail Metadata Tests

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`

- [x] Add a failing unit test proving proof detail display trims text/link, exposes a valid link URL, shows quality label/reason/improvement, and formats earned XP.
- [x] Add a failing unit test proving missing quality data falls back to local, non-crashing display text.
- [x] Implement the minimal `ProofDetailContent` helper from `ProofRecord`.
- [x] Run the focused test target and confirm the new tests pass.

### Task 2: Reusable Detail UI

**Files:**
- Create: `OpenLARP/Views/ProofDetailView.swift`
- Modify: `OpenLARP/Views/ProgressTabView.swift`
- Modify: `OpenLARP/Views/ProfileView.swift`
- Regenerate: `OpenLARP.xcodeproj/project.pbxproj`

- [x] Add `ProofReceiptRow` so Progress and Profile use one tappable receipt summary.
- [x] Add `ProofDetailView` showing quest title, proof type, submitted date, quality label, XP, reason, improvement, text, link, and larger image previews.
- [x] Make link opening use native `openURL` when the trimmed link parses as a URL.
- [x] Make missing local image files render a placeholder instead of force-loading image data.
- [x] Present the detail view from Progress via `.sheet(item:)`.
- [x] Present the detail view from Profile via `.sheet(item:)`.

### Task 3: Verification And Publish

**Files:**
- Review all changed files.

- [x] Run `xcodegen generate` after adding the new Swift file.
- [x] Run simulator tests with signing disabled.
- [x] Run the unsigned generic iOS build.
- [x] Launch the app in Simulator and verify proof receipt rows can open the detail sheet where local state exists.
- [x] Inspect diff and run a secret scan.
- [ ] Commit, push, open PR, verify PR checks/review, merge if safe, and delete the merged branch.
