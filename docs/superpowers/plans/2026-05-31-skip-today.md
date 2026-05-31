# Skip Today V0 Slice

## Goal

Add an intentional local-only "Skip Today" flow that is separate from accidental missed-day recovery.

## Implementation Plan

- [x] Inspect current daily cadence, missed-day recovery, Today, Map, Store, and test coverage.
- [x] Add failing tests for:
  - available quest skip
  - in-progress quest skip clearing pending proof/result
  - same-day lockout
  - next local day unlock/clear
  - preserving prior XP, proof, badges, completed quests, and readiness
  - final quest skip with no next quest
- [x] Add persisted skipped-today state and skipped-today UI content model.
- [x] Add engine skip transition and refresh behavior.
- [x] Add store action that clears pending proof/result after a successful skip.
- [x] Wire Today secondary action, confirmation dialog, and skipped-today card.
- [x] Verify focused tests, full tests, signing-disabled build, and a quick simulator sanity check.
- [ ] Commit, push, open PR, monitor review/CI, merge, and clean up.
