# Rich V0 Career Understanding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the long setup form with a guided, account-aware onboarding flow whose durable career understanding distinguishes confirmed user facts, unconfirmed AI hypotheses, and unknown information.

**Architecture:** Add a focused career-understanding domain model beside the legacy `CareerGoal`, then migrate old saved goals into provenanced confirmed facts. The UI builds an in-memory draft across short steps and only writes the goal, understanding, diagnostic, and plan after the user reviews and approves the summary. Existing deterministic diagnostic and plan generation remain the fallback; live adaptive onboarding questions are a separate follow-on backend PR that will produce `.aiHypothesis` records through the interfaces defined here.

**Tech Stack:** Swift 6, SwiftUI, Observation, Codable JSON persistence, XCTest, Firebase-ready account services already present in the internal-beta target.

**Implementation status (2026-08-10):** Domain, fail-closed schema-11 migration, exact reviewed-object approval, four-step UI with hypothesis confirm/edit/reject controls, owner-scoped service-beta account entry, persisted atomic privacy-safe funnel state, knownness-aware cloud mapping, and aligned Rich V0 backend goal fields are implemented. All Swift sources parse; the iOS-target Swift 6 app source graph typechecks when the separately packaged RevenueCat adapter is omitted; the dependency-free domain harness and backend/script suites pass. Full XCTest, signed-in UI exercise, and Xcode target builds remain assigned to CI because this machine reports the iOS 26.2 platform component unavailable.

## Global Constraints

- Native iOS first; keep the SwiftUI architecture simple and maintainable.
- Every durable fact stores provenance, confirmation state, and `lastUpdatedAt`.
- AI hypotheses always begin as `awaitingConfirmation`; no code path may promote them implicitly.
- Unknown information is explicit and is never replaced with invented values.
- The user must be able to review, edit, approve, or reject AI understanding before it becomes confirmed state.
- The service-enabled beta offers Apple and Google entry while keeping a clearly explained local-device path.
- The public App Store target stays local-only and links no service SDKs.
- Do not implement live Gemini calls, mission generation, a 14-day plan, paywall, or release distribution in this PR.
- Never persist private career text in beta analytics events or authentication result copy.

---

## File Map

- Create `OpenLARP/Models/OpenLARPCareerUnderstanding.swift`: fact, provenance, unknown, intake-draft, and review models plus deterministic migration/building helpers.
- Modify `OpenLARP/Models/OpenLARPModels.swift`: extend `CareerGoal` compatibly and add `careerUnderstanding` to state schema 11.
- Modify `OpenLARP/Models/OpenLARPEngine.swift`: accept only reviewed understanding when creating an active goal; preserve compatibility for existing callers.
- Modify `OpenLARP/Models/OpenLARPStore.swift`: expose an approval entry point and keep owner-switch guards around the asynchronous diagnostic/plan work.
- Create `OpenLARP/Views/GuidedCareerOnboardingView.swift`: short step flow, review surface, and explicit final approval.
- Create `OpenLARP/Views/OnboardingAccountEntryView.swift`: reusable Apple/Google/local entry card for service beta without changing public release wiring.
- Modify `OpenLARP/Views/TodayView.swift`: replace the embedded long form with the guided flow.
- Modify `OpenLARP/Models/OpenLARPBetaMeasurement.swift`: add text-free onboarding/review funnel events.
- Create `OpenLARPTests/CareerUnderstandingTests.swift`: focused model, migration, engine, store, and analytics tests.
- Update `OpenLARPTests/V0EngineTests.swift`: compatibility expectations for approved understanding and schema migration.
- Update `docs/DEVELOPMENT_ROADMAP.md` and `docs/IOS_PRODUCT_ARCHITECTURE.md`: document the implemented boundary and the still-pending live AI question job.

### Task 1: Provenanced Career Understanding Domain

**Files:**

- Create: `OpenLARP/Models/OpenLARPCareerUnderstanding.swift`
- Test: `OpenLARPTests/CareerUnderstandingTests.swift`

**Interfaces:**

- Produces: `CareerOutcomeType`, `CareerUrgency`, `CareerFactKind`, `CareerFactSource`, `CareerFactConfirmationState`, `CareerFactProvenance`, `CareerFactRecord`, `CareerUnknown`, `CareerUnderstandingReviewState`, `CareerUnderstanding`, and `CareerIntakeDraft`.
- Produces: `CareerIntakeDraft.makeGoal()` and `CareerIntakeDraft.makeUnderstanding(reviewedAt:)`.
- Consumes later: the engine/store accept a `CareerUnderstanding` whose `reviewState == .approved`.

- [x] **Step 1: Write failing fact-state tests**

```swift
func testAIHypothesisCannotBecomeConfirmedWithoutExplicitApproval() throws {
    let hypothesis = try CareerFactRecord.aiHypothesis(
        kind: .experience,
        value: "Worked as an engineer",
        workflowRequestID: "request-1",
        createdAt: referenceDate
    )
    XCTAssertEqual(hypothesis.confirmationState, .awaitingConfirmation)
    XCTAssertThrowsError(try hypothesis.confirmed(at: referenceDate))
    XCTAssertEqual(hypothesis.provenance.source, .aiHypothesis)
}

func testEditingHypothesisCreatesConfirmedUserEditProvenance() throws {
    let edited = try hypothesis.editedAndConfirmed(
        value: "Completed one engineering course",
        at: referenceDate
    )
    XCTAssertEqual(edited.confirmationState, .confirmed)
    XCTAssertEqual(edited.provenance.source, .userEdit)
}

func testRejectedHypothesisIsExcludedFromConfirmedFacts() throws {
    var understanding = CareerUnderstanding.reviewing(facts: [hypothesis], unknowns: [])
    try understanding.rejectFact(id: hypothesis.id, at: referenceDate)
    XCTAssertTrue(understanding.confirmedFacts.isEmpty)
    XCTAssertEqual(understanding.rejectedFacts.map(\.id), [hypothesis.id])
}
```

- [ ] **Step 2: Run the focused tests and verify missing types fail compilation**

Run:

```bash
xcodebuild test -project OpenLARP.xcodeproj -scheme OpenLARPInternal -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/OpenLARPCareerUnderstandingDerivedData CODE_SIGNING_ALLOWED=NO -only-testing:OpenLARPTests/CareerUnderstandingTests
```

Expected: FAIL because the career-understanding types do not exist.

- [x] **Step 3: Implement the minimal domain types**

Use stable raw values and keep fact values as trimmed user-visible strings so every record can be reviewed uniformly. `CareerFactRecord.confirmed(at:)` must reject `.aiHypothesis` unless an explicit `userConfirmed(at:)` method is used. `CareerUnderstanding.approve(at:)` must fail while any AI fact remains `awaitingConfirmation`.

```swift
enum CareerFactSource: String, Codable, Sendable {
    case userEntry
    case userEdit
    case aiHypothesis
    case legacyMigration
}

enum CareerFactConfirmationState: String, Codable, Sendable {
    case awaitingConfirmation
    case confirmed
    case rejected
}

struct CareerFactProvenance: Codable, Equatable, Sendable {
    var source: CareerFactSource
    var sourceIdentifier: String?
    var recordedAt: Date
}

struct CareerFactRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: CareerFactKind
    var value: String
    var provenance: CareerFactProvenance
    var confirmationState: CareerFactConfirmationState
    var lastUpdatedAt: Date
}
```

- [x] **Step 4: Add draft-to-understanding tests**

Cover all required intake fields: outcome type and target, current stage, timeline, urgency, background/experience, existing proof, constraints, confidence, daily time, and biggest blocker. Assert blank optional answers create `CareerUnknown` entries rather than empty facts.

- [x] **Step 5: Implement `CareerIntakeDraft` mapping and sanitization**

Clamp confidence to `1...5` and daily minutes to supported values `10`, `20`, `30`, or `45`; trim whitespace; limit persisted fact values to 4,000 characters; and keep full private text out of analytics.

- [ ] **Step 6: Run focused tests and verify they pass**

Expected: all `CareerUnderstandingTests` model tests PASS.

### Task 2: Schema 11 Migration and Goal Compatibility

**Files:**

- Modify: `OpenLARP/Models/OpenLARPModels.swift`
- Modify: `OpenLARP/Models/OpenLARPCareerUnderstanding.swift`
- Test: `OpenLARPTests/CareerUnderstandingTests.swift`
- Test: `OpenLARPTests/V0EngineTests.swift`

**Interfaces:**

- `CareerGoal` gains `outcomeType`, `urgency`, `constraints`, and `dailyCommitmentMinutes` with decoding defaults.
- `OpenLARPState` gains `careerUnderstanding: CareerUnderstanding` and advances to schema version 11.
- `CareerUnderstanding.migratingLegacyGoal(_:updatedAt:)` creates confirmed `.legacyMigration` facts.

- [x] **Step 1: Write failing legacy-decode tests**

Create schema-10 JSON with the old seven-field goal. Decode it and assert:

```swift
XCTAssertEqual(state.goal?.outcomeType, .job)
XCTAssertEqual(state.goal?.urgency, .steady)
XCTAssertEqual(state.goal?.dailyCommitmentMinutes, 25)
XCTAssertEqual(state.careerUnderstanding.reviewState, .approved)
XCTAssertTrue(state.careerUnderstanding.facts.allSatisfy {
    $0.provenance.source == .legacyMigration && $0.confirmationState == .confirmed
})
```

- [ ] **Step 2: Run the migration tests and verify failure**

Expected: FAIL because schema 11 fields do not exist.

- [x] **Step 3: Add explicit backward-compatible `CareerGoal` Codable implementation**

Preserve every existing initializer call with defaults:

```swift
init(
    currentStatus: CurrentStatus,
    targetRole: String,
    timeline: String,
    background: String,
    existingProof: String,
    confidence: Int,
    biggestBlocker: String,
    outcomeType: CareerOutcomeType = .job,
    urgency: CareerUrgency = .steady,
    constraints: String = "",
    dailyCommitmentMinutes: Int = 25
)
```

- [x] **Step 4: Add state decoding and migration**

Decode `careerUnderstanding` when present. For schema 10 or earlier with a goal and no understanding, call `migratingLegacyGoal`; for an empty state, use `.empty`. Never invent optional background/proof/constraint facts during migration.

- [ ] **Step 5: Run migration plus existing persistence tests**

Run focused `CareerUnderstandingTests`, `LocalDataOwnershipTests`, `LocalDataExportTests`, and schema-related `V0EngineTests`. Expected: PASS with old fixtures preserved.

### Task 3: Review Approval in Engine and Store

**Files:**

- Modify: `OpenLARP/Models/OpenLARPEngine.swift`
- Modify: `OpenLARP/Models/OpenLARPStore.swift`
- Test: `OpenLARPTests/CareerUnderstandingTests.swift`
- Test: `OpenLARPTests/V0EngineTests.swift`

**Interfaces:**

- Produces: `OpenLARPEngine.confirmGoal(_:understanding:diagnostic:plan:now:)`.
- Produces: `OpenLARPStore.approveCareerUnderstanding(_:goal:expectedOwnerScope:) async -> Bool`, which approves and persists the exact reviewed records only for the still-active protected workspace.
- Preserves: `confirmGoal(_:) async` as a compatibility wrapper for existing tests/internal callers, implemented through a user-confirmed draft rather than a separate unsafe path.

- [x] **Step 1: Write failing approval-gate tests**

Assert the engine rejects `.collecting` and `.reviewing` understanding, rejects unresolved hypotheses, accepts a fully reviewed understanding, and stores the exact approved records without regenerating provenance.

- [ ] **Step 2: Verify the tests fail**

Expected: FAIL because engine/store do not accept understanding.

- [x] **Step 3: Implement the engine gate**

Add `OpenLARPError.careerUnderstandingNeedsReview` and validate:

```swift
guard understanding.reviewState == .approved,
      understanding.pendingHypotheses.isEmpty else {
    throw OpenLARPError.careerUnderstandingNeedsReview
}
```

- [x] **Step 4: Implement the store approval entry point**

Build the goal and reviewed understanding at one timestamp, then reuse the current async diagnostic/plan workflow with the existing owner revision guard. Commit state only after the returned diagnostic and plan are validated. On service failure, commit the same reviewed understanding with the deterministic local evaluation/plan and honest fallback message.

- [ ] **Step 5: Test async owner switching and fallback**

Add tests that a delayed approval cannot mutate a newly active owner and that fallback preserves the approved facts exactly.

- [ ] **Step 6: Run focused engine/store tests**

Expected: PASS.

### Task 4: Guided Four-Step Onboarding and Review

**Files:**

- Create: `OpenLARP/Views/GuidedCareerOnboardingView.swift`
- Modify: `OpenLARP/Views/TodayView.swift`
- Test: `OpenLARPTests/CareerUnderstandingTests.swift`

**Interfaces:**

- `GuidedCareerOnboardingView(store:onGoalConfirmed:)` replaces the private `GoalSetupView`.
- `CareerOnboardingStep` is `outcome`, `currentReality`, `commitment`, `review`.
- The final CTA is `Approve Understanding & Check My Readiness`; intermediate CTAs name their destination.

- [ ] **Step 1: Add presentation-model tests**

Test step titles, progress (`1 of 4` through `4 of 4`), validation, specific CTA labels, VoiceOver summaries, and review grouping into `You told us`, `Needs your confirmation`, and `Still unknown`.

- [x] **Step 2: Implement the guided container**

Use a vertical `ScrollView`, one primary bottom action, quiet Back/Edit actions, keyboard-friendly text fields, semantic selection controls, and `@FocusState`. Do not show all questions at once.

- [x] **Step 3: Implement each step**

- Outcome: job/internship/promotion/other outcome, target role/outcome, current stage.
- Current reality: timeline, urgency, confidence, current experience, existing proof.
- Commitment: constraints, daily minutes, biggest blocker.
- Review: fact source/confirmation labels, explicit unknowns, and edit links back to the relevant step.

- [x] **Step 4: Wire explicit approval**

Only the review CTA calls `store.approveCareerUnderstanding`. Disable duplicate submission and expose an accessible progress state while evaluation is running.

- [x] **Step 5: Remove the embedded long form**

Delete `GoalSetupView` from `TodayView.swift` and replace its call site with `GuidedCareerOnboardingView`.

- [ ] **Step 6: Run focused tests and an unsigned build**

Expected: tests PASS and both targets compile.

### Task 5: Service-Beta Account Entry with Local Fallback

**Files:**

- Create: `OpenLARP/Views/OnboardingAccountEntryView.swift`
- Modify: `OpenLARP/Views/GuidedCareerOnboardingView.swift`
- Test: `OpenLARPTests/CareerUnderstandingTests.swift`
- Test: `OpenLARPTests/ReleaseServiceBoundaryTests.swift`

**Interfaces:**

- `OnboardingAccountEntryView(store:continueLocally:)` is shown before career questions only when account capability exists.
- Public local-only builds render direct onboarding and never reference Firebase/Google types.

- [ ] **Step 1: Write release-policy tests**

Assert internal beta exposes `Continue with Apple`, `Continue with Google`, and `Use This iPhone Only`; App Store local-only exposes none of the service controls and begins career questions directly.

- [x] **Step 2: Implement account entry UI**

Reuse `AuthenticationPresentationAnchorReader` and store sign-in methods. Explain that sign-in enables supported cloud restoration, while local mode stores progress only on this device and can be linked later. Cancellation/failure must leave the local CTA available.

- [x] **Step 3: Verify authentication operation states**

Disable conflicting actions during sign-in/account-data work, show provider-specific progress, and surface existing honest authentication messages without claiming cloud sync completed.

- [ ] **Step 4: Run authentication and release-boundary tests**

Expected: PASS and the App Store target remains service-SDK-free.

### Task 6: Privacy-Safe Funnel Measurement

**Files:**

- Modify: `OpenLARP/Models/OpenLARPBetaMeasurement.swift`
- Modify: `OpenLARP/Models/OpenLARPStore.swift`
- Test: `OpenLARPTests/CareerUnderstandingTests.swift`
- Test: `OpenLARPTests/BetaMeasurementTests.swift`

**Interfaces:**

- Add event kinds `onboardingStarted`, `careerUnderstandingReviewed`, and `careerUnderstandingApproved`.
- Event summaries contain counts and categorical state only—never fact values, target text, proof text, prompts, or constraints.

- [x] **Step 1: Write redaction tests**

Encode/export the measurement summary after onboarding and assert none of the draft's unique private strings appear.

- [x] **Step 2: Record idempotent funnel events**

Record start once per fresh goal flow, review when the review screen is first reached, and approval after state persistence succeeds.

- [ ] **Step 3: Run beta measurement tests**

Expected: PASS with safe aggregate export.

### Task 7: Documentation, Full Verification, and PR Delivery

**Files:**

- Modify: `docs/DEVELOPMENT_ROADMAP.md`
- Modify: `docs/IOS_PRODUCT_ARCHITECTURE.md`
- Modify: this plan to mark completed checkboxes as work lands.

- [x] **Step 1: Update docs truthfully**

Document guided onboarding, provenance, review semantics, migration, account entry, and the fact that live adaptive AI questions remain pending the next backend PR.

- [x] **Step 2: Run formatting and secret checks**

Run `git diff --check`, `npm run public:safety`, and inspect all staged files for local configuration or private data.

- [ ] **Step 3: Run the complete automated gate**

Run backend typecheck/test/build, script tests, Firebase rules emulators, full `OpenLARPInternal` XCTest, `OpenLARPReleaseContract` XCTest, and unsigned builds for `OpenLARPInternal` plus `OpenLARP`.

- [ ] **Step 4: Manually exercise both entry modes**

On simulator, verify fresh local onboarding, service-beta account/local choice, review/edit/approval, deterministic fallback, relaunch persistence, Dynamic Type, VoiceOver labels, and no dead-end after auth cancellation.

- [ ] **Step 5: Review, commit, push, and open a focused PR**

Stage only intended files, commit with `feat: add reviewed career understanding`, push `codex/rich-v0-career-understanding`, open a PR to `main`, wait for fresh green CI, address actionable review feedback, and merge when verified.

## Self-Review

- Spec coverage: this plan covers the local data model, migration, explicit fact confirmation, unknowns, guided onboarding, service-beta account entry, local fallback, privacy-safe instrumentation, and accessibility states. Live AI follow-up generation is intentionally assigned to the next AI/backend PR, but its hypothesis contract is defined here.
- Placeholder scan: no TODO/TBD implementation step remains.
- Type consistency: engine/store/UI all pass `CareerIntakeDraft -> CareerGoal + CareerUnderstanding`; AI-produced future records use the same `CareerFactRecord.aiHypothesis` path.
- Scope check: Cooked output expansion, mission approval, 14-day sprint, proof/evidence expansion, sync restoration, and live Gemini remain independent later plans/PRs.
