# Proof Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users submit text, link, and screenshot/photo proof locally, with attachment files stored on device and attachment metadata persisted in existing app state.

**Architecture:** Keep `OpenLARPState` as the JSON source of truth for proof metadata only. Store selected image bytes in an app-private `ProofAttachments/` directory via a small storage helper, and let `OpenLARPStore` bridge SwiftUI-selected image data into proof submissions.

**Tech Stack:** SwiftUI, PhotosUI `PhotosPicker`, Foundation file storage, XCTest.

---

### Task 1: Attachment Domain Tests

**Files:**
- Modify: `OpenLARPTests/V0EngineTests.swift`

- [x] Add a test proving image-only proof is accepted by the mock proof check and full XP can be claimed.
- [x] Add a test proving claimed proof records keep attachment metadata through JSON persistence.
- [x] Add a test proving the local attachment store writes image bytes to disk and deletes them.

### Task 2: Attachment Models And Storage

**Files:**
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Create: `OpenLARP/Models/OpenLARPAttachmentStore.swift`
- Modify: `OpenLARP/Models/OpenLARPEngine.swift`
- Modify: `OpenLARP/Models/OpenLARPStore.swift`

- [x] Add `ProofAttachment` metadata with file name, content type, byte count, created date, and local relative path.
- [x] Add attachment arrays to `ProofSubmission` and `ProofRecord` with decoding defaults for existing local JSON.
- [x] Add local image save/delete helpers under `ProofAttachments/`.
- [x] Make image attachments count as concrete proof in the mock quality check.
- [x] Keep self-report lower-credit even if text is present.

### Task 3: SwiftUI Proof UI

**Files:**
- Modify: `OpenLARP/Views/TodayView.swift`
- Modify: `OpenLARP/Views/ProgressTabView.swift`
- Modify: `OpenLARP/Views/ProfileView.swift`

- [x] Use `PhotosPicker` to select screenshot/photo proof.
- [x] Store selected images through `OpenLARPStore` before running the quality check.
- [x] Show selected image thumbnails before checking proof.
- [x] Show saved proof attachments in Recent Proof and Profile.

### Task 4: Verification And Publish

**Files:**
- Review all changed files.

- [x] Run `xcodegen generate` if project file inputs changed.
- [x] Run XCTest on simulator.
- [x] Run the unsigned iOS build check.
- [x] Launch the app and verify the proof submission surface renders.
- [x] Inspect diff and secret scan.
- [ ] Commit, push, open PR, verify PR state, merge if safe, and delete the merged branch.
