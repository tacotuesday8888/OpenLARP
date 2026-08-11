import XCTest
@testable import OpenLARP

final class MissionBriefTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_100_000)

    func testMissionProposalUsesOnlyConfirmedCareerFactsAndWaitsForApproval() throws {
        let goal = testGoal
        var understanding = CareerIntakeDraft(goal: goal).makeApprovedUnderstanding(approvedAt: now)
        let pending = try CareerFactRecord.aiHypothesis(
            kind: .experience,
            value: "Worked at an unnamed startup",
            workflowRequestID: "adaptive-request",
            createdAt: now
        )
        understanding.facts.append(pending)
        let diagnostic = testDiagnostic

        let mission = try CareerMissionBrief.localProposal(
            goal: goal,
            understanding: understanding,
            diagnostic: diagnostic,
            generatedAt: now
        )

        XCTAssertEqual(mission.reviewState, .awaitingApproval)
        XCTAssertNil(mission.approvedAt)
        XCTAssertTrue(mission.confirmedCurrentState.allSatisfy {
            $0.confirmationState == .confirmed
        })
        XCTAssertFalse(mission.confirmedCurrentState.contains { $0.id == pending.id })
        XCTAssertEqual(mission.targetOutcome, goal.targetRole)
        XCTAssertEqual(mission.dailyCommitmentMinutes, goal.dailyCommitmentMinutes)
        XCTAssertEqual(mission.sprint.dayCount, 14)
        XCTAssertEqual(mission.sprint.chapterCount, 2)
    }

    func testMissionEditsRemainPendingUntilExplicitApproval() throws {
        let mission = try CareerMissionBrief.localProposal(
            goal: testGoal,
            understanding: CareerIntakeDraft(goal: testGoal).makeApprovedUnderstanding(approvedAt: now),
            diagnostic: testDiagnostic,
            generatedAt: now
        )

        let edited = try mission.applyingUserEdits(
            constraints: "Weeknights only",
            mainReadinessGaps: ["Needs one role-specific proof artifact"],
            firstMilestone: "Publish one truthful project walkthrough",
            dailyCommitmentMinutes: 30,
            sprintSummary: "Chapter one builds proof; chapter two turns it into repeatable job-search action.",
            editedAt: now.addingTimeInterval(60)
        )

        XCTAssertEqual(edited.reviewState, .awaitingApproval)
        XCTAssertNil(edited.approvedAt)
        XCTAssertEqual(edited.constraints, "Weeknights only")
        XCTAssertEqual(edited.firstMilestone, "Publish one truthful project walkthrough")
        XCTAssertEqual(edited.lastUpdatedAt, now.addingTimeInterval(60))

        let approved = try edited.approved(at: now.addingTimeInterval(120))
        XCTAssertEqual(approved.reviewState, .approved)
        XCTAssertEqual(approved.approvedAt, now.addingTimeInterval(120))
    }

    func testMissionEditRejectsInvalidFieldsAndTimeReversal() throws {
        let mission = try CareerMissionBrief.localProposal(
            goal: testGoal,
            understanding: CareerIntakeDraft(goal: testGoal).makeApprovedUnderstanding(approvedAt: now),
            diagnostic: testDiagnostic,
            generatedAt: now
        )

        XCTAssertThrowsError(try mission.applyingUserEdits(
            constraints: "",
            mainReadinessGaps: ["Proof gap"],
            firstMilestone: "   ",
            dailyCommitmentMinutes: 30,
            sprintSummary: "Two focused chapters.",
            editedAt: now
        ))
        XCTAssertThrowsError(try mission.applyingUserEdits(
            constraints: "",
            mainReadinessGaps: ["Proof gap"],
            firstMilestone: "Create one proof artifact",
            dailyCommitmentMinutes: 30,
            sprintSummary: "Two focused chapters.",
            editedAt: now.addingTimeInterval(-1)
        ))
        XCTAssertThrowsError(try mission.applyingUserEdits(
            constraints: "",
            mainReadinessGaps: ["Proof gap"],
            firstMilestone: "Create one proof artifact",
            dailyCommitmentMinutes: 240,
            sprintSummary: "Two focused chapters.",
            editedAt: now
        ))
    }

    func testPreparedMissionStateCannotExposeAQuestBeforeMissionApproval() throws {
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeApprovedUnderstanding(approvedAt: now)
        let diagnostic = testDiagnostic
        let mission = try CareerMissionBrief.localProposal(
            goal: testGoal,
            understanding: understanding,
            diagnostic: diagnostic,
            generatedAt: now
        )

        let state = try OpenLARPEngine.prepareMission(
            testGoal,
            understanding: understanding,
            diagnostic: diagnostic,
            mission: mission,
            now: now
        )

        XCTAssertTrue(state.needsMissionApproval)
        XCTAssertTrue(state.plan.isEmpty)
        XCTAssertNil(state.currentQuest)
        XCTAssertFalse(state.needsCareerIntake)
    }

    func testPendingMissionRoundTripsWithoutStartingTheSprint() throws {
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeApprovedUnderstanding(approvedAt: now)
        let mission = try CareerMissionBrief.localProposal(
            goal: testGoal,
            understanding: understanding,
            diagnostic: testDiagnostic,
            generatedAt: now
        )
        let state = try OpenLARPEngine.prepareMission(
            testGoal,
            understanding: understanding,
            diagnostic: testDiagnostic,
            mission: mission,
            now: now
        )

        let data = try JSONEncoder.openLARPPersistence.encode(state)
        let decoded = try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: data)

        XCTAssertEqual(decoded.mission, mission)
        XCTAssertTrue(decoded.needsMissionApproval)
        XCTAssertTrue(decoded.plan.isEmpty)
        XCTAssertFalse(decoded.subscriptionState.hasStartedAccessLifecycle)
    }

    func testSchemaElevenPlanMigratesToAnApprovedLegacyMission() throws {
        let legacy = OpenLARPEngine.confirmGoal(testGoal, now: now)
        let data = try JSONEncoder.openLARPPersistence.encode(legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 11
        object.removeValue(forKey: "mission")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let decoded = try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, OpenLARPState.currentSchemaVersion)
        XCTAssertEqual(decoded.mission?.reviewState, .approved)
        XCTAssertEqual(decoded.mission?.targetOutcome, testGoal.targetRole)
        XCTAssertFalse(decoded.needsMissionApproval)
        XCTAssertFalse(decoded.plan.isEmpty)
    }

    func testPersistenceRejectsAnImpossibleApprovedMissionState() throws {
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeApprovedUnderstanding(approvedAt: now)
        let mission = try CareerMissionBrief.localProposal(
            goal: testGoal,
            understanding: understanding,
            diagnostic: testDiagnostic,
            generatedAt: now
        )
        let state = try OpenLARPEngine.prepareMission(
            testGoal,
            understanding: understanding,
            diagnostic: testDiagnostic,
            mission: mission,
            now: now
        )
        let data = try JSONEncoder.openLARPPersistence.encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var missionObject = try XCTUnwrap(object["mission"] as? [String: Any])
        missionObject["reviewState"] = CareerMissionReviewState.approved.rawValue
        missionObject.removeValue(forKey: "approvedAt")
        object["mission"] = missionObject
        let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        XCTAssertThrowsError(
            try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: invalidData)
        )
    }

    func testPersistenceRejectsAnApprovedMissionWithoutItsQuestChapter() throws {
        let approvedState = OpenLARPEngine.confirmGoal(testGoal, now: now)
        let data = try JSONEncoder.openLARPPersistence.encode(approvedState)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["plan"] = []
        let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        XCTAssertThrowsError(
            try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: invalidData)
        )
    }

    func testCookedShareCardPointsToMissionApprovalBeforeAQuestExists() throws {
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeApprovedUnderstanding(approvedAt: now)
        let mission = try CareerMissionBrief.localProposal(
            goal: testGoal,
            understanding: understanding,
            diagnostic: testDiagnostic,
            generatedAt: now
        )
        let state = try OpenLARPEngine.prepareMission(
            testGoal,
            understanding: understanding,
            diagnostic: testDiagnostic,
            mission: mission,
            now: now
        )

        let content = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))

        XCTAssertEqual(content.recoveryText, "Recovery path: approve an honest 14-day mission before any quests begin.")
        XCTAssertEqual(content.detailText, "First move: review and approve the editable mission.")
    }

    @MainActor
    func testStorePersistsCookedEvaluationAndMissionBeforeRequestingAQuestPlan() async throws {
        let fixture = try storeFixture()
        defer { fixture.cleanup() }
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeUnderstanding(reviewedAt: now)

        let succeeded = await fixture.store.approveCareerUnderstanding(
            understanding,
            goal: testGoal,
            expectedOwnerScope: fixture.store.onboardingOwnerScope
        )

        XCTAssertTrue(succeeded)
        XCTAssertTrue(fixture.store.state.needsMissionApproval)
        XCTAssertEqual(fixture.store.state.mission?.reviewState, .awaitingApproval)
        XCTAssertTrue(fixture.store.state.plan.isEmpty)
        XCTAssertNil(fixture.store.state.currentQuest)
        XCTAssertEqual(fixture.store.state.aiWorkflowRuns.suffix(2).map(\.kind), [
            .cookedDiagnostic,
            .missionBrief
        ])
    }

    @MainActor
    func testStoreGeneratesQuestPlanOnlyAfterEditedMissionIsExplicitlyApproved() async throws {
        let fixture = try storeFixture()
        defer { fixture.cleanup() }
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeUnderstanding(reviewedAt: now)
        let prepared = await fixture.store.approveCareerUnderstanding(
            understanding,
            goal: testGoal,
            expectedOwnerScope: fixture.store.onboardingOwnerScope
        )
        XCTAssertTrue(prepared)
        let proposed = try XCTUnwrap(fixture.store.state.mission)
        let edited = try proposed.applyingUserEdits(
            constraints: "Weeknights only",
            mainReadinessGaps: ["Needs one role-specific walkthrough"],
            firstMilestone: "Publish one truthful project walkthrough",
            dailyCommitmentMinutes: 30,
            sprintSummary: proposed.sprint.summary,
            editedAt: now
        )

        let approved = await fixture.store.approveMissionBrief(
            edited,
            expectedOwnerScope: fixture.store.onboardingOwnerScope
        )

        XCTAssertTrue(approved)
        XCTAssertEqual(fixture.store.state.mission?.reviewState, .approved)
        XCTAssertEqual(fixture.store.state.mission?.firstMilestone, "Publish one truthful project walkthrough")
        XCTAssertEqual(fixture.store.state.plan.count, 7)
        XCTAssertTrue(fixture.store.state.plan.allSatisfy { $0.timeEstimateMinutes <= 30 })
        XCTAssertNotNil(fixture.store.state.currentQuest)
        XCTAssertEqual(fixture.store.state.aiWorkflowRuns.last?.kind, .questPlan)
    }

    @MainActor
    func testStoreFallsBackToACompleteChapterWhenGeneratedPlanIsTooShort() async throws {
        let fixture = try storeFixture(aiWorkflowService: ShortPlanAIWorkflowService())
        defer { fixture.cleanup() }
        let understanding = CareerIntakeDraft(goal: testGoal)
            .makeUnderstanding(reviewedAt: now)
        let prepared = await fixture.store.approveCareerUnderstanding(
            understanding,
            goal: testGoal,
            expectedOwnerScope: fixture.store.onboardingOwnerScope
        )
        XCTAssertTrue(prepared)
        let mission = try XCTUnwrap(fixture.store.state.mission)

        let approved = await fixture.store.approveMissionBrief(
            mission,
            expectedOwnerScope: fixture.store.onboardingOwnerScope
        )

        XCTAssertTrue(approved)
        XCTAssertEqual(fixture.store.state.plan.count, 7)
        XCTAssertTrue(fixture.store.state.aiWorkflowRuns.last?.usedFallback == true)
    }

    private var testGoal: CareerGoal {
        CareerGoal(
            currentStatus: .newGrad,
            targetRole: "iOS Engineer",
            timeline: "Within 90 days",
            background: "One shipped class app",
            existingProof: "A public repository",
            confidence: 3,
            biggestBlocker: "Role-specific proof",
            outcomeType: .job,
            urgency: .steady,
            constraints: "Evenings only",
            dailyCommitmentMinutes: 20
        )
    }

    private var testDiagnostic: CookedDiagnostic {
        CookedDiagnostic(
            score: 55,
            label: "Recoverable",
            mainGap: "Role-specific proof",
            strongestSignal: "One shipped class app",
            fastestFix: "Create one focused walkthrough",
            readinessBaseline: 45,
            strongestSignals: ["One shipped class app"],
            readinessGaps: ["Role-specific proof"],
            missingInformation: [],
            uncertaintyExplanation: "This is directional because hiring context is incomplete.",
            firstAction: "Outline one project walkthrough"
        )
    }

    @MainActor
    private func storeFixture(
        aiWorkflowService: any V0AIWorkflowServicing = LocalMockV0AIWorkflowService()
    ) throws -> (store: OpenLARPStore, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLARP-MissionTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            aiWorkflowService: aiWorkflowService,
            releaseConfiguration: .internalBeta,
            now: { self.now }
        )
        return (
            store,
            { try? FileManager.default.removeItem(at: directory) }
        )
    }
}

private struct ShortPlanAIWorkflowService: V0AIWorkflowServicing {
    private let local = LocalMockV0AIWorkflowService()

    func generateAdaptiveCareerIntake(
        _ request: V0AdaptiveCareerIntakeRequest
    ) async throws -> V0AdaptiveCareerIntakeResponse {
        try await local.generateAdaptiveCareerIntake(request)
    }

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        try await local.generateDiagnostic(request)
    }

    func generateMissionBrief(_ request: V0MissionBriefRequest) async throws -> V0MissionBriefResponse {
        try await local.generateMissionBrief(request)
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        var response = try await local.generateQuestPlan(request)
        response.quests = Array(response.quests.prefix(1))
        return response
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        try await local.reviewProof(request)
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        try await local.summarizeProgress(request)
    }
}
