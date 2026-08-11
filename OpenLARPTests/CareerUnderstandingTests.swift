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

    func testConfirmingOrEditingHypothesisResolvesItsUnknownKind() throws {
        let confirmedHypothesis = try CareerFactRecord.aiHypothesis(
            kind: .existingProof,
            value: "A class app demo",
            workflowRequestID: "request-1",
            createdAt: referenceDate
        )
        let editedHypothesis = try CareerFactRecord.aiHypothesis(
            kind: .constraints,
            value: "Weekends only",
            workflowRequestID: "request-1",
            createdAt: referenceDate
        )
        var understanding = CareerUnderstanding.reviewing(
            facts: [confirmedHypothesis, editedHypothesis],
            unknowns: [
                CareerUnknown(kind: .existingProof, lastUpdatedAt: referenceDate),
                CareerUnknown(kind: .constraints, lastUpdatedAt: referenceDate)
            ],
            reviewedAt: referenceDate
        )

        try understanding.confirmHypothesis(id: confirmedHypothesis.id, at: referenceDate)
        try understanding.editAndConfirmFact(
            id: editedHypothesis.id,
            value: "Evenings only",
            at: referenceDate
        )

        XCTAssertTrue(understanding.unknowns.isEmpty)
        XCTAssertEqual(understanding.confirmedFacts.count, 2)
        XCTAssertEqual(
            understanding.confirmedFacts.first(where: { $0.kind == .constraints })?.provenance.source,
            .userEdit
        )
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

    func testAdaptiveIntakeUsesOnlyExplicitlyConfirmedFactsAndPriorHypothesisDecisions() throws {
        var understanding = CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: "iOS Engineer",
            currentStatus: .newGrad,
            timeline: "90 days",
            urgency: .steady,
            experience: "Coursework and one class app",
            existingProof: "",
            constraints: "",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: ""
        ).makeUnderstanding(reviewedAt: referenceDate)
        let rejected = try CareerFactRecord.aiHypothesis(
            kind: .existingProof,
            value: "May have a public portfolio",
            workflowRequestID: "old-request",
            createdAt: referenceDate
        ).rejected(at: referenceDate.addingTimeInterval(1))
        understanding.facts.append(rejected)

        XCTAssertTrue(understanding.confirmedFacts.isEmpty)

        try understanding.confirmUserEntriesForAdaptiveIntake(at: referenceDate.addingTimeInterval(2))
        let request = V0AdaptiveCareerIntakeRequest(
            understanding: understanding,
            requestedAt: referenceDate.addingTimeInterval(3),
            requestID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        )

        XCTAssertTrue(request.confirmedFacts.allSatisfy {
            $0.confirmationState == .confirmed && $0.provenance.source != .aiHypothesis
        })
        XCTAssertEqual(request.rejectedHypothesisIDs, [rejected.id])
        XCTAssertEqual(request.unknownKinds, [.existingProof, .constraints, .biggestBlocker])
        XCTAssertEqual(request.maxQuestions, 1)
    }

    func testAdaptiveAnswerSupersedesSameKindHypothesisWithoutInventingConfirmation() throws {
        var draft = CareerIntakeDraft(
            outcomeType: .internship,
            targetOutcome: "iOS internship",
            currentStatus: .student,
            timeline: "This semester",
            urgency: .urgent,
            experience: "One class app",
            existingProof: "",
            constraints: "Evenings only",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: "Interview confidence"
        )
        var understanding = draft.makeUnderstanding(reviewedAt: referenceDate)
        try understanding.confirmUserEntriesForAdaptiveIntake(at: referenceDate)
        let requestID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let response = V0AdaptiveCareerIntakeResponse(
            requestID: requestID,
            run: V0AIWorkflowRun(
                kind: .adaptiveCareerIntake,
                providerRoute: .localMock,
                requestedAt: referenceDate
            ),
            questions: [
                V0AdaptiveCareerQuestion(
                    id: "adaptive-existingProof",
                    factKind: .existingProof,
                    question: "What work can you already show or explain?",
                    rationale: "This changes the first useful action.",
                    responseType: .freeText,
                    options: []
                )
            ],
            hypotheses: [
                V0AdaptiveCareerHypothesis(
                    kind: .existingProof,
                    value: "The class app may be available as proof."
                )
            ]
        )

        try understanding.addAdaptiveHypotheses(from: response, at: referenceDate)

        let hypothesis = try XCTUnwrap(understanding.pendingHypotheses.first)
        XCTAssertEqual(hypothesis.provenance.sourceIdentifier, requestID.uuidString)
        XCTAssertEqual(hypothesis.confirmationState, .awaitingConfirmation)

        let answer = "A screen recording and repository for my class app"
        try understanding.answerAdaptiveQuestion(
            response.questions[0],
            answer: answer,
            at: referenceDate.addingTimeInterval(30)
        )
        try draft.applyAdaptiveAnswer(answer, for: .existingProof)

        XCTAssertTrue(understanding.pendingHypotheses.isEmpty)
        XCTAssertFalse(understanding.unknowns.contains { $0.kind == .existingProof })
        XCTAssertEqual(
            understanding.facts.first(where: {
                $0.kind == .existingProof && $0.provenance.source == .userEntry
            })?.value,
            answer
        )
        XCTAssertEqual(draft.existingProof, answer)
    }

    func testRebuildingReviewPreservesAdaptiveDecisionsAndConfirmedAIProvenance() throws {
        var draft = CareerIntakeDraft(
            outcomeType: .internship,
            targetOutcome: "iOS internship",
            currentStatus: .student,
            timeline: "This semester",
            urgency: .urgent,
            experience: "One class app",
            existingProof: "",
            constraints: "",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: "Interview confidence"
        )
        var understanding = draft.makeUnderstanding(reviewedAt: referenceDate)
        let confirmedHypothesis = try CareerFactRecord.aiHypothesis(
            kind: .existingProof,
            value: "A screen recording of my class app",
            workflowRequestID: "adaptive-request",
            createdAt: referenceDate
        )
        let rejectedHypothesis = try CareerFactRecord.aiHypothesis(
            kind: .constraints,
            value: "Weekends only",
            workflowRequestID: "adaptive-request",
            createdAt: referenceDate
        )
        understanding.facts.append(contentsOf: [confirmedHypothesis, rejectedHypothesis])
        try understanding.confirmHypothesis(id: confirmedHypothesis.id, at: referenceDate)
        try understanding.rejectFact(id: rejectedHypothesis.id, at: referenceDate)
        try draft.applyAdaptiveAnswer(confirmedHypothesis.value, for: .existingProof)

        let rebuilt = understanding.rebuildingReview(
            using: draft,
            reviewedAt: referenceDate.addingTimeInterval(60)
        )
        let request = V0AdaptiveCareerIntakeRequest(
            understanding: rebuilt,
            requestedAt: referenceDate.addingTimeInterval(60)
        )

        XCTAssertEqual(
            rebuilt.facts.first(where: { $0.id == confirmedHypothesis.id })?.provenance.source,
            .aiHypothesis
        )
        XCTAssertEqual(
            rebuilt.facts.first(where: { $0.id == confirmedHypothesis.id })?.confirmationState,
            .confirmed
        )
        XCTAssertEqual(
            rebuilt.facts.first(where: { $0.id == rejectedHypothesis.id })?.confirmationState,
            .rejected
        )
        XCTAssertTrue(request.confirmedFacts.map(\.id).contains(confirmedHypothesis.id))
        XCTAssertEqual(request.rejectedHypothesisIDs, [rejectedHypothesis.id])
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

        XCTAssertEqual(decoded.schemaVersion, OpenLARPState.currentSchemaVersion)
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

    @MainActor
    func testStoreRecordsAdaptiveIntakeAuditWithoutPersistingDraftCareerText() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore,
            now: { self.referenceDate }
        )
        var understanding = CareerIntakeDraft(
            outcomeType: .job,
            targetOutcome: "PRIVATE-ADAPTIVE-TARGET",
            currentStatus: .newGrad,
            timeline: "90 days",
            urgency: .steady,
            experience: "One class app",
            existingProof: "",
            constraints: "Evenings only",
            confidence: 3,
            dailyCommitmentMinutes: 20,
            biggestBlocker: "Interview confidence"
        ).makeUnderstanding(reviewedAt: referenceDate)
        try understanding.confirmUserEntriesForAdaptiveIntake(at: referenceDate)

        let response = try await store.generateAdaptiveCareerIntake(
            for: understanding,
            expectedOwnerScope: store.onboardingOwnerScope
        )

        XCTAssertEqual(response.questions.map(\.factKind), [.existingProof])
        XCTAssertFalse(store.isAdaptiveIntakeRunning)
        XCTAssertEqual(store.state.aiWorkflowRuns.last?.kind, .adaptiveCareerIntake)
        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.aiWorkflowRuns.last?.kind, .adaptiveCareerIntake)
        XCTAssertFalse(
            String(decoding: try JSONEncoder.openLARPPersistence.encode(reloaded), as: UTF8.self)
                .contains("PRIVATE-ADAPTIVE-TARGET")
        )
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
