# MVP Proof Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make proof handling safe and truthful for the App Store MVP: unclaimed images remain owned by one persisted draft, every abandonment path removes private staged files, claimed receipts contain only committed files, and the local review never implies that it opened a link or inspected an image.

**Architecture:** `OpenLARPStore` becomes the only owner of proof-draft state. Image bytes enter a draft-specific `ProofAttachmentDrafts/<proof-id>/` directory after type, decode, size, and count validation. Claiming proof copies staged files into `ProofAttachments/`, saves the claimed state, then deletes staged originals; any failed claim rolls back committed copies. `QualityCheckResult` carries a migration-safe inspection scope so both current and historical UI can distinguish reviewed text/metadata from content the app did not inspect.

**Tech Stack:** Swift 6, SwiftUI, PhotosUI, Foundation, ImageIO/UIKit image processing, Observation, XCTest, XcodeGen.

**Implementation status (July 11, 2026):** Tasks 1–6 are implemented. Automated Task 7 checks are green: deterministic XcodeGen output, 339 internal XCTest cases, 121 script tests, the one-test optimized public Release contract, repository safety/beta gates, and a fresh unsigned public Release build/archive with bundle inspection. Signed-device interaction QA, final launch assets/URLs, and App Store upload remain external release work.

## Global Constraints

- A proof draft belongs to exactly one current quest and uses its `ProofSubmission.id` as the draft identifier.
- A draft may contain at most four images total across all picker actions.
- Each accepted image must be a decodable PNG, JPEG, HEIC, or HEIF and must be no larger than 8 MiB after processing.
- Draft paths are never eligible for cloud upload or permanent proof receipts.
- A file is committed only after the claim state can be persisted; a failed claim leaves the editable draft intact.
- Switching to self-report, removing an image, discarding, skipping, resetting, swapping, or invalidating the quest must clean the affected staged files.
- Leaving the screen keeps a referenced, auto-saved draft; explicit discard removes it. No view-local attachment list may own file lifetime.
- Link or attachment presence alone never increases local acceptance, score, XP, readiness, or badge eligibility.
- The local review may assess written specificity and format/metadata only. It must explicitly say that linked pages and image contents were not inspected.
- Existing persisted state and internal callable responses must decode conservatively when inspection scope is absent.
- Every behavior change begins with a failing focused test.

## File Structure

### New files

- `OpenLARP/Models/OpenLARPProofImageProcessor.swift` — image policy, validation, normalization, and typed errors.
- `OpenLARPTests/ProofLifecycleTests.swift` — focused draft, storage, promotion, review, and migration tests.

### Modified files

- `OpenLARP/Models/OpenLARPModels.swift` — inspection scope, draft quest ownership, conservative decoding, and attachment policy errors.
- `OpenLARP/Models/OpenLARPAttachmentStore.swift` — staged storage, safe promotion/rollback/finalization, migration, and reconciliation.
- `OpenLARP/Models/OpenLARPEngine.swift` — text-based local assessment and truthful review results.
- `OpenLARP/Models/OpenLARPStore.swift` — store-owned draft APIs and transactional claim lifecycle.
- `OpenLARP/Views/TodayView.swift` — store-backed composer, aggregate capacity, typed errors, and inspection disclosure.
- `OpenLARP/Views/ProofDetailView.swift` — historical inspection disclosure and neutral review language.
- `OpenLARPTests/V0EngineTests.swift` — update legacy proof-score and direct attachment expectations.
- `project.yml` and generated `OpenLARP.xcodeproj/project.pbxproj` — include new sources through deterministic regeneration.
- `docs/APP_STORE_TESTFLIGHT_READINESS.md` — record the verified proof limits and inspection boundary.

---

### Task 1: Define truthful review semantics

**Files:**
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Models/OpenLARPEngine.swift`
- Create: `OpenLARPTests/ProofLifecycleTests.swift`
- Modify: `OpenLARPTests/V0EngineTests.swift`

- [ ] Add failing tests proving URL-only and image-only submissions are not accepted as strong proof.
- [ ] Add a failing test proving the same detailed text receives the same score, XP, and readiness result with or without an uninspected URL/image.
- [ ] Add failing tests requiring written reflection for self-report and ensuring local results never award the strong-proof badge merely for metadata.
- [ ] Add a failing JSON compatibility test: a legacy `QualityCheckResult` without inspection scope decodes as “inspection not documented,” never as inspected.
- [ ] Add `ProofInspectionScope` with explicit booleans for written text, link format, linked destination, attachment metadata, and attachment contents.
- [ ] Give `QualityCheckResult` an explicit initializer and custom decoding default that is conservative for old state and old callable responses.
- [ ] Base deterministic acceptance and score on written specificity only. Use neutral labels such as “Well-documented submission” and “Needs more context.”
- [ ] Ensure every new local result records that text/format/metadata were reviewed and linked/image contents were not inspected.
- [ ] Run only the new review tests and confirm they pass before proceeding.

### Task 2: Validate and normalize selected images

**Files:**
- Create: `OpenLARP/Models/OpenLARPProofImageProcessor.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARPTests/ProofLifecycleTests.swift`

- [ ] Add failing tests for supported content, unsupported MIME type, corrupt bytes, an image over 8 MiB, and normalized output metadata.
- [ ] Define `ProofAttachmentPolicy.maximumCount = 4`, `maximumBytes = 8 * 1024 * 1024`, and the allowed MIME types.
- [ ] Add typed errors for full draft, unsupported type, corrupt image, oversized image, stale draft, and promotion/storage failure.
- [ ] Implement a stateless, `Sendable` processor that validates image bytes and metadata before any persistent write.
- [ ] Preserve valid supported images at or below 8 MiB; recompress/downscale oversized decodable images to JPEG and reject them if no safe result fits the limit.
- [ ] Ensure conversion updates MIME type, extension, and byte count together.
- [ ] Run the processor tests and verify no rejected input creates a file.

### Task 3: Add staged attachment storage and transactional promotion

**Files:**
- Modify: `OpenLARP/Models/OpenLARPAttachmentStore.swift`
- Modify: `OpenLARPTests/ProofLifecycleTests.swift`

- [ ] Add failing tests proving staged paths use `ProofAttachmentDrafts/<draft-id>/` and cloud upload refuses those paths.
- [ ] Add failing tests for successful copy/finalize promotion and rollback after a simulated persistence failure.
- [ ] Constrain every read/delete/migration operation to either the draft root or committed attachment root after URL standardization.
- [ ] Implement stage, remove, draft cleanup, prepare-promotion, rollback, and finalize operations.
- [ ] Keep promotion two-phase: copy to committed storage, save state, then remove staged originals.
- [ ] Add reconciliation that preserves every path referenced by claimed receipts or the active draft and removes other files from these dedicated roots.
- [ ] Run attachment-store and cloud-boundary tests.

### Task 4: Make the Store own the complete draft lifecycle

**Files:**
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Models/OpenLARPStore.swift`
- Modify: `OpenLARPTests/ProofLifecycleTests.swift`
- Modify: `OpenLARPTests/V0EngineTests.swift`

- [ ] Add failing tests for four images across repeated staging calls and a fifth rejection with no file or metadata mutation.
- [ ] Add failing tests for remove, proof-to-self-report, explicit discard, skip, reset, swap, and changed-quest cleanup.
- [ ] Add failing tests proving “Improve Proof” preserves the draft and successful claim stores committed paths while removing staged paths.
- [ ] Add a delayed-operation test proving a picker/review completion cannot recreate an abandoned or mismatched draft.
- [ ] Add `proofDraftQuestID` to `OpenLARPState` with backward-compatible decoding.
- [ ] Add focused Store APIs to update draft fields, stage/remove an image, change kind, check the active draft, discard, and claim.
- [ ] Revalidate the draft ID, quest ID, proof kind, and remaining capacity after every asynchronous boundary.
- [ ] Make claim transactional: prepare promotion, claim using committed metadata, save, finalize; on any failure restore draft/state and roll back copies.
- [ ] Remove or internalize the orphan-prone raw `saveProofImage`/`deleteProofImage` UI path.
- [ ] Ensure all quest lifecycle methods centralize draft cleanup rather than duplicating partial state changes.
- [ ] Run focused Store lifecycle tests.

### Task 5: Migrate and reconcile legacy drafts safely

**Files:**
- Modify: `OpenLARP/Models/OpenLARPAttachmentStore.swift`
- Modify: `OpenLARP/Models/OpenLARPStore.swift`
- Modify: `OpenLARPTests/ProofLifecycleTests.swift`

- [ ] Add a failing test for an old persisted draft whose files are in `ProofAttachments/`.
- [ ] Add a failing test proving migration preserves files referenced by claimed `recentProof` receipts.
- [ ] Add a failing test proving a stale draft for another/no current quest is removed with its private files.
- [ ] On startup, move or copy legacy pending files into the active draft directory, persist new paths, and leave claimed files untouched.
- [ ] Treat missing or malformed draft files conservatively: remove unusable metadata, surface a recoverable message, and never damage claimed receipts.
- [ ] Reconcile unreferenced files only after the migrated state is successfully saved.
- [ ] Reload the Store in tests and verify the resulting state and disk tree.

### Task 6: Refactor the proof UI around the Store

**Files:**
- Modify: `OpenLARP/Views/TodayView.swift`
- Modify: `OpenLARP/Views/ProofDetailView.swift`
- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARPTests/ProofLifecycleTests.swift`

- [ ] Remove view-local proof attachment ownership and bind kind/text/link/attachments to the active Store draft.
- [ ] Limit each picker action to remaining capacity and hide/disable selection at four images.
- [ ] Pass the draft ID through each post-`await` staging call so stale completions fail closed.
- [ ] Preserve typed validation messages and show the four-image/8 MiB-per-image policy.
- [ ] State that drafts auto-save locally and provide an explicit “Discard Draft” action that removes staged files.
- [ ] Switching to self-report must call the Store cleanup API before the UI clears attachment metadata.
- [ ] Change “Quality check” to “Submission review,” identify the numeric value as context detail, and show separate “Reviewed” and “Not inspected” rows.
- [ ] Update proof receipt detail with the same neutral language; legacy receipts say their inspection scope was not recorded.
- [ ] Add pure content/presentation tests for disclosure wording where practical.

### Task 7: Regression verification and handoff

**Files:**
- Modify: `docs/APP_STORE_TESTFLIGHT_READINESS.md`
- Regenerate: `OpenLARP.xcodeproj/project.pbxproj`

- [ ] Run `xcodegen generate` and verify a second generation is clean.
- [ ] Run `git diff --check`, repository safety, script tests, and the beta release gate.
- [ ] Run the focused `ProofLifecycleTests` suite.
- [ ] Run the complete internal Debug XCTest suite and inspect the `.xcresult` summary.
- [ ] Run the optimized public Release contract.
- [ ] Build and archive the unsigned public target; inspect the final bundle for service/config/privacy regressions.
- [ ] Exercise proof text, link, repeated image selection, removal, discard, self-report switch, relaunch, improve, and claim on Simulator.
- [ ] Inspect the diff, run a secret-pattern audit, request independent code review, and resolve all Critical/Important findings.
- [ ] Commit the scoped work, push the stacked branch, open a draft PR against the release-profile branch, and monitor CI.
