# OpenLARP MVP Local Data Integrity Implementation Plan

**Goal:** Make every on-device career record and proof file owner-scoped, recoverable, protected, exportable, and completely erasable before the App Store MVP ships.

**Release contract:** The public app remains local-only. Authentication stays internal-only, but its storage behavior must be safe before it can be enabled later. Guest data never moves into an account automatically.

## Storage design

Production data moves from the legacy global `Documents` layout to app-private Application Support:

```text
Library/Application Support/OpenLARP/v1/
├── legacy-migration.json
└── Owners/
    ├── guest/
    │   ├── owner.json
    │   ├── openlarp-state.json
    │   ├── openlarp-state.previous.json
    │   ├── ProofAttachments/
    │   ├── ProofAttachmentDrafts/
    │   └── CachedPreviews/
    └── account-<SHA256 Firebase UID>/
        └── ...
```

- Raw account IDs and emails never appear in paths.
- `owner.json` binds the directory, state envelope, and backend owner identity.
- State and committed proof remain eligible for ordinary iOS device/iCloud backup.
- Drafts, cached previews, migration metadata, and temporary export artifacts are excluded from backup.
- Every sensitive file and managed directory receives complete iOS file protection.
- A previous valid state is retained for recovery from primary-file corruption.

## Task 1: File policy and owner primitives

**Files:**

- Create `OpenLARP/Models/OpenLARPFilePolicy.swift`.
- Create `OpenLARP/Models/OpenLARPLocalDataStore.swift`.
- Create `OpenLARPTests/LocalDataOwnershipTests.swift`.

**Tests first:**

- Guest and account storage keys are stable and distinct.
- Account paths contain a SHA-256 key, not a raw UID or email.
- Malicious or unusual account identifiers cannot escape the owner root.
- Existing symlinks in managed owner paths are rejected.
- Included and excluded backup policies are observable on created files.
- Sensitive files and directories use complete protection.

**Implementation:**

- Model guest/account owners and protected owner metadata.
- Create paired owner contexts that always supply persistence and attachment storage from the same directory.
- Add strict managed-root and owner-metadata validation.
- Centralize protected atomic writes, directory creation, copy policy, and backup flags.

## Task 2: Owner-bound persistence and recovery

**Files:**

- Modify `OpenLARP/Models/OpenLARPPersistence.swift`.
- Modify `OpenLARP/Models/OpenLARPModels.swift` only where schema validation is required.
- Extend `OpenLARPTests/LocalDataOwnershipTests.swift`.

**Tests first:**

- An owner-bound state envelope refuses an owner mismatch.
- Saving writes protected primary state and a protected last-known-good previous state.
- Corrupt primary state recovers from the previous valid state and restores the primary.
- Corrupt primary plus corrupt previous state is preserved for support rather than overwritten silently.
- Unsupported future envelope/state versions are rejected without rewriting the file.
- A recovered load does not immediately reconcile away files that a newer state may reference.

**Implementation:**

- Add an owner-bound persistence envelope.
- Validate encoded data before atomic replacement.
- Rotate only a decodable primary into `previous`.
- Return load metadata so the Store can distinguish normal, recovered, empty, and blocked states.

## Task 3: Attachment file policy and owner-safe upload reads

**Files:**

- Modify `OpenLARP/Models/OpenLARPAttachmentStore.swift`.
- Modify `OpenLARP/Models/OpenLARPAppStoreFactory.swift`.
- Extend `OpenLARPTests/ProofAttachmentStoreLifecycleTests.swift` and `LocalDataOwnershipTests.swift`.

**Tests first:**

- Draft files are protected and excluded from backup.
- Committed files are protected and backup eligible.
- Promotion explicitly normalizes a copied draft to committed policy.
- Rollback remains transactional.
- Upload reads route to the account encoded by the cloud intent, never whichever owner is active later.
- Cross-owner paths, metadata mismatches, and symlinks fail closed.

**Implementation:**

- Apply file policy after every write/copy because common operations can reset backup metadata.
- Add a validated import path used only by legacy migration.
- Make the local data store the stable proof-byte provider for internal cloud services.

## Task 4: One-time legacy migration

**Files:**

- Implement migration in `OpenLARPLocalDataStore.swift`.
- Extend `OpenLARPTests/LocalDataOwnershipTests.swift`.

**Tests first:**

- Valid legacy state, claimed proof, and active draft migrate once into guest.
- Legacy account ID/email, cloud consent, subscriber identity, account-control results, and authenticated backend outbox records do not enter guest.
- Goal, quest, outcome, progress, proof, and local audit history are preserved.
- A partially completed migration safely resumes without overwriting a valid guest container.
- Corrupt legacy state remains preserved and produces a clear warning.
- Only the known legacy state and proof paths are removed after a verified migration.

**Implementation:**

- Build migration in a protected staging owner directory.
- Decode and sanitize before commit.
- Copy only referenced attachments through the existing safe attachment reader.
- Atomically move staging into `Owners/guest`, write the completion marker, verify, then clean legacy paths.

## Task 5: Store owner switching and async ownership guards

**Files:**

- Modify `OpenLARP/Models/OpenLARPStore.swift`.
- Update `OpenLARPTests/AuthenticationReadinessTests.swift`.
- Extend `OpenLARPTests/LocalDataOwnershipTests.swift`.

**Tests first:**

- Guest -> Account A opens a separate empty or existing A container without adopting guest data.
- Sign-out restores the exact guest state and hides A data.
- Account A -> Account B never exposes A goals, proofs, outcomes, events, subscriptions, or support status.
- Returning to A restores A exactly.
- A failed destination load never presents the previous owner under the new identity.
- Delayed goal, proof, photo, sync, consent, cleanup, subscription, purchase, or Agent results cannot mutate a newly active owner.

**Implementation:**

- Let the Store switch one paired owner context rather than relabeling the current profile.
- Persist the current owner before authentication begins.
- Increment an owner revision on every transition and clear owner-bound transient UI state.
- Capture `{ owner key, owner revision }` across every asynchronous operation and discard stale results.
- Keep explicit guest-to-account import unimplemented and hidden for this MVP.

## Task 6: Complete export and erase

**Files:**

- Create `OpenLARP/Models/OpenLARPLocalDataExport.swift`.
- Modify `OpenLARPStore.swift` and `ProfileView.swift`.
- Extend `LocalDataOwnershipTests.swift` and release presentation tests.

**Tests first:**

- Export contains the active profile state plus referenced committed/draft proof bytes without absolute local paths or other owners.
- Missing, changed, or unsafe attachment data makes export fail honestly.
- Erase removes guest, every account owner, state/previous files, drafts, committed files, caches, owner metadata, migration leftovers, and known legacy paths.
- Erase never calls cloud-account deletion and never claims that existing device backups were removed.
- Partial erase does not report success; launch-time cleanup completes an interrupted erase tombstone.
- Erase starts a new guest identity and empty state.

**Implementation:**

- Export a user-initiated JSON archive with state and Base64 proof bytes through the system file exporter.
- Implement all-device erase by moving the managed root to an erase tombstone, starting a clean guest, and deleting the tombstone with retry.
- Attempt local authentication/subscription sign-out without conflating erase with cloud-account deletion.

## Task 7: Honest Profile controls and documentation

**Files:**

- Modify `OpenLARP/Views/ProfileView.swift`.
- Modify `OpenLARP/Models/OpenLARPReleasePresentationPolicy.swift`.
- Update `docs/APP_STORE_TESTFLIGHT_READINESS.md` and relevant setup docs.

**Tests first:**

- Public Profile always exposes Export My Data and Erase All On-Device Data.
- Public copy says no upload/sync, committed data may follow iOS backup settings, and drafts are excluded.
- Erase confirmation distinguishes local data, cloud data, and existing iOS backups.
- No public memory, share-wins, cloud-sync, account, or developer no-op controls appear.
- Internal long-term-memory/shareable-wins toggles remain hidden until behavior exists.

**Implementation:**

- Add a system file-export flow and destructive confirmation.
- Keep Change Goal, local erase, and cloud-account deletion visibly separate.
- Remove no-op memory/share controls from internal presentation.
- Keep hosted Privacy Policy and Support URLs documented as owner-supplied launch blockers until real HTTPS destinations exist.

## Verification

- Regenerate the Xcode project with XcodeGen.
- Run focused ownership, persistence, attachment, authentication, and release presentation tests during development.
- Run the complete internal XCTest suite with zero failures/skips.
- Run script tests, public safety, and the beta release gate.
- Run the optimized App Store release-contract test.
- Build and archive a fresh unsigned Release build.
- Inspect the archive for only expected Apple-linked code and the truthful privacy manifest.
- Launch the exact public Release app on Simulator and manually exercise export and erase.
- Perform a final diff review, commit the verified local-data package locally, and stop before any submission or additional feature work.
