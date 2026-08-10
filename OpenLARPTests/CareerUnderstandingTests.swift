import XCTest
@testable import OpenLARP

final class CareerUnderstandingTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testAIHypothesisCannotUseImplicitConfirmationPath() throws {
        let hypothesis = try CareerFactRecord.aiHypothesis(
            kind: .experience,
            value: "Worked as an engineer",
            workflowRequestID: "request-1",
            createdAt: referenceDate
        )

        XCTAssertEqual(hypothesis.confirmationState, .awaitingConfirmation)
        XCTAssertEqual(hypothesis.provenance.source, .aiHypothesis)
        XCTAssertThrowsError(try hypothesis.confirmed(at: referenceDate)) { error in
            XCTAssertEqual(error as? CareerFactError, .aiHypothesisRequiresExplicitUserConfirmation)
        }
    }

    func testEditingHypothesisRecordsConfirmedUserEditInsteadOfAIProvenance() throws {
        let hypothesis = try CareerFactRecord.aiHypothesis(
            kind: .experience,
            value: "Worked as an engineer",
            workflowRequestID: "request-1",
            createdAt: referenceDate
        )

        let edited = try hypothesis.editedAndConfirmed(
            value: "Completed one engineering course",
            at: referenceDate.addingTimeInterval(60)
        )

        XCTAssertEqual(edited.value, "Completed one engineering course")
        XCTAssertEqual(edited.confirmationState, .confirmed)
        XCTAssertEqual(edited.provenance.source, .userEdit)
        XCTAssertEqual(edited.provenance.sourceIdentifier, hypothesis.id.uuidString)
        XCTAssertEqual(edited.lastUpdatedAt, referenceDate.addingTimeInterval(60))
    }

    func testRejectedHypothesisNeverAppearsAmongConfirmedFacts() throws {
        let hypothesis = try CareerFactRecord.aiHypothesis(
            kind: .experience,
            value: "Worked as an engineer",
            workflowRequestID: "request-1",
            createdAt: referenceDate
        )
        var understanding = CareerUnderstanding.reviewing(
            facts: [hypothesis],
            unknowns: [],
            reviewedAt: referenceDate
        )

        try understanding.rejectFact(
            id: hypothesis.id,
            at: referenceDate.addingTimeInterval(30)
        )

        XCTAssertTrue(understanding.confirmedFacts.isEmpty)
        XCTAssertEqual(understanding.rejectedFacts.map(\.id), [hypothesis.id])
        XCTAssertEqual(understanding.rejectedFacts.first?.lastUpdatedAt, referenceDate.addingTimeInterval(30))
        XCTAssertThrowsError(
            try understanding.confirmHypothesis(
                id: hypothesis.id,
                at: referenceDate.addingTimeInterval(60)
            )
        ) { error in
            XCTAssertEqual(error as? CareerFactError, .factIsNotAwaitingAIConfirmation)
        }
    }

    func testHypothesisConfirmationPathRejectsUserEnteredFacts() throws {
        let userFact = try XCTUnwrap(CareerFactRecord.userEntry(
            kind: .experience,
            value: "One class app",
            createdAt: referenceDate
        ))
        var understanding = CareerUnderstanding.reviewing(
            facts: [userFact],
            unknowns: [],
            reviewedAt: referenceDate
        )

        XCTAssertThrowsError(
            try understanding.confirmHypothesis(id: userFact.id, at: referenceDate)
        ) { error in
            XCTAssertEqual(error as? CareerFactError, .factIsNotAwaitingAIConfirmation)
        }
    }

    func testAIHypothesisRejectsBlankContentAndMissingWorkflowProvenance() {
        XCTAssertThrowsError(
            try CareerFactRecord.aiHypothesis(
                kind: .experience,
                value: "   ",
                workflowRequestID: "request-1",
                createdAt: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? CareerFactError, .emptyValue)
        }

        XCTAssertThrowsError(
            try CareerFactRecord.aiHypothesis(
                kind: .experience,
                value: "Completed one engineering course",
                workflowRequestID: "\n",
                createdAt: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? CareerFactError, .missingSourceIdentifier)
        }
    }

    func testCareerFactLengthsMatchBackendRequestBoundaries() throws {
        let longTarget = String(repeating: "T", count: 300)
        let longBlocker = String(repeating: "B", count: 1_500)
        let draft = CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: longTarget,
            currentStatus: .newGrad,
            timeline: String(repeating: "9", count: 300),
            urgency: .steady,
            experience: String(repeating: "E", count: 5_000),
            existingProof: "Proof",
            constraints: "Constraints",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: longBlocker
        )

        let goal = draft.makeGoal()
        let understanding = draft.makeUnderstanding(reviewedAt: referenceDate)

        XCTAssertEqual(goal.targetRole.count, 120)
        XCTAssertEqual(goal.timeline.count, 120)
        XCTAssertEqual(goal.background.count, 4_000)
        XCTAssertEqual(goal.biggestBlocker.count, 1_000)
        XCTAssertEqual(
            understanding.facts.first(where: { $0.kind == .targetOutcome })?.value.count,
            120
        )
        XCTAssertEqual(
            understanding.facts.first(where: { $0.kind == .biggestBlocker })?.value.count,
            1_000
        )
    }

    func testDraftCreatesUnknownsInsteadOfEmptyFactsAndApprovalConfirmsUserEntries() throws {
        let draft = CareerIntakeDraft(
            outcomeType: .internship,
            targetOutcome: "iOS engineering internship",
            currentStatus: .student,
            timeline: "This semester",
            urgency: .urgent,
            experience: "Built a class app",
            existingProof: "",
            constraints: "Can only work evenings",
            confidence: 4,
            dailyCommitmentMinutes: 30,
            biggestBlocker: "No interview experience"
        )
        var understanding = draft.makeUnderstanding(reviewedAt: referenceDate)

        XCTAssertEqual(understanding.reviewState, .reviewing)
        XCTAssertEqual(understanding.unknowns.map(\.kind), [.existingProof])
        XCTAssertFalse(understanding.facts.contains { $0.kind == .existingProof })
        XCTAssertTrue(understanding.facts.allSatisfy {
            $0.provenance.source == .userEntry && $0.confirmationState == .awaitingConfirmation
        })

        try understanding.approve(at: referenceDate.addingTimeInterval(45))

        XCTAssertEqual(understanding.reviewState, .approved)
        XCTAssertTrue(understanding.pendingHypotheses.isEmpty)
        XCTAssertTrue(understanding.facts.allSatisfy { $0.confirmationState == .confirmed })
        XCTAssertEqual(understanding.approvedAt, referenceDate.addingTimeInterval(45))
    }

    func testLegacyCareerGoalJSONUsesSafeDefaultsForNewUnderstandingFields() throws {
        let data = Data(
            #"{"currentStatus":"Student","targetRole":"iOS Engineer","timeline":"90 days","background":"Coursework","existingProof":"Class app","confidence":4,"biggestBlocker":"Interviews"}"#.utf8
        )

        let goal = try JSONDecoder().decode(CareerGoal.self, from: data)

        XCTAssertEqual(goal.outcomeType, .job)
        XCTAssertEqual(goal.urgency, .steady)
        XCTAssertEqual(goal.constraints, "")
        XCTAssertEqual(goal.dailyCommitmentMinutes, 25)
    }

    func testSchemaTenStateMigratesLegacyGoalIntoApprovedProvenancedFacts() throws {
        var legacyState = OpenLARPState.empty
        legacyState.goal = CareerGoal(
            currentStatus: .student,
            targetRole: "iOS Engineer",
            timeline: "90 days",
            background: "Coursework",
            existingProof: "",
            confidence: 4,
            biggestBlocker: "Interviews"
        )
        legacyState.updatedAt = referenceDate
        let encoded = try JSONEncoder.openLARPPersistence.encode(legacyState)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 10
        object.removeValue(forKey: "careerUnderstanding")
        object.removeValue(forKey: "onboardingFunnel")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let decoded = try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, 11)
        XCTAssertEqual(decoded.careerUnderstanding.reviewState, .approved)
        XCTAssertEqual(
            decoded.careerUnderstanding.unknowns.map(\.kind),
            [.outcomeType, .urgency, .existingProof, .constraints, .dailyCommitment]
        )
        XCTAssertTrue(decoded.careerUnderstanding.facts.allSatisfy {
            $0.provenance.source == .legacyMigration && $0.confirmationState == .confirmed
        })
        XCTAssertFalse(decoded.careerUnderstanding.facts.contains {
            [.outcomeType, .urgency, .dailyCommitment].contains($0.kind)
        })
        XCTAssertEqual(
            decoded.careerUnderstanding.confirmedFacts.first(where: { $0.kind == .targetOutcome })?.value,
            "iOS Engineer"
        )
    }

    func testSchemaElevenStateMissingCareerUnderstandingFailsClosed() throws {
        var state = OpenLARPState.empty
        state.goal = makeCompleteDraft().makeGoal()
        let encoded = try JSONEncoder.openLARPPersistence.encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "careerUnderstanding")
        let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        XCTAssertThrowsError(
            try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: invalidData)
        ) { error in
            XCTAssertEqual(error as? OpenLARPPersistenceError, .unrecoverableState)
        }
    }

    func testEngineRejectsUnderstandingThatHasNotBeenApproved() throws {
        let draft = makeCompleteDraft()
        let goal = draft.makeGoal()
        let reviewing = draft.makeUnderstanding(reviewedAt: referenceDate)

        XCTAssertThrowsError(
            try OpenLARPEngine.confirmGoal(
                goal,
                understanding: reviewing,
                now: referenceDate
            )
        ) { error in
            XCTAssertEqual(error as? OpenLARPError, .careerUnderstandingNeedsReview)
        }
    }

    func testEngineStoresExactApprovedUnderstandingWithoutReplacingProvenance() throws {
        let draft = makeCompleteDraft()
        let goal = draft.makeGoal()
        var approved = draft.makeUnderstanding(reviewedAt: referenceDate)
        try approved.approve(at: referenceDate.addingTimeInterval(10))

        let state = try OpenLARPEngine.confirmGoal(
            goal,
            understanding: approved,
            now: referenceDate.addingTimeInterval(20)
        )

        XCTAssertEqual(state.goal, goal)
        XCTAssertEqual(state.careerUnderstanding, approved)
        XCTAssertTrue(state.careerUnderstanding.facts.allSatisfy {
            $0.provenance.source == .userEntry
        })
    }

    func testCompatibilityEnginePathCreatesAnApprovedUserSourcedUnderstanding() {
        let goal = makeCompleteDraft().makeGoal()

        let state = OpenLARPEngine.confirmGoal(goal, now: referenceDate)

        XCTAssertEqual(state.careerUnderstanding.reviewState, .approved)
        XCTAssertTrue(state.careerUnderstanding.pendingHypotheses.isEmpty)
        XCTAssertTrue(state.careerUnderstanding.facts.allSatisfy {
            $0.provenance.source == .userEntry && $0.confirmationState == .confirmed
        })
    }

    @MainActor
    func testStoreApprovesDraftBeforePersistingGoalAndEvaluation() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { self.referenceDate }
        )

        let draft = makeCompleteDraft()
        let reviewing = draft.makeUnderstanding(reviewedAt: referenceDate)
        let reviewedIDs = reviewing.facts.map(\.id)
        let succeeded = await store.approveCareerUnderstanding(
            reviewing,
            goal: draft.makeGoal(),
            expectedOwnerScope: store.onboardingOwnerScope
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(store.state.goal?.targetRole, "iOS Engineer")
        XCTAssertEqual(store.state.careerUnderstanding.reviewState, .approved)
        XCTAssertEqual(store.state.careerUnderstanding.approvedAt, referenceDate)
        XCTAssertTrue(store.state.careerUnderstanding.facts.allSatisfy {
            $0.confirmationState == .confirmed
        })
        XCTAssertEqual(store.state.careerUnderstanding.facts.map(\.id), reviewedIDs)
    }

    @MainActor
    func testStorePersistsExactReviewedHypothesisDecision() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { self.referenceDate }
        )
        let draft = makeCompleteDraft()
        var reviewing = draft.makeUnderstanding(reviewedAt: referenceDate)
        let hypothesis = try CareerFactRecord.aiHypothesis(
            kind: .experience,
            value: "May have role-adjacent experience",
            workflowRequestID: "workflow-1",
            createdAt: referenceDate
        )
        reviewing.facts.append(hypothesis)
        try reviewing.confirmHypothesis(id: hypothesis.id, at: referenceDate)

        let succeeded = await store.approveCareerUnderstanding(
            reviewing,
            goal: draft.makeGoal(),
            expectedOwnerScope: store.onboardingOwnerScope
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(
            store.state.careerUnderstanding.facts.first(where: { $0.id == hypothesis.id })?.confirmationState,
            .confirmed
        )
        XCTAssertEqual(
            store.state.careerUnderstanding.facts.first(where: { $0.id == hypothesis.id })?.provenance.source,
            .aiHypothesis
        )
    }

    @MainActor
    func testStoreRejectsApprovalForStaleOwnerScope() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { self.referenceDate }
        )
        let draft = makeCompleteDraft()

        let succeeded = await store.approveCareerUnderstanding(
            draft.makeUnderstanding(reviewedAt: referenceDate),
            goal: draft.makeGoal(),
            expectedOwnerScope: "stale-owner-scope"
        )

        XCTAssertFalse(succeeded)
        XCTAssertTrue(store.state.needsGoalSetup)
    }

    @MainActor
    func testApprovalDoesNotAdvanceWhenPersistenceFails() async {
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: URL(fileURLWithPath: "/dev/null")),
            attachmentStore: OpenLARPAttachmentStore(
                directory: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            now: { self.referenceDate }
        )
        let draft = makeCompleteDraft()

        let succeeded = await store.approveCareerUnderstanding(
            draft.makeUnderstanding(reviewedAt: referenceDate),
            goal: draft.makeGoal(),
            expectedOwnerScope: store.onboardingOwnerScope
        )

        XCTAssertFalse(succeeded)
        XCTAssertTrue(store.state.needsGoalSetup)
        XCTAssertEqual(store.errorMessage, "Local progress could not be saved.")
    }

    func testGuidedOnboardingRequiresAnOutcomeBeforeAdvancing() throws {
        var flow = CareerOnboardingFlow()

        XCTAssertThrowsError(try flow.advance(using: .empty)) { error in
            XCTAssertEqual(error as? CareerOnboardingFlowError, .targetOutcomeRequired)
        }
        XCTAssertEqual(flow.step, .outcome)
    }

    func testGuidedOnboardingAdvancesThroughShortStepsAndCanReturn() throws {
        var flow = CareerOnboardingFlow()
        var draft = makeCompleteDraft()

        try flow.advance(using: draft)
        XCTAssertEqual(flow.step, .currentReality)
        XCTAssertEqual(flow.progressText, "2 of 4")

        draft.existingProof = ""
        draft.constraints = ""
        try flow.advance(using: draft)
        XCTAssertEqual(flow.step, .commitment)

        try flow.advance(using: draft)
        XCTAssertEqual(flow.step, .review)
        XCTAssertThrowsError(try flow.advance(using: draft)) { error in
            XCTAssertEqual(error as? CareerOnboardingFlowError, .approvalRequired)
        }

        flow.goBack()
        XCTAssertEqual(flow.step, .commitment)
    }

    func testAccountEntryPolicyKeepsPublicBuildDirectAndServiceBetaOptional() {
        let localSession = BackendUserSession.localOnly(for: .empty)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "user-1",
            accountID: "account-1"
        )

        XCTAssertEqual(
            OnboardingAccountEntryPolicy.mode(
                configuration: .appStoreMVP,
                session: localSession
            ),
            .directLocal
        )
        XCTAssertEqual(
            OnboardingAccountEntryPolicy.mode(
                configuration: .internalBeta,
                session: localSession
            ),
            .offerAccountOrLocal
        )
        XCTAssertEqual(
            OnboardingAccountEntryPolicy.mode(
                configuration: .internalBeta,
                session: authenticatedSession
            ),
            .alreadyLinked
        )
    }

    @MainActor
    func testServiceOnboardingWaitsForInitialAuthenticationResolution() async {
        let localDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let betaDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStore = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: localDirectory),
            attachmentStore: OpenLARPAttachmentStore(directory: localDirectory),
            releaseConfiguration: .appStoreMVP
        )
        let betaStore = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: betaDirectory),
            attachmentStore: OpenLARPAttachmentStore(directory: betaDirectory),
            releaseConfiguration: .internalBeta
        )

        XCTAssertTrue(localStore.didFinishInitialAuthenticationResolution)
        XCTAssertFalse(betaStore.didFinishInitialAuthenticationResolution)

        await betaStore.restorePreviousAuthenticationSession()

        XCTAssertTrue(betaStore.didFinishInitialAuthenticationResolution)
    }

    @MainActor
    func testOnboardingMeasurementIsIdempotentAndDoesNotExportCareerText() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore,
            now: { self.referenceDate }
        )
        var draft = makeCompleteDraft()
        draft.targetOutcome = "UNIQUE-PRIVATE-TARGET-STRING"

        store.recordOnboardingStarted()
        store.recordOnboardingStarted()
        store.recordCareerUnderstandingReviewed()
        store.recordCareerUnderstandingReviewed()
        let reloaded = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore,
            now: { self.referenceDate }
        )
        reloaded.recordOnboardingStarted()
        reloaded.recordCareerUnderstandingReviewed()
        let succeeded = await reloaded.approveCareerUnderstanding(
            draft.makeUnderstanding(reviewedAt: referenceDate),
            goal: draft.makeGoal(),
            expectedOwnerScope: reloaded.onboardingOwnerScope
        )

        XCTAssertTrue(succeeded)
        let summary = BetaMeasurementSummaryContent(
            state: reloaded.state,
            generatedAt: referenceDate
        )
        let counts = Dictionary(uniqueKeysWithValues: summary.eventCounts.map { ($0.kind, $0.count) })
        XCTAssertEqual(counts[.onboardingStarted], 1)
        XCTAssertEqual(counts[.careerUnderstandingReviewed], 1)
        XCTAssertEqual(counts[.careerUnderstandingApproved], 1)
        XCTAssertEqual(
            reloaded.state.onboardingFunnel,
            OnboardingFunnelState(
                didRecordStart: true,
                didRecordUnderstandingReview: true,
                didRecordUnderstandingApproval: true
            )
        )
        let encoded = try JSONEncoder.openLARPPersistence.encode(summary)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("UNIQUE-PRIVATE-TARGET-STRING"))
    }

    private func makeCompleteDraft() -> CareerIntakeDraft {
        CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: "iOS Engineer",
            currentStatus: .newGrad,
            timeline: "90 days",
            urgency: .steady,
            experience: "Coursework and one class app",
            existingProof: "A working app demo",
            constraints: "Evenings only",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: "Interview confidence"
        )
    }
}
