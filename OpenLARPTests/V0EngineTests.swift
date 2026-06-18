import XCTest
@testable import OpenLARP

final class V0EngineTests: XCTestCase {
    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let goal = CareerGoal(
        currentStatus: .student,
        targetRole: "iOS engineering internship",
        timeline: "30 days",
        background: "Second-year CS student with one class project and no shipped app yet.",
        existingProof: "Class project, SwiftUI tutorial clone",
        confidence: 3,
        biggestBlocker: "I do not have strong proof that I can build production-quality apps."
    )

    func testGoalSetupCreatesDiagnosticAndSevenDayPlan() {
        let state = OpenLARPEngine.confirmGoal(goal)

        XCTAssertEqual(state.goal, goal)
        XCTAssertEqual(state.diagnostic?.label, "Medium Cooked")
        XCTAssertEqual(state.plan.count, 7)
        XCTAssertEqual(state.currentQuest?.status, .available)
        XCTAssertEqual(state.currentQuest?.gap, .proofStrength)
        XCTAssertEqual(state.progress.readiness.overall, 42)
    }

    func testGoalSetupUsesDiagnosticReadinessBaseline() {
        let now = Date(timeIntervalSince1970: 16_000)
        let diagnostic = CookedDiagnostic(
            score: 71,
            label: "Less Cooked",
            mainGap: "Proof is improving, but still thin.",
            strongestSignal: "A shipped class project.",
            fastestFix: "Turn the project into a reusable proof artifact.",
            readinessBaseline: 67
        )
        let quest = Quest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            day: 4,
            title: "Create a proof artifact",
            purpose: "Show one target-role skill with evidence.",
            timeEstimateMinutes: 120,
            proofRequired: "Add the artifact link or screenshot.",
            xpReward: 500,
            status: .completed
        )

        let state = OpenLARPEngine.confirmGoal(
            goal,
            diagnostic: diagnostic,
            plan: [quest],
            now: now
        )

        XCTAssertEqual(state.progress.readiness.overall, 67)
        XCTAssertEqual(state.progress.readinessHistory.first?.overall, 67)
        XCTAssertEqual(state.plan.first?.status, .available)
        XCTAssertEqual(state.plan.first?.day, 1)
        XCTAssertEqual(state.plan.first?.xpReward, 180)
        XCTAssertEqual(state.plan.first?.timeEstimateMinutes, 90)
    }

    func testCookedDiagnosticResultContentShowsScoreReadinessAndFirstQuest() throws {
        let state = OpenLARPEngine.confirmGoal(goal)

        let content = try XCTUnwrap(CookedDiagnosticResultContent(state: state))

        XCTAssertEqual(content.eyebrow, "Am I Cooked?")
        XCTAssertEqual(content.title, "Medium Cooked")
        XCTAssertEqual(content.scoreText, "58/100 cooked")
        XCTAssertEqual(content.readinessText, "42% ready")
        XCTAssertEqual(content.mainGap, state.diagnostic?.mainGap)
        XCTAssertEqual(content.strongestSignal, state.diagnostic?.strongestSignal)
        XCTAssertEqual(content.fastestFix, state.diagnostic?.fastestFix)
        XCTAssertEqual(content.firstQuestID, state.plan[0].id)
        XCTAssertEqual(content.firstQuestTitle, state.plan[0].title)
        XCTAssertEqual(content.firstQuestMetaText, "25 min, Starter, +120 XP")
        XCTAssertEqual(content.primaryActionTitle, "Start My First Quest")
        XCTAssertEqual(content.shareActionTitle, "Share Cooked Card")
        XCTAssertEqual(content.adjustGoalActionTitle, "Adjust Goal")
    }

    func testCookedDiagnosticResultContentIsNilBeforeGoalSetup() {
        XCTAssertNil(CookedDiagnosticResultContent(state: .empty))
    }

    func testCookedDiagnosticResultContentSanitizesPrivateTargetRoleInExplanation() throws {
        let privateGoal = CareerGoal(
            currentStatus: .student,
            targetRole: "/Users/langqi/private/F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1/sk-test-secret-api-key.txt",
            timeline: "30 days",
            background: "",
            existingProof: "",
            confidence: 3,
            biggestBlocker: ""
        )
        let state = OpenLARPEngine.confirmGoal(privateGoal)

        let content = try XCTUnwrap(CookedDiagnosticResultContent(state: state))

        XCTAssertTrue(content.explanationText.contains("your career goal"))
        XCTAssertFalse(content.explanationText.contains("/Users"))
        XCTAssertFalse(content.explanationText.contains("F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1"))
        XCTAssertFalse(content.explanationText.contains("sk-test-secret"))
        XCTAssertFalse(content.explanationText.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(content.explanationText.contains(".txt"))
    }

    func testCookedShareCardContentHidesPrivateGoalSetupDetailsByDefault() throws {
        let sensitiveGoal = CareerGoal(
            currentStatus: .student,
            targetRole: "AI product internship",
            timeline: "30 days",
            background: "Private background: langqi@example.com, campus office, and personal visa concern.",
            existingProof: "Secret Project Falcon, https://private.example.com/proof, and private repo notes.",
            confidence: 2,
            biggestBlocker: "Family money stress and confidential hiring anxiety."
        )
        let state = OpenLARPEngine.confirmGoal(sensitiveGoal)

        let content = try XCTUnwrap(CookedShareCardContent(state: state))
        let displayText = content.displayText + " " + content.shareText

        XCTAssertEqual(content.title, "Am I cooked for AI product internship?")
        XCTAssertTrue(displayText.contains("AI product internship"))
        XCTAssertTrue(displayText.contains("Medium Cooked"))
        XCTAssertFalse(displayText.contains("langqi@example.com"))
        XCTAssertFalse(displayText.contains("campus office"))
        XCTAssertFalse(displayText.contains("visa"))
        XCTAssertFalse(displayText.contains("Secret Project Falcon"))
        XCTAssertFalse(displayText.contains("private.example.com"))
        XCTAssertFalse(displayText.contains("Family money"))
        XCTAssertFalse(displayText.contains(sensitiveGoal.background))
        XCTAssertFalse(displayText.contains(sensitiveGoal.existingProof))
        XCTAssertFalse(displayText.contains(sensitiveGoal.biggestBlocker))
    }

    func testCookedShareCardContentNeverLeaksLocalPathsUUIDsOrSecrets() throws {
        let now = Date(timeIntervalSince1970: 16_100)
        let attachmentID = UUID(uuidString: "F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1")!
        let proofID = UUID(uuidString: "F2F2F2F2-F2F2-F2F2-F2F2-F2F2F2F2F2F2")!
        let attachment = ProofAttachment(
            id: attachmentID,
            fileName: "local-private-proof.png",
            originalFileName: "private-screenshot.png",
            contentType: "image/png",
            byteCount: 40_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let proof = ProofRecord(
            id: proofID,
            questID: UUID(uuidString: "F3F3F3F3-F3F3-F3F3-F3F3-F3F3F3F3F3F3")!,
            questTitle: "Private proof quest",
            kind: .proof,
            text: "Sensitive proof text with sk-test-secret and internal recruiter notes.",
            link: "https://private.example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Concrete enough to count.",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
        let outcome = CareerOutcomeRecord(
            kind: .interview,
            title: "Private recruiter screen",
            organizationName: "Example Labs",
            note: "Sensitive recruiter note should stay private.",
            occurredAt: now,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        state.outcomeLog = [outcome]

        let content = try XCTUnwrap(CookedShareCardContent(state: state))
        let displayText = content.displayText + " " + content.shareText

        XCTAssertFalse(displayText.contains(attachmentID.uuidString))
        XCTAssertFalse(displayText.contains(proofID.uuidString))
        XCTAssertFalse(displayText.contains("ProofAttachments"))
        XCTAssertFalse(displayText.contains("private-device-path"))
        XCTAssertFalse(displayText.contains("sk-test-secret"))
        XCTAssertFalse(displayText.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(displayText.contains("Sensitive recruiter note"))
        XCTAssertFalse(displayText.contains("private.example.com"))
    }

    func testCookedShareCardContentFallsBackWhenTargetRoleLooksPrivate() throws {
        let privateRole = "/Users/langqi/private/F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1/sk-test-secret-api-key.txt"
        let privateGoal = CareerGoal(
            currentStatus: .student,
            targetRole: privateRole,
            timeline: "30 days",
            background: "",
            existingProof: "",
            confidence: 3,
            biggestBlocker: ""
        )
        let state = OpenLARPEngine.confirmGoal(privateGoal)

        let content = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))
        let displayText = content.displayText + " " + content.shareText

        XCTAssertEqual(content.targetRole, "my career goal")
        XCTAssertTrue(displayText.contains("my career goal"))
        XCTAssertFalse(displayText.contains("/Users"))
        XCTAssertFalse(displayText.contains("F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1"))
        XCTAssertFalse(displayText.contains("sk-test-secret"))
        XCTAssertFalse(displayText.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(displayText.contains(".txt"))
    }

    func testCookedShareCardDetailedModeUsesGenericPublicDetail() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state.plan[0].title = "Use private proof from /Users/langqi/SecretProject and sk-test-secret"

        let content = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))
        let displayText = content.displayText + " " + content.shareText

        XCTAssertEqual(content.detailText, "First move: start one proof-building quest.")
        XCTAssertFalse(displayText.contains("/Users"))
        XCTAssertFalse(displayText.contains("SecretProject"))
        XCTAssertFalse(displayText.contains("sk-test-secret"))
    }

    func testCookedShareCardContentUsesCurrentQuestGapWithoutPrivateDetails() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state.plan[0].gap = .networking

        let content = try XCTUnwrap(CookedShareCardContent(state: state))

        XCTAssertEqual(content.publicGapText, "Main gap: networking")
    }

    func testCookedShareCardContentRejectsBareDomainsAndSlashHeavyTargetRoles() throws {
        let privateGoal = CareerGoal(
            currentStatus: .student,
            targetRole: "private.example.com/linkedin.com/in/langqi/recruiting-notes",
            timeline: "30 days",
            background: "",
            existingProof: "",
            confidence: 3,
            biggestBlocker: ""
        )
        let state = OpenLARPEngine.confirmGoal(privateGoal)

        let content = try XCTUnwrap(CookedShareCardContent(state: state))
        let displayText = content.displayText + " " + content.shareText

        XCTAssertEqual(content.targetRole, "my career goal")
        XCTAssertFalse(displayText.contains("private.example.com"))
        XCTAssertFalse(displayText.contains("linkedin.com"))
        XCTAssertFalse(displayText.contains("recruiting-notes"))
    }

    func testCookedShareCardContentDoesNotMutateSharingPreference() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state.userProfile?.privacy.shareWins = false

        _ = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))

        XCTAssertEqual(state.userProfile?.privacy.shareWins, false)
    }

    func testStartingFirstQuestFromDiagnosticResultUsesExistingQuestState() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        let content = try XCTUnwrap(CookedDiagnosticResultContent(state: state))

        state = try OpenLARPEngine.startCurrentQuest(in: state)

        XCTAssertEqual(state.currentQuest?.id, content.firstQuestID)
        XCTAssertEqual(state.currentQuest?.status, .inProgress)
    }

    func testStrongProofAwardsFullXPStreakReadinessAndBadges() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let proof = ProofSubmission(
            kind: .proof,
            text: "I built a small SwiftUI screen for the target app, tested the empty and completed states, wrote notes about the tradeoffs, and saved the code in a repo.",
            link: "https://example.com/proof",
            submittedAt: Date(timeIntervalSince1970: 1_800)
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.xpEarned, 120)
        XCTAssertEqual(state.progress.xp, 120)
        XCTAssertEqual(state.progress.streakCount, 1)
        XCTAssertEqual(state.progress.proofCount, 1)
        XCTAssertEqual(state.progress.completedQuestCount, 1)
        XCTAssertEqual(state.progress.readiness.proofStrength, 49)
        XCTAssertTrue(state.progress.badges.contains(.firstProof))
        XCTAssertEqual(state.plan[0].status, .completed)
        XCTAssertEqual(state.plan[1].status, .locked)
        XCTAssertEqual(state.dailyCadence.nextQuestID, state.plan[1].id)
    }

    func testClaimLocksNextQuestUntilNextLocalDay() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        var state = OpenLARPEngine.confirmGoal(goal, now: claimTime)
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: claimTime)

        let proof = ProofSubmission(
            kind: .proof,
            text: "I mapped repeated iOS internship requirements, chose one proof-building path, and saved notes that connect the work to a target role.",
            link: "https://example.com/requirements",
            submittedAt: claimTime
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)

        state = try OpenLARPEngine.claim(
            result,
            proof: proof,
            in: state,
            now: claimTime,
            calendar: testCalendar
        )

        XCTAssertEqual(state.plan[0].status, .completed)
        XCTAssertEqual(state.plan[1].status, .locked)
        XCTAssertNil(state.currentQuest)
        XCTAssertEqual(state.dailyCadence.lastCompletedQuestID, state.plan[0].id)
        XCTAssertEqual(state.dailyCadence.completedQuestTitle, state.plan[0].title)
        XCTAssertEqual(state.dailyCadence.xpEarned, result.xpEarned)
        XCTAssertEqual(state.dailyCadence.streakCountAfterCompletion, 1)
        XCTAssertEqual(state.dailyCadence.nextQuestID, state.plan[1].id)
    }

    func testRefreshDailyAvailabilityKeepsNextQuestLockedOnSameLocalDay() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let sameDayLater = localDate(year: 2026, month: 5, day: 31, hour: 22)
        var state = try completedFirstQuestState(claimTime: claimTime)

        state = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: sameDayLater,
            calendar: testCalendar
        )

        XCTAssertEqual(state.plan[1].status, .locked)
        XCTAssertNil(state.currentQuest)
        XCTAssertEqual(state.dailyCadence.nextQuestID, state.plan[1].id)
    }

    func testRefreshDailyAvailabilityUnlocksNextQuestOnNextLocalDay() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let nextDay = localDate(year: 2026, month: 6, day: 1, hour: 8)
        var state = try completedFirstQuestState(claimTime: claimTime)

        state = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: nextDay,
            calendar: testCalendar
        )

        XCTAssertEqual(state.plan[1].status, .available)
        XCTAssertEqual(state.currentQuest?.id, state.plan[1].id)
        XCTAssertEqual(state.dailyCadence, .empty)
    }

    func testRefreshDailyAvailabilityDoesNotShowMissedDayOnSameLocalDay() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let sameDayLater = localDate(year: 2026, month: 5, day: 31, hour: 22)
        let state = try completedFirstQuestState(claimTime: claimTime)

        let refreshed = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: sameDayLater,
            calendar: testCalendar
        )

        XCTAssertNil(refreshed.missedDayRecovery.startedAt)
        XCTAssertEqual(refreshed.progress.streakCount, 1)
        XCTAssertNil(MissedDayRecoveryContent(state: refreshed))
    }

    func testRefreshDailyAvailabilityUnlocksNextDayWithoutMissedDayWarning() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let nextDay = localDate(year: 2026, month: 6, day: 1, hour: 8)
        let state = try completedFirstQuestState(claimTime: claimTime)

        let refreshed = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: nextDay,
            calendar: testCalendar
        )

        XCTAssertNil(refreshed.missedDayRecovery.startedAt)
        XCTAssertEqual(refreshed.progress.streakCount, 1)
        XCTAssertEqual(refreshed.currentQuest?.id, refreshed.plan[1].id)
    }

    func testRefreshDailyAvailabilityShowsRecoveryAfterSkippingAvailableQuestDay() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let skippedReturn = localDate(year: 2026, month: 6, day: 2, hour: 8)
        let state = try completedFirstQuestState(claimTime: claimTime)

        let refreshed = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: skippedReturn,
            calendar: testCalendar
        )

        XCTAssertEqual(refreshed.plan[1].status, .available)
        XCTAssertEqual(refreshed.progress.streakCount, 0)
        XCTAssertEqual(refreshed.missedDayRecovery.missedDayCount, 1)
        XCTAssertEqual(refreshed.missedDayRecovery.nextQuestID, refreshed.plan[1].id)
    }

    func testMissedDayRecoveryContentExplainsStreakAndNextQuest() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let skippedReturn = localDate(year: 2026, month: 6, day: 3, hour: 8)
        let state = OpenLARPEngine.refreshDailyAvailability(
            in: try completedFirstQuestState(claimTime: claimTime),
            now: skippedReturn,
            calendar: testCalendar
        )

        let content = try XCTUnwrap(MissedDayRecoveryContent(state: state))

        XCTAssertEqual(content.title, "Streak reset, track still alive")
        XCTAssertEqual(content.missedDaysText, "You missed 2 quest days.")
        XCTAssertEqual(content.bodyText, "No shame. Your XP and proof receipts are still here. Start the next quest to rebuild from today.")
        XCTAssertEqual(content.previousStreakText, "Previous streak: 1 day")
        XCTAssertEqual(content.activeStreakText, "Active streak: 0 days")
        XCTAssertEqual(content.nextQuestTitle, state.plan[1].title)
        XCTAssertEqual(content.nextQuestObjectiveText, state.plan[1].purpose)
        XCTAssertEqual(content.primaryActionTitle, "Continue Next Quest")
    }

    func testStartingCurrentQuestClearsMissedDayRecovery() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let skippedReturn = localDate(year: 2026, month: 6, day: 2, hour: 8)
        var state = OpenLARPEngine.refreshDailyAvailability(
            in: try completedFirstQuestState(claimTime: claimTime),
            now: skippedReturn,
            calendar: testCalendar
        )

        state = try OpenLARPEngine.startCurrentQuest(in: state, now: skippedReturn)

        XCTAssertEqual(state.plan[1].status, .inProgress)
        XCTAssertEqual(state.missedDayRecovery, .empty)
        XCTAssertEqual(state.progress.streakCount, 0)
    }

    func testSkipAvailableQuestMarksSkippedLocksNextAndResetsStreak() throws {
        let skipTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        var state = OpenLARPEngine.confirmGoal(goal, now: skipTime)
        state.progress.streakCount = 3

        state = try OpenLARPEngine.skipCurrentQuest(
            in: state,
            now: skipTime,
            calendar: testCalendar
        )

        XCTAssertEqual(state.plan[0].status, .skipped)
        XCTAssertEqual(state.plan[1].status, .locked)
        XCTAssertNil(state.currentQuest)
        XCTAssertEqual(state.progress.streakCount, 0)
        XCTAssertEqual(state.skippedToday.skippedQuestID, state.plan[0].id)
        XCTAssertEqual(state.skippedToday.skippedQuestTitle, state.plan[0].title)
        XCTAssertEqual(state.skippedToday.previousStreakCount, 3)
        XCTAssertEqual(state.skippedToday.nextQuestID, state.plan[1].id)
        XCTAssertEqual(state.dailyCadence, .empty)
        XCTAssertEqual(state.missedDayRecovery, .empty)
    }

    @MainActor
    func testStoreSkipInProgressQuestClearsPendingProofAndQualityResult() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let skipTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore,
            now: { skipTime },
            calendar: testCalendar
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let attachment = try store.saveProofImage(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            originalFileName: "proof.png"
        )
        await store.checkProof(
            kind: .proof,
            text: "I mapped repeated iOS internship requirements, chose one proof-building path, and saved notes that connect the work to a target role.",
            link: "https://example.com/requirements",
            attachments: [attachment]
        )

        XCTAssertNotNil(store.pendingProof)
        XCTAssertNotNil(store.pendingQualityResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))

        store.skipCurrentQuest()

        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.pendingQualityResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))
        XCTAssertEqual(store.state.plan[0].status, .skipped)
        XCTAssertEqual(store.state.plan[1].status, .locked)
        XCTAssertNil(store.state.currentQuest)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.skippedToday.skippedQuestID, store.state.plan[0].id)
        XCTAssertNil(reloaded.currentQuest)
    }

    func testRefreshDailyAvailabilityKeepsSkippedStateOnSameLocalDay() throws {
        let skipTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let sameDayLater = localDate(year: 2026, month: 5, day: 31, hour: 21)
        var state = OpenLARPEngine.confirmGoal(goal, now: skipTime)
        state = try OpenLARPEngine.skipCurrentQuest(
            in: state,
            now: skipTime,
            calendar: testCalendar
        )

        let refreshed = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: sameDayLater,
            calendar: testCalendar
        )

        XCTAssertEqual(refreshed.plan[0].status, .skipped)
        XCTAssertEqual(refreshed.plan[1].status, .locked)
        XCTAssertEqual(refreshed.skippedToday.skippedQuestID, state.plan[0].id)
        XCTAssertNil(refreshed.currentQuest)
        XCTAssertNotNil(SkippedTodayContent(
            state: refreshed,
            now: sameDayLater,
            calendar: testCalendar
        ))
    }

    func testRefreshDailyAvailabilityUnlocksNextQuestAfterSkippedTodayClears() throws {
        let skipTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let nextDay = localDate(year: 2026, month: 6, day: 1, hour: 8)
        var state = OpenLARPEngine.confirmGoal(goal, now: skipTime)
        state = try OpenLARPEngine.skipCurrentQuest(
            in: state,
            now: skipTime,
            calendar: testCalendar
        )

        let refreshed = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: nextDay,
            calendar: testCalendar
        )

        XCTAssertEqual(refreshed.plan[0].status, .skipped)
        XCTAssertEqual(refreshed.plan[1].status, .available)
        XCTAssertEqual(refreshed.currentQuest?.id, refreshed.plan[1].id)
        XCTAssertEqual(refreshed.skippedToday, .empty)
        XCTAssertEqual(refreshed.missedDayRecovery, .empty)
    }

    func testSkipPreservesPriorProgressProofBadgesCompletedQuestsAndReadiness() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let nextDay = localDate(year: 2026, month: 6, day: 1, hour: 8)
        var state = OpenLARPEngine.refreshDailyAvailability(
            in: try completedFirstQuestState(claimTime: claimTime),
            now: nextDay,
            calendar: testCalendar
        )

        let preservedXP = state.progress.xp
        let preservedProofCount = state.progress.proofCount
        let preservedCompletedQuestCount = state.progress.completedQuestCount
        let preservedBadges = state.progress.badges
        let preservedReadiness = state.progress.readiness
        let preservedProofs = state.progress.recentProof
        let previousStreak = state.progress.streakCount

        state = try OpenLARPEngine.skipCurrentQuest(
            in: state,
            now: nextDay,
            calendar: testCalendar
        )

        XCTAssertEqual(state.progress.xp, preservedXP)
        XCTAssertEqual(state.progress.proofCount, preservedProofCount)
        XCTAssertEqual(state.progress.completedQuestCount, preservedCompletedQuestCount)
        XCTAssertEqual(state.progress.badges, preservedBadges)
        XCTAssertEqual(state.progress.readiness, preservedReadiness)
        XCTAssertEqual(state.progress.recentProof, preservedProofs)
        XCTAssertEqual(state.progress.streakCount, 0)
        XCTAssertEqual(state.skippedToday.previousStreakCount, previousStreak)
    }

    func testSkipFinalQuestShowsNoNextQuestState() throws {
        let skipTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let nextDay = localDate(year: 2026, month: 6, day: 1, hour: 8)
        let finalQuest = Quest(
            id: UUID(uuidString: "FAFAFAFA-FAFA-FAFA-FAFA-FAFAFAFAFAFA")!,
            day: 7,
            title: "Run the weekly less-cooked check",
            purpose: "Review what changed this week.",
            proofRequired: "Write what proof improved.",
            xpReward: 160,
            status: .available
        )
        var state = OpenLARPState(
            goal: goal,
            diagnostic: nil,
            plan: [finalQuest],
            progress: .empty,
            updatedAt: skipTime
        )

        state = try OpenLARPEngine.skipCurrentQuest(
            in: state,
            now: skipTime,
            calendar: testCalendar
        )

        let content = try XCTUnwrap(SkippedTodayContent(
            state: state,
            now: skipTime,
            calendar: testCalendar
        ))

        XCTAssertEqual(state.plan[0].status, .skipped)
        XCTAssertNil(state.skippedToday.nextQuestID)
        XCTAssertNil(content.nextQuestTitle)
        XCTAssertEqual(content.nextQuestStatusText, "Track complete")
        XCTAssertEqual(content.unlockMessage, "You skipped the final local quest. The track is finished for now.")

        let refreshed = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: nextDay,
            calendar: testCalendar
        )
        XCTAssertEqual(refreshed.skippedToday, .empty)
        XCTAssertEqual(refreshed.plan[0].status, .skipped)
        XCTAssertNil(refreshed.currentQuest)
    }

    func testPersistenceRoundTripKeepsMissedDayRecoveryState() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let skippedReturn = localDate(year: 2026, month: 6, day: 2, hour: 8)
        let state = OpenLARPEngine.refreshDailyAvailability(
            in: try completedFirstQuestState(claimTime: claimTime),
            now: skippedReturn,
            calendar: testCalendar
        )

        try persistence.save(state)
        let reloaded = try persistence.load()

        XCTAssertEqual(reloaded.missedDayRecovery.missedDayCount, 1)
        XCTAssertEqual(reloaded.missedDayRecovery.nextQuestID, reloaded.plan[1].id)
        XCTAssertEqual(reloaded.progress.streakCount, 0)
        XCTAssertEqual(reloaded.currentQuest?.id, reloaded.plan[1].id)
    }

    func testTodayCompletionContentShowsDoneStateAndNextQuestPreview() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let sameDayLater = localDate(year: 2026, month: 5, day: 31, hour: 18)
        let state = try completedFirstQuestState(claimTime: claimTime)

        let content = try XCTUnwrap(TodayCompletionContent(
            state: state,
            now: sameDayLater,
            calendar: testCalendar
        ))

        XCTAssertEqual(content.completedQuestTitle, state.plan[0].title)
        XCTAssertEqual(content.resultSummary, "Strong proof")
        XCTAssertEqual(content.xpText, "+120 XP")
        XCTAssertEqual(content.streakText, "1-day streak")
        XCTAssertEqual(content.proofRecord?.questID, state.plan[0].id)
        XCTAssertEqual(content.nextQuestTitle, state.plan[1].title)
        XCTAssertEqual(content.nextQuestStatusText, "Locked until tomorrow")
        XCTAssertEqual(content.unlockMessage, "Your next quest unlocks tomorrow.")
    }

    func testTodayCompletionContentShowsFinishedTrackWhenNoNextQuestExists() throws {
        let claimTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let finalQuest = Quest(
            id: UUID(uuidString: "FAFAFAFA-FAFA-FAFA-FAFA-FAFAFAFAFAFA")!,
            day: 7,
            title: "Run the weekly less-cooked check",
            purpose: "Review what changed this week.",
            proofRequired: "Write what proof improved.",
            xpReward: 160,
            status: .available
        )
        var state = OpenLARPState(
            goal: goal,
            diagnostic: nil,
            plan: [finalQuest],
            progress: .empty,
            updatedAt: claimTime
        )
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: claimTime)
        let proof = ProofSubmission(
            kind: .proof,
            text: "I reviewed the week, named the proof I created, and wrote the next honest gap to shrink.",
            submittedAt: claimTime
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(
            result,
            proof: proof,
            in: state,
            now: claimTime,
            calendar: testCalendar
        )

        let content = try XCTUnwrap(TodayCompletionContent(
            state: state,
            now: claimTime,
            calendar: testCalendar
        ))

        XCTAssertEqual(content.completedQuestTitle, finalQuest.title)
        XCTAssertNil(content.nextQuestTitle)
        XCTAssertEqual(content.nextQuestStatusText, "Track complete")
        XCTAssertEqual(content.unlockMessage, "You finished the local seven-day track.")
    }

    func testSelfReportAwardsPartialCreditWithoutPretendingProofIsStrong() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let proof = ProofSubmission(
            kind: .selfReport,
            text: "I looked at two job posts and wrote down a few repeated skills.",
            link: "",
            submittedAt: Date(timeIntervalSince1970: 2_400)
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        XCTAssertFalse(result.isAccepted)
        XCTAssertEqual(result.xpEarned, 45)
        XCTAssertEqual(result.readinessDelta, 2)
        XCTAssertEqual(state.progress.xp, 45)
        XCTAssertEqual(state.progress.streakCount, 1)
        XCTAssertEqual(state.progress.proofCount, 1)
        XCTAssertEqual(state.progress.readiness.proofStrength, 44)
        XCTAssertEqual(state.progress.recentProof.first?.quality?.label, "Needs stronger proof")
    }

    func testImageAttachmentProofAwardsFullCreditWithoutTextOrLink() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let attachment = ProofAttachment(
            fileName: "proof-image.png",
            originalFileName: "whiteboard.png",
            contentType: "image/png",
            byteCount: 128,
            createdAt: Date(timeIntervalSince1970: 2_800)
        )
        let proof = ProofSubmission(
            kind: .proof,
            text: "",
            link: "",
            attachments: [attachment],
            submittedAt: Date(timeIntervalSince1970: 2_900)
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.xpEarned, 120)
        XCTAssertEqual(result.label, "Strong proof")
        XCTAssertEqual(state.progress.xp, 120)
        XCTAssertEqual(state.progress.proofCount, 1)
        XCTAssertEqual(state.progress.recentProof.first?.attachments, [attachment])
    }

    func testPersistenceRoundTripKeepsProofAttachmentMetadata() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)

        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let attachment = ProofAttachment(
            fileName: "proof-image.jpg",
            originalFileName: "screenshot.jpg",
            contentType: "image/jpeg",
            byteCount: 256,
            createdAt: Date(timeIntervalSince1970: 3_200)
        )
        let proof = ProofSubmission(
            kind: .proof,
            text: "This screenshot shows the requirement map I made.",
            link: "",
            attachments: [attachment],
            submittedAt: Date(timeIntervalSince1970: 3_300)
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        try persistence.save(state)
        let reloaded = try persistence.load()

        XCTAssertEqual(reloaded.progress.recentProof.first?.attachments, [attachment])
        XCTAssertEqual(reloaded.progress.recentProof.first?.attachmentSummary, "1 image")
    }

    func testAttachmentStoreWritesAndDeletesImageData() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPAttachmentStore(directory: directory)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        let attachment = try store.saveImage(
            data: imageData,
            contentType: "image/png",
            originalFileName: "proof.png",
            now: Date(timeIntervalSince1970: 3_600)
        )

        XCTAssertEqual(attachment.contentType, "image/png")
        XCTAssertEqual(attachment.byteCount, imageData.count)
        XCTAssertEqual(try store.data(for: attachment), imageData)

        try store.delete(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: attachment).path))
    }

    func testAttachmentStoreRejectsUploadIntentOutsideProofAttachmentDirectory() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let privateFileData = Data("do-not-upload".utf8)
        let outsideFileName = "\(directory.lastPathComponent)-private-file.txt"
        let outsideFileURL = directory
            .deletingLastPathComponent()
            .appendingPathComponent(outsideFileName)
        try privateFileData.write(to: outsideFileURL)
        defer {
            try? FileManager.default.removeItem(at: outsideFileURL)
        }
        let store = OpenLARPAttachmentStore(directory: directory)
        let proofID = UUID(uuidString: "B1B1B1B1-B1B1-B1B1-B1B1-B1B1B1B1B1B1")!
        let attachment = ProofAttachment(
            id: UUID(uuidString: "B2B2B2B2-B2B2-B2B2-B2B2-B2B2B2B2B2B2")!,
            fileName: outsideFileName,
            originalFileName: outsideFileName,
            contentType: "text/plain",
            byteCount: privateFileData.count,
            createdAt: Date(timeIntervalSince1970: 3_700),
            localRelativePath: "../\(outsideFileName)"
        )
        let cloudAttachment = CloudProofAttachmentDocument(
            attachment: attachment,
            ownerUserID: "firebase_uid_attachment_escape",
            proofID: proofID
        )
        let uploadIntent = CareerGraphSyncUploadIntent(
            proofID: proofID.uuidString,
            attachment: cloudAttachment
        )

        do {
            _ = try await store.data(for: uploadIntent)
            XCTFail("Attachment uploads must not read files outside the proof attachments directory.")
        } catch let error as CareerGraphProofAttachmentDataError {
            XCTAssertEqual(error, .unsafeLocalPath)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDiscardPendingQualityResultDeletesPendingProofAttachments() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let attachment = try store.saveProofImage(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            originalFileName: "draft-proof.png"
        )

        await store.checkProof(kind: .proof, text: "", link: "", attachments: [attachment])

        XCTAssertNotNil(store.pendingProof)
        XCTAssertNotNil(store.pendingQualityResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))

        store.discardPendingQualityResult()

        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.pendingQualityResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))

        let reloaded = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertNil(reloaded.pendingProof)
        XCTAssertNil(reloaded.pendingQualityResult)
        XCTAssertNil(reloaded.state.proofDraft)
        XCTAssertNil(reloaded.state.proofDraftQualityResult)
    }

    @MainActor
    func testRecheckingSamePendingAttachmentKeepsImageFile() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let attachment = try store.saveProofImage(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            originalFileName: "same-draft-proof.png"
        )

        await store.checkProof(kind: .proof, text: "", link: "", attachments: [attachment])
        await store.checkProof(kind: .proof, text: "Adding a short note before checking again.", link: "", attachments: [attachment])

        XCTAssertNotNil(store.pendingProof)
        XCTAssertNotNil(store.pendingQualityResult)
        XCTAssertEqual(store.pendingProof?.attachments, [attachment])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))
    }

    func testProofDetailContentTrimsProofMetadataAndKeepsQualityFields() {
        let proof = ProofRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            questID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            questTitle: "Build a target-role proof map",
            kind: .proof,
            text: "  I made a requirements map from three internship posts.  ",
            link: " https://example.com/proof-map ",
            submittedAt: Date(timeIntervalSince1970: 4_200),
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "This includes a concrete artifact.",
                improvement: "Tie the artifact to one target-role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )

        let content = ProofDetailContent(proof: proof)

        XCTAssertEqual(content.questTitle, "Build a target-role proof map")
        XCTAssertEqual(content.proofType, "Proof")
        XCTAssertEqual(content.submittedAt, Date(timeIntervalSince1970: 4_200))
        XCTAssertEqual(content.qualityLabel, "Strong proof")
        XCTAssertEqual(content.xpText, "120 XP")
        XCTAssertEqual(content.reason, "This includes a concrete artifact.")
        XCTAssertEqual(content.improvement, "Tie the artifact to one target-role requirement.")
        XCTAssertEqual(content.proofText, "I made a requirements map from three internship posts.")
        XCTAssertEqual(content.proofLinkText, "https://example.com/proof-map")
        XCTAssertEqual(content.proofURL, URL(string: "https://example.com/proof-map"))
    }

    func testProofDetailContentUsesFallbacksWhenQualityIsMissing() {
        let proof = ProofRecord(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            questID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            questTitle: "Reflect on outreach",
            kind: .selfReport,
            text: "   ",
            link: "not a url",
            submittedAt: Date(timeIntervalSince1970: 4_800),
            quality: nil
        )

        let content = ProofDetailContent(proof: proof)

        XCTAssertEqual(content.qualityLabel, "Self-report")
        XCTAssertEqual(content.xpText, "0 XP")
        XCTAssertEqual(content.reason, "No quality check is attached to this receipt yet.")
        XCTAssertEqual(content.improvement, "Submit stronger proof on the next quest to get sharper feedback.")
        XCTAssertNil(content.proofText)
        XCTAssertEqual(content.proofLinkText, "not a url")
        XCTAssertNil(content.proofURL)
    }

    func testProofArchiveContentSortsReceiptsNewestFirstAndReportsCount() {
        let oldProof = proofRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            questTitle: "Older proof",
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newestProof = proofRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            questTitle: "Newest proof",
            submittedAt: Date(timeIntervalSince1970: 3_000)
        )
        let middleProof = proofRecord(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            questTitle: "Middle proof",
            submittedAt: Date(timeIntervalSince1970: 2_000)
        )

        let content = ProofArchiveContent(proofs: [oldProof, newestProof, middleProof])

        XCTAssertEqual(content.receipts.map(\.questTitle), ["Newest proof", "Middle proof", "Older proof"])
        XCTAssertEqual(content.countText, "3 proof receipts")
        XCTAssertEqual(content.emptyMessage, "Proof receipts appear here after you submit quest proof.")
    }

    func testClaimKeepsAllProofReceiptsForArchiveHistory() throws {
        let questIDs = (1...13).map { index in
            UUID(uuidString: String(format: "AAAAAAAA-AAAA-AAAA-AAAA-%012d", index))!
        }
        var state = OpenLARPState(
            goal: goal,
            diagnostic: nil,
            plan: questIDs.enumerated().map { index, id in
                Quest(
                    id: id,
                    day: index + 1,
                    title: "Quest \(index + 1)",
                    purpose: "Create real proof \(index + 1).",
                    proofRequired: "Submit proof.",
                    xpReward: 100,
                    status: .available
                )
            },
            progress: .empty,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        for index in 1...13 {
            let claimTime = localDate(year: 2026, month: 5, day: index, hour: 9)
            let proof = ProofSubmission(
                kind: .proof,
                text: "I created useful proof item number \(index) with enough detail to count as meaningful career progress.",
                submittedAt: claimTime
            )
            let result = try OpenLARPEngine.checkProof(proof, in: state)
            state = try OpenLARPEngine.claim(
                result,
                proof: proof,
                in: state,
                now: claimTime,
                calendar: testCalendar
            )

            if index < 13 {
                state = OpenLARPEngine.refreshDailyAvailability(
                    in: state,
                    now: localDate(year: 2026, month: 5, day: index + 1, hour: 8),
                    calendar: testCalendar
                )
            }
        }

        let content = ProofArchiveContent(proofs: state.progress.recentProof)

        XCTAssertEqual(state.progress.recentProof.count, 13)
        XCTAssertEqual(content.receipts.first?.questTitle, "Quest 13")
        XCTAssertEqual(content.receipts.last?.questTitle, "Quest 1")
    }

    func testCompletedQuestDetailContentMatchesSavedProofByQuestID() {
        let questID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let otherQuestID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let quest = Quest(
            id: questID,
            day: 2,
            title: "Create one tiny proof artifact",
            purpose: "A small real artifact beats a big unsupported claim.",
            timeEstimateMinutes: 30,
            difficulty: "Starter",
            gap: .proofStrength,
            proofRequired: "Add a link, screenshot, or notes showing what you made.",
            xpReward: 130,
            steps: ["Make the first version.", "Write what it proves honestly."],
            status: .completed
        )
        let matchingProof = proofRecord(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            questID: questID,
            questTitle: quest.title,
            submittedAt: Date(timeIntervalSince1970: 5_200)
        )
        let unrelatedProof = proofRecord(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            questID: otherQuestID,
            questTitle: "Different quest",
            submittedAt: Date(timeIntervalSince1970: 5_600)
        )

        let content = CompletedQuestDetailContent(
            quest: quest,
            proofs: [unrelatedProof, matchingProof]
        )

        XCTAssertEqual(content.dayText, "Day 2")
        XCTAssertEqual(content.statusText, "Complete")
        XCTAssertEqual(content.title, "Create one tiny proof artifact")
        XCTAssertEqual(content.objectiveText, "A small real artifact beats a big unsupported claim.")
        XCTAssertEqual(content.stepTexts, ["Make the first version.", "Write what it proves honestly."])
        XCTAssertEqual(content.proofRequiredText, "Add a link, screenshot, or notes showing what you made.")
        XCTAssertEqual(content.gapText, "Proof strength")
        XCTAssertEqual(content.xpRewardText, "130 XP")
        XCTAssertEqual(content.savedProof, matchingProof)
        XCTAssertEqual(content.noProofMessage, "No proof receipt saved for this completed quest.")
    }

    func testCompletedQuestDetailContentShowsFallbackWhenNoProofReceiptExists() {
        let quest = Quest(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            day: 4,
            title: "Explain your proof in five bullets",
            purpose: "If you cannot explain the work, it will not help in interviews.",
            timeEstimateMinutes: 25,
            difficulty: "Balanced",
            gap: .confidence,
            proofRequired: "Paste the five bullets.",
            xpReward: 110,
            status: .completed
        )

        let content = CompletedQuestDetailContent(quest: quest, proofs: [])

        XCTAssertNil(content.savedProof)
        XCTAssertEqual(content.noProofMessage, "No proof receipt saved for this completed quest.")
        XCTAssertEqual(content.gapText, "Confidence")
        XCTAssertEqual(content.xpRewardText, "110 XP")
    }

    func testQuestPreviewContentShowsAvailableQuestMetadataAndStartCTA() {
        let quest = Quest(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            day: 2,
            title: "Create one tiny proof artifact",
            purpose: "A small real artifact beats a big unsupported claim.",
            timeEstimateMinutes: 30,
            difficulty: "Starter",
            gap: .proofStrength,
            proofRequired: "Add a link, screenshot, or notes showing what you made.",
            xpReward: 130,
            steps: ["Make the first version.", "Write what it proves honestly."],
            status: .available
        )

        let content = QuestPreviewContent(quest: quest)

        XCTAssertEqual(content.dayText, "Day 2")
        XCTAssertEqual(content.statusText, "Today")
        XCTAssertEqual(content.title, "Create one tiny proof artifact")
        XCTAssertEqual(content.objectiveText, "A small real artifact beats a big unsupported claim.")
        XCTAssertEqual(content.stepTexts, ["Make the first version.", "Write what it proves honestly."])
        XCTAssertEqual(content.proofRequiredText, "Add a link, screenshot, or notes showing what you made.")
        XCTAssertEqual(content.gapText, "Proof strength")
        XCTAssertEqual(content.xpRewardText, "130 XP")
        XCTAssertEqual(content.timeEstimateText, "30 min")
        XCTAssertEqual(content.difficultyText, "Starter")
        XCTAssertEqual(content.todayCTATitle, "Go to Today to Start")
        XCTAssertTrue(content.canOpenToday)
    }

    func testQuestPreviewContentUsesContinueCTAForInProgressQuest() {
        let quest = Quest(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!,
            day: 1,
            title: "Map 3 real requirements",
            purpose: "Know what proof matters before building it.",
            timeEstimateMinutes: 25,
            difficulty: "Starter",
            gap: .targetClarity,
            proofRequired: "Paste requirement notes.",
            xpReward: 120,
            steps: ["Find two postings.", "Pick repeated requirements."],
            status: .inProgress
        )

        let content = QuestPreviewContent(quest: quest)

        XCTAssertEqual(content.statusText, "In progress")
        XCTAssertEqual(content.todayCTATitle, "Go to Today to Continue")
        XCTAssertTrue(content.canOpenToday)
    }

    func testQuestPreviewContentDoesNotExposeTodayCTAForLockedQuest() {
        let quest = Quest(
            id: UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!,
            day: 5,
            title: "Find one low-friction networking target",
            purpose: "Networking gets easier when the ask is specific and tied to real work.",
            timeEstimateMinutes: 20,
            difficulty: "Spicy",
            gap: .networking,
            proofRequired: "Paste the person's role and why they are relevant.",
            xpReward: 120,
            status: .locked
        )

        let content = QuestPreviewContent(quest: quest)

        XCTAssertEqual(content.statusText, "Locked")
        XCTAssertNil(content.todayCTATitle)
        XCTAssertFalse(content.canOpenToday)
    }

    func testPersistenceRoundTripKeepsGoalProgressAndQuestStatuses() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)

        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let proof = ProofSubmission(
            kind: .proof,
            text: "I created a target-role requirements map with six repeated skills, picked one proof-building app idea, and wrote the first implementation checklist.",
            link: "https://example.com/checklist",
            submittedAt: Date(timeIntervalSince1970: 3_000)
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        try persistence.save(state)
        let reloaded = try persistence.load()

        XCTAssertEqual(reloaded.goal, goal)
        XCTAssertEqual(reloaded.progress.xp, 120)
        XCTAssertEqual(reloaded.progress.streakCount, 1)
        XCTAssertEqual(reloaded.plan[0].status, .completed)
        XCTAssertEqual(reloaded.plan[1].status, .locked)
        XCTAssertNil(reloaded.currentQuest)
        XCTAssertEqual(reloaded.dailyCadence.nextQuestID, reloaded.plan[1].id)
        XCTAssertEqual(reloaded.progress.recentProof.count, 1)
        XCTAssertEqual(reloaded.progress.recentProof.first?.text, proof.text)
    }

    func testGoalSetupCreatesAccountReadyProfileTargetRoleAndAgentState() {
        let state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 10_000))

        XCTAssertEqual(state.userProfile?.segment, .student)
        XCTAssertEqual(state.userProfile?.displayName, "Early-career candidate")
        XCTAssertEqual(state.userProfile?.privacy.memoryMode, .localOnly)
        XCTAssertEqual(state.userProfile?.privacy.shareWins, false)
        XCTAssertEqual(state.targetRoles.first?.title, "iOS engineering internship")
        XCTAssertEqual(state.targetRoles.first?.seniority, .internship)
        XCTAssertEqual(state.targetRoles.first?.timeline, "30 days")
        XCTAssertEqual(state.progress.readiness.skillProof, 38)
        XCTAssertEqual(state.progress.readiness.networkStrength, 31)
        XCTAssertEqual(state.progress.readinessHistory.count, 1)
        XCTAssertEqual(state.progress.readinessHistory.first?.reason, "Initial Am I Cooked baseline")
        XCTAssertEqual(state.agentBrief.title, "Career agent brief")
        XCTAssertEqual(state.agentBrief.opportunities.count, 3)
        XCTAssertEqual(state.agentBrief.activities.first?.status, .completed)
    }

    func testClaimAddsProofToReadinessHistoryAndRefreshesAgentBrief() throws {
        let claimTime = Date(timeIntervalSince1970: 11_000)
        var state = OpenLARPEngine.confirmGoal(goal, now: claimTime)
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: claimTime)
        let proof = ProofSubmission(
            kind: .proof,
            text: "I mapped three iOS internship requirements, grouped the repeated SwiftUI and testing signals, and saved the target-role proof plan.",
            link: "https://example.com/ios-plan",
            submittedAt: claimTime
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(
            result,
            proof: proof,
            in: state,
            now: claimTime,
            calendar: testCalendar
        )

        XCTAssertEqual(state.progress.readinessHistory.count, 2)
        XCTAssertEqual(state.progress.readinessHistory.last?.relatedProofID, proof.id)
        XCTAssertEqual(state.progress.readinessHistory.last?.overall, state.progress.readiness.overall)
        XCTAssertEqual(state.agentBrief.activities.first?.type, .proofEvaluation)
        XCTAssertEqual(state.agentBrief.activities.first?.status, .completed)
        XCTAssertTrue(state.agentBrief.summary.contains("1 proof receipt"))
    }

    func testOpportunityRankingOrdersByFitUrgencyProofGapAndImpact() {
        let targetRole = TargetRole(
            title: "AI product manager internship",
            seniority: .internship,
            roleFamily: .product,
            timeline: "21 days",
            keywords: ["AI", "product", "prototype"]
        )
        let opportunities = [
            OpportunityCard(
                type: .course,
                title: "Generic resume webinar",
                sourceName: "Career Center",
                fitScore: 50,
                urgencyScore: 20,
                missingProofScore: 20,
                impactScore: 30,
                whyItMatters: "General polish.",
                missingProof: "Resume credibility",
                recommendedAction: "Watch later."
            ),
            OpportunityCard(
                type: .project,
                title: "Ship an AI product teardown",
                sourceName: "OpenLARP Agent",
                fitScore: 92,
                urgencyScore: 72,
                missingProofScore: 88,
                impactScore: 90,
                whyItMatters: "Creates proof for AI product judgment.",
                missingProof: "Product proof",
                recommendedAction: "Build the one-page teardown."
            ),
            OpportunityCard(
                type: .networking,
                title: "Message a PM intern alum",
                sourceName: "Approved network scan",
                fitScore: 82,
                urgencyScore: 86,
                missingProofScore: 60,
                impactScore: 76,
                whyItMatters: "Near-term conversation with a relevant peer.",
                missingProof: "Network signal",
                recommendedAction: "Send one honest question."
            )
        ]

        let ranked = LocalOpportunityRankingService().rank(opportunities, for: targetRole)

        XCTAssertEqual(ranked.map(\.title), [
            "Ship an AI product teardown",
            "Message a PM intern alum",
            "Generic resume webinar"
        ])
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 3])
        XCTAssertGreaterThan(ranked[0].compositeScore, ranked[1].compositeScore)
    }

    @MainActor
    func testMockAgentServiceProducesBackendReadyBriefWithoutClientLLMCalls() async throws {
        let state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 12_000))
        let service: CareerAgentBriefServicing = MockCareerAgentService()

        let brief = try await service.generateBrief(for: state)

        XCTAssertEqual(brief.providerRoute, .localMock)
        XCTAssertEqual(brief.opportunities.map(\.rank), [1, 2, 3])
        XCTAssertTrue(brief.activities.contains { $0.type == .opportunityScan && $0.status == .completed })
        XCTAssertTrue(brief.nextSteps.contains { $0.title == "Do today's proof quest" })
    }

    func testLoggingOutcomeAddsPrivateRecordWithoutInflatingProofQuestOrStreakCounts() throws {
        let outcomeTime = Date(timeIntervalSince1970: 12_500)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            kind: .applied,
            title: "Applied to campus iOS internship",
            organizationName: "Example Labs",
            note: "Submitted a truthful application using the SwiftUI proof artifact.",
            occurredAt: outcomeTime,
            createdAt: outcomeTime,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let initial = OpenLARPEngine.confirmGoal(goal, now: outcomeTime)

        let state = OpenLARPEngine.logOutcome(outcome, in: initial, now: outcomeTime)

        XCTAssertEqual(state.outcomeLog.count, 1)
        XCTAssertEqual(state.outcomeLog.first, outcome)
        XCTAssertEqual(state.progress.proofCount, initial.progress.proofCount)
        XCTAssertEqual(state.progress.completedQuestCount, initial.progress.completedQuestCount)
        XCTAssertEqual(state.progress.streakCount, initial.progress.streakCount)
        XCTAssertGreaterThan(state.progress.xp, initial.progress.xp)
        XCTAssertEqual(state.progress.readiness.applicationExecution, initial.progress.readiness.applicationExecution + 4)
        XCTAssertEqual(state.progress.readinessHistory.last?.source, .outcomeLog)
        XCTAssertEqual(state.progress.readinessHistory.last?.relatedOutcomeID, outcome.id)
        XCTAssertEqual(state.agentBrief.activities.first?.type, .outcomeLogged)
        XCTAssertTrue(state.agentBrief.summary.contains("1 career outcome"))
    }

    func testLoggingSameOutcomeIDTwiceDoesNotDoubleCountProgress() {
        let outcomeTime = Date(timeIntervalSince1970: 12_550)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!,
            kind: .interview,
            title: "Scheduled recruiter screen",
            organizationName: "Example Labs",
            note: "Same backend event replayed twice.",
            occurredAt: outcomeTime,
            createdAt: outcomeTime,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let initial = OpenLARPEngine.confirmGoal(goal, now: outcomeTime)

        let once = OpenLARPEngine.logOutcome(outcome, in: initial, now: outcomeTime)
        let twice = OpenLARPEngine.logOutcome(outcome, in: once, now: outcomeTime.addingTimeInterval(60))

        XCTAssertEqual(twice.outcomeLog.count, 1)
        XCTAssertEqual(twice.progress.xp, once.progress.xp)
        XCTAssertEqual(twice.progress.readiness, once.progress.readiness)
        XCTAssertEqual(twice.progress.readinessHistory.count, once.progress.readinessHistory.count)
        XCTAssertEqual(twice.progress.badges, once.progress.badges)
    }

    func testEditingOutcomeUpdatesRecordWithoutDoubleCountingProgress() {
        let outcomeTime = Date(timeIntervalSince1970: 12_600)
        let editTime = outcomeTime.addingTimeInterval(120)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!,
            kind: .applied,
            title: "Applied to campus iOS internship",
            organizationName: "Example Labs",
            note: "Original application note.",
            occurredAt: outcomeTime,
            createdAt: outcomeTime,
            updatedAt: outcomeTime,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let initial = OpenLARPEngine.confirmGoal(goal, now: outcomeTime)
        let logged = OpenLARPEngine.logOutcome(outcome, in: initial, now: outcomeTime)
        var edited = outcome
        edited.kind = .interview
        edited.title = "Scheduled campus iOS internship screen"
        edited.organizationName = "Example Labs Recruiting"
        edited.note = "Recruiter confirmed a truthful first screen."
        edited.occurredAt = editTime
        edited.updatedAt = editTime

        let updated = OpenLARPEngine.updateOutcome(edited, in: logged, now: editTime)

        XCTAssertEqual(updated.outcomeLog.count, 1)
        XCTAssertEqual(updated.outcomeLog.first?.id, outcome.id)
        XCTAssertEqual(updated.outcomeLog.first?.kind, .interview)
        XCTAssertEqual(updated.outcomeLog.first?.title, "Scheduled campus iOS internship screen")
        XCTAssertEqual(updated.outcomeLog.first?.updatedAt, editTime)
        XCTAssertNil(updated.outcomeLog.first?.deletedAt)
        XCTAssertEqual(updated.progress.xp, logged.progress.xp)
        XCTAssertEqual(updated.progress.readiness, logged.progress.readiness)
        XCTAssertEqual(updated.progress.readinessHistory.count, logged.progress.readinessHistory.count)
        XCTAssertTrue(updated.agentBrief.summary.contains("1 career outcome"))
    }

    func testDeletingOutcomeHidesRecordButKeepsHistoricalProgressSnapshot() {
        let outcomeTime = Date(timeIntervalSince1970: 12_620)
        let deleteTime = outcomeTime.addingTimeInterval(180)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "ACACACAC-ACAC-ACAC-ACAC-ACACACACACAC")!,
            kind: .applied,
            title: "Applied to first iOS internship",
            organizationName: "Example Labs",
            note: "Application submitted with real proof.",
            occurredAt: outcomeTime,
            createdAt: outcomeTime,
            updatedAt: outcomeTime,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let initial = OpenLARPEngine.confirmGoal(goal, now: outcomeTime)
        let logged = OpenLARPEngine.logOutcome(outcome, in: initial, now: outcomeTime)

        let deleted = OpenLARPEngine.deleteOutcome(id: outcome.id, in: logged, now: deleteTime)

        XCTAssertEqual(deleted.outcomeLog.count, 1)
        XCTAssertEqual(deleted.outcomeLog.first?.deletedAt, deleteTime)
        XCTAssertEqual(OutcomeLogContent(outcomes: deleted.outcomeLog).outcomes.count, 0)
        XCTAssertEqual(deleted.progress.xp, logged.progress.xp)
        XCTAssertEqual(deleted.progress.readiness, logged.progress.readiness)
        XCTAssertEqual(deleted.progress.readinessHistory.last?.relatedOutcomeID, outcome.id)
        XCTAssertTrue(deleted.agentBrief.summary.contains("0 career outcomes"))
    }

    func testRejectionOutcomeDoesNotPretendReadinessImproved() {
        let outcomeTime = Date(timeIntervalSince1970: 12_700)
        let outcome = CareerOutcomeRecord(
            kind: .rejection,
            title: "Rejected after product intern screen",
            organizationName: "Example Labs",
            note: "Rejected after the first screen; need stronger product proof.",
            occurredAt: outcomeTime,
            createdAt: outcomeTime,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let initial = OpenLARPEngine.confirmGoal(goal, now: outcomeTime)

        let state = OpenLARPEngine.logOutcome(outcome, in: initial, now: outcomeTime)

        XCTAssertEqual(state.progress.readiness.overall, initial.progress.readiness.overall)
        XCTAssertEqual(state.progress.proofCount, initial.progress.proofCount)
        XCTAssertEqual(state.progress.streakCount, initial.progress.streakCount)
        XCTAssertFalse(state.progress.badges.contains(.firstOutcome))
        XCTAssertEqual(state.outcomeLog.first?.kind.recoveryPrompt, "Turn the rejection into one recovery quest instead of treating it as proof of failure.")
    }

    func testChangedGoalOutcomeIsContextOnlyUntilFreshDiagnostic() {
        let outcomeTime = Date(timeIntervalSince1970: 12_750)
        let outcome = CareerOutcomeRecord(
            kind: .changedGoal,
            title: "Considering AI product roles instead",
            organizationName: "",
            note: "The plan should not become more ready until a new diagnostic runs.",
            occurredAt: outcomeTime,
            createdAt: outcomeTime,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let initial = OpenLARPEngine.confirmGoal(goal, now: outcomeTime)

        let state = OpenLARPEngine.logOutcome(outcome, in: initial, now: outcomeTime)

        XCTAssertEqual(state.outcomeLog.first?.kind, .changedGoal)
        XCTAssertEqual(state.progress.xp, initial.progress.xp)
        XCTAssertEqual(state.progress.readiness, initial.progress.readiness)
        XCTAssertEqual(state.progress.readinessHistory.count, initial.progress.readinessHistory.count)
        XCTAssertFalse(state.progress.badges.contains(.firstOutcome))
    }

    @MainActor
    func testStorePersistsOutcomeLogAcrossReloadAndGoalReset() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )
        let outcomeTime = Date(timeIntervalSince1970: 12_900)

        await store.confirmGoal(goal)
        store.logOutcome(
            kind: .interview,
            title: "Scheduled first iOS internship screen",
            organizationName: "Example Labs",
            note: "Recruiter confirmed a 20-minute screen.",
            occurredAt: outcomeTime,
            isPrivate: true
        )

        let reloaded = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )
        XCTAssertEqual(reloaded.state.outcomeLog.count, 1)
        XCTAssertEqual(reloaded.state.outcomeLog.first?.kind, .interview)
        XCTAssertEqual(reloaded.state.outcomeLog.first?.targetRoleTitle, goal.targetRole)
        XCTAssertEqual(reloaded.state.outcomeLog.first?.targetRoleID, reloaded.state.targetRoles.first?.id)

        reloaded.resetGoal()

        XCTAssertTrue(reloaded.state.needsGoalSetup)
        XCTAssertEqual(reloaded.state.outcomeLog.count, 1)
        XCTAssertEqual(reloaded.state.outcomeLog.first?.title, "Scheduled first iOS internship screen")
    }

    @MainActor
    func testStoreRejectsEditingOutcomeToFutureDate() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 13_020)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { now }
        )

        await store.confirmGoal(goal)
        store.logOutcome(
            kind: .applied,
            title: "Applied to iOS internship",
            organizationName: "Example Labs",
            note: "Submitted with real proof.",
            occurredAt: now,
            isPrivate: true
        )
        let outcomeID = store.state.outcomeLog[0].id
        let originalState = store.state

        store.updateOutcome(
            id: outcomeID,
            kind: .interview,
            title: "Future interview",
            organizationName: "Example Labs",
            note: "This date should not save.",
            occurredAt: now.addingTimeInterval(86_400),
            isPrivate: true
        )

        XCTAssertEqual(store.state, originalState)
        XCTAssertEqual(store.errorMessage, "Choose today or a past date for the outcome.")
    }

    @MainActor
    func testStoreReturnsClearErrorWhenEditingMissingOutcome() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 13_040)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { now }
        )

        await store.confirmGoal(goal)
        store.updateOutcome(
            id: UUID(uuidString: "ADADADAD-ADAD-ADAD-ADAD-ADADADADADAD")!,
            kind: .applied,
            title: "Missing outcome edit",
            organizationName: "Example Labs",
            note: "",
            occurredAt: now,
            isPrivate: true
        )

        XCTAssertTrue(store.state.outcomeLog.isEmpty)
        XCTAssertEqual(store.errorMessage, "That outcome could not be found.")
    }

    @MainActor
    func testStoreRejectsFutureOutcomeDatesBeforeSaving() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 13_000)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { now }
        )

        await store.confirmGoal(goal)
        store.logOutcome(
            kind: .offer,
            title: "Future offer",
            organizationName: "Example Labs",
            note: "This date is not allowed yet.",
            occurredAt: now.addingTimeInterval(86_400),
            isPrivate: true
        )

        XCTAssertTrue(store.state.outcomeLog.isEmpty)
        XCTAssertEqual(store.errorMessage, "Choose today or a past date for the outcome.")
    }

    func testOutcomeLogContentSortsNewestFirstAndReportsEmptyState() {
        let older = CareerOutcomeRecord(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            kind: .applied,
            title: "Applied to first role",
            organizationName: "Example Labs",
            note: "",
            occurredAt: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 10),
            targetRoleTitle: "iOS internship",
            isPrivate: true
        )
        let newer = CareerOutcomeRecord(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            kind: .offer,
            title: "Received internship offer",
            organizationName: "Example Labs",
            note: "Offer received after proof sprint.",
            occurredAt: Date(timeIntervalSince1970: 20),
            createdAt: Date(timeIntervalSince1970: 20),
            targetRoleTitle: "iOS internship",
            isPrivate: true
        )

        let content = OutcomeLogContent(outcomes: [older, newer])
        let empty = OutcomeLogContent(outcomes: [])

        XCTAssertEqual(content.outcomes.map(\.id), [newer.id, older.id])
        XCTAssertEqual(content.countText, "2 career outcomes")
        XCTAssertEqual(content.latestSummary, "Offer: Received internship offer")
        XCTAssertEqual(empty.emptyMessage, "Log real outcomes here: applied, interview, rejection, offer, or changed goal.")
    }

    func testOlderPersistedStateDecodesWithEmptyOutcomeLog() throws {
        let state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 13_100))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "outcomeLog")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(OpenLARPState.self, from: oldData)

        XCTAssertEqual(decoded.schemaVersion, 8)
        XCTAssertTrue(decoded.outcomeLog.isEmpty)
    }

    func testOlderOutcomeRecordDecodesWithDefaultMutationMetadata() throws {
        let createdAt = Date(timeIntervalSince1970: 13_140)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "B7B7B7B7-B7B7-B7B7-B7B7-B7B7B7B7B7B7")!,
            kind: .applied,
            title: "Applied to iOS internship",
            organizationName: "Example Labs",
            note: "Old local JSON before mutation metadata existed.",
            occurredAt: createdAt,
            createdAt: createdAt,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder.encode(outcome)) as? [String: Any])
        object.removeValue(forKey: "updatedAt")
        object.removeValue(forKey: "deletedAt")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CareerOutcomeRecord.self, from: oldData)

        XCTAssertEqual(decoded.id, outcome.id)
        XCTAssertEqual(decoded.updatedAt, createdAt)
        XCTAssertNil(decoded.deletedAt)
        XCTAssertFalse(decoded.isDeleted)
    }

    @MainActor
    func testStoreEditsOutcomeAndPersistsAcrossReloadWithoutProgressReplay() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        var clock = Date(timeIntervalSince1970: 13_160)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { clock }
        )

        await store.confirmGoal(goal)
        store.logOutcome(
            kind: .applied,
            title: "Applied to iOS internship",
            organizationName: "Example Labs",
            note: "Submitted the first truthful application.",
            occurredAt: clock,
            isPrivate: true
        )
        let loggedState = store.state
        let outcomeID = store.state.outcomeLog[0].id

        clock = clock.addingTimeInterval(300)
        store.updateOutcome(
            id: outcomeID,
            kind: .interview,
            title: "Scheduled iOS internship screen",
            organizationName: "Example Labs Recruiting",
            note: "Recruiter confirmed a first screen.",
            occurredAt: clock,
            isPrivate: false
        )

        XCTAssertEqual(store.state.outcomeLog.count, 1)
        XCTAssertEqual(store.state.outcomeLog[0].kind, .interview)
        XCTAssertEqual(store.state.outcomeLog[0].title, "Scheduled iOS internship screen")
        XCTAssertEqual(store.state.outcomeLog[0].updatedAt, clock)
        XCTAssertFalse(store.state.outcomeLog[0].isPrivate)
        XCTAssertEqual(store.state.progress.xp, loggedState.progress.xp)
        XCTAssertEqual(store.state.progress.readiness, loggedState.progress.readiness)
        XCTAssertEqual(store.state.progress.readinessHistory.count, loggedState.progress.readinessHistory.count)

        let reloaded = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { clock }
        )

        XCTAssertEqual(reloaded.state.outcomeLog.count, 1)
        XCTAssertEqual(reloaded.state.outcomeLog[0].id, outcomeID)
        XCTAssertEqual(reloaded.state.outcomeLog[0].kind, .interview)
        XCTAssertEqual(reloaded.state.outcomeLog[0].title, "Scheduled iOS internship screen")
        XCTAssertEqual(reloaded.state.outcomeLog[0].updatedAt, clock)
        XCTAssertEqual(reloaded.state.progress.xp, loggedState.progress.xp)
        XCTAssertEqual(reloaded.state.progress.readinessHistory.count, loggedState.progress.readinessHistory.count)
    }

    func testCloudCareerGraphSnapshotExportsBackendSafeEvidenceByPolicy() throws {
        let now = Date(timeIntervalSince1970: 13_200)
        let attachment = ProofAttachment(
            id: UUID(uuidString: "AEAEAEAE-AEAE-AEAE-AEAE-AEAEAEAEAEAE")!,
            fileName: "proof.png",
            originalFileName: "local-proof.png",
            contentType: "image/png",
            byteCount: 42_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let proof = ProofRecord(
            id: UUID(uuidString: "AFAFAFAF-AFAF-AFAF-AFAF-AFAFAFAFAFAF")!,
            questID: UUID(uuidString: "B0B0B0B0-B0B0-B0B0-B0B0-B0B0B0B0B0B0")!,
            questTitle: "Create one tiny proof artifact",
            kind: .proof,
            text: "I built a real proof artifact and saved a screenshot.",
            link: "https://example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Real artifact",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
        let privateOutcome = CareerOutcomeRecord(
            id: UUID(uuidString: "B1B1B1B1-B1B1-B1B1-B1B1-B1B1B1B1B1B1")!,
            kind: .interview,
            title: "Private recruiter screen",
            organizationName: "Example Labs",
            note: "Sensitive notes stay local unless export policy allows them.",
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        let publicOutcome = CareerOutcomeRecord(
            id: UUID(uuidString: "B2B2B2B2-B2B2-B2B2-B2B2-B2B2B2B2B2B2")!,
            kind: .offer,
            title: "Share-safe internship offer",
            organizationName: "Example Labs",
            note: "Public win summary.",
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            targetRoleTitle: goal.targetRole,
            isPrivate: false
        )
        var deletedOutcome = publicOutcome
        deletedOutcome.id = UUID(uuidString: "B8B8B8B8-B8B8-B8B8-B8B8-B8B8B8B8B8B8")!
        deletedOutcome.title = "Deleted share-safe outcome"
        deletedOutcome.updatedAt = now.addingTimeInterval(60)
        deletedOutcome.deletedAt = now.addingTimeInterval(60)
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        state.outcomeLog = [privateOutcome, publicOutcome, deletedOutcome]
        let mapper = LocalCareerGraphCloudMapper()

        let privateSnapshot = mapper.makeSnapshot(
            from: state,
            policy: CloudExportPolicy(ownerUserID: "user_123", includePrivateEvidence: false),
            generatedAt: now
        )
        let fullSnapshot = mapper.makeSnapshot(
            from: state,
            policy: CloudExportPolicy(ownerUserID: "user_123", includePrivateEvidence: true),
            generatedAt: now
        )

        XCTAssertEqual(privateSnapshot.ownerUserID, "user_123")
        XCTAssertTrue(privateSnapshot.proofRecords.isEmpty)
        XCTAssertEqual(privateSnapshot.outcomes.map(\.metadata.localID), [publicOutcome.id.uuidString])
        XCTAssertEqual(fullSnapshot.proofRecords.count, 1)
        XCTAssertEqual(fullSnapshot.proofRecords.first?.attachments.first?.storagePath, "users/user_123/proofAttachments/\(attachment.id.uuidString)")
        XCTAssertEqual(fullSnapshot.outcomes.map(\.metadata.localID), [privateOutcome.id.uuidString, publicOutcome.id.uuidString])
        XCTAssertFalse(fullSnapshot.outcomes.map(\.metadata.localID).contains(deletedOutcome.id.uuidString))

        let encoded = try JSONEncoder().encode(fullSnapshot)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("localRelativePath"))
        XCTAssertFalse(json.contains("private-device-path"))
        XCTAssertNoThrow(try JSONDecoder().decode(CloudCareerGraphSnapshot.self, from: encoded))
    }

    func testCloudCareerGraphSnapshotExportsPrivacySafeGoalAndProfileByDefault() throws {
        let now = Date(timeIntervalSince1970: 13_250)
        let state = privacySensitiveCloudState(now: now)
        let mapper = LocalCareerGraphCloudMapper()

        let privateSnapshot = mapper.makeSnapshot(
            from: state,
            policy: CloudExportPolicy(ownerUserID: "user_123", includePrivateEvidence: false),
            generatedAt: now
        )
        let fullSnapshot = mapper.makeSnapshot(
            from: state,
            policy: CloudExportPolicy(ownerUserID: "user_123", includePrivateEvidence: true),
            generatedAt: now
        )

        XCTAssertEqual(privateSnapshot.ownerUserID, "user_123")
        XCTAssertEqual(privateSnapshot.goal?.targetRole, "AI product internship")
        XCTAssertEqual(privateSnapshot.goal?.timeline, "30 days")
        XCTAssertEqual(privateSnapshot.goal?.currentStatus, .student)
        XCTAssertNil(privateSnapshot.goal?.privateContext)
        XCTAssertEqual(privateSnapshot.userProfile?.segment, .student)
        XCTAssertNil(privateSnapshot.userProfile?.email)
        XCTAssertNil(privateSnapshot.userProfile?.accountID)

        let privateJSON = String(
            decoding: try JSONEncoder().encode(privateSnapshot),
            as: UTF8.self
        )
        assertNoPrivateCloudExportLeaks(privateJSON)

        XCTAssertEqual(fullSnapshot.goal?.privateContext?.background, state.goal?.background)
        XCTAssertEqual(fullSnapshot.goal?.privateContext?.existingProof, state.goal?.existingProof)
        XCTAssertEqual(fullSnapshot.goal?.privateContext?.confidence, state.goal?.confidence)
        XCTAssertEqual(fullSnapshot.goal?.privateContext?.biggestBlocker, state.goal?.biggestBlocker)
        XCTAssertNoThrow(try JSONDecoder().decode(
            CloudCareerGraphSnapshot.self,
            from: try JSONEncoder().encode(fullSnapshot)
        ))
    }

    func testCloudCareerGraphSnapshotDecodesLegacyRawGoalWithoutPrivateContext() throws {
        let now = Date(timeIntervalSince1970: 13_255)
        let state = privacySensitiveCloudState(now: now)
        let legacyPayload = LegacyCloudCareerGraphSnapshotPayload(
            schemaVersion: 1,
            ownerUserID: "user_legacy",
            generatedAt: now,
            userProfile: nil,
            goal: try XCTUnwrap(state.goal),
            targetRoles: [],
            proofRecords: [],
            outcomes: [],
            readinessSnapshots: [],
            currentReadiness: state.progress.readiness,
            policy: CloudExportPolicy(ownerUserID: "user_legacy", includePrivateEvidence: true)
        )

        let decoded = try JSONDecoder().decode(
            CloudCareerGraphSnapshot.self,
            from: try JSONEncoder().encode(legacyPayload)
        )

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.goal?.targetRole, "AI product internship")
        XCTAssertEqual(decoded.goal?.timeline, "30 days")
        XCTAssertEqual(decoded.goal?.currentStatus, .student)
        XCTAssertNil(decoded.goal?.privateContext)

        let reencodedJSON = String(
            decoding: try JSONEncoder().encode(decoded),
            as: UTF8.self
        )
        assertNoPrivateCloudExportLeaks(reencodedJSON)
    }

    func testCloudCareerOutcomeDocumentRoundTripsStableBackendFields() throws {
        let now = Date(timeIntervalSince1970: 13_300)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "B3B3B3B3-B3B3-B3B3-B3B3-B3B3B3B3B3B3")!,
            kind: .applied,
            title: "Applied to iOS internship",
            organizationName: "Example Labs",
            note: "Submitted a truthful application.",
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            targetRoleID: UUID(uuidString: "B4B4B4B4-B4B4-B4B4-B4B4-B4B4B4B4B4B4")!,
            targetRoleTitle: goal.targetRole,
            relatedQuestID: UUID(uuidString: "B5B5B5B5-B5B5-B5B5-B5B5-B5B5B5B5B5B5")!,
            relatedProofID: UUID(uuidString: "B6B6B6B6-B6B6-B6B6-B6B6-B6B6B6B6B6B6")!,
            isPrivate: true
        )

        let document = CloudCareerOutcomeDocument(
            outcome: outcome,
            ownerUserID: "user_123"
        )
        let decoded = try JSONDecoder().decode(
            CloudCareerOutcomeDocument.self,
            from: try JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded.metadata.ownerUserID, "user_123")
        XCTAssertEqual(decoded.metadata.localID, outcome.id.uuidString)
        XCTAssertEqual(decoded.kind, .applied)
        XCTAssertEqual(decoded.targetRoleID, outcome.targetRoleID?.uuidString)
        XCTAssertEqual(decoded.relatedQuestID, outcome.relatedQuestID?.uuidString)
        XCTAssertEqual(decoded.relatedProofID, outcome.relatedProofID?.uuidString)
        XCTAssertEqual(decoded.collectionPath, "users/user_123/outcomes")
        XCTAssertEqual(decoded.documentPath, "users/user_123/outcomes/\(outcome.id.uuidString)")
    }

    func testBackendSessionDefaultsToLocalOnlyUnauthenticatedState() {
        let state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 13_400))
        let session = BackendUserSession.localOnly(for: state)

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertEqual(session.authProvider, .localMock)
        XCTAssertEqual(session.ownerUserID, "local_\(state.userProfile?.id.uuidString ?? "device")")
        XCTAssertEqual(session.firestore.status, .notConnected)
        XCTAssertEqual(session.storage.status, .notConnected)
        XCTAssertEqual(session.functions.status, .notConnected)
        XCTAssertEqual(session.cloudRun.status, .notConnected)
        XCTAssertEqual(session.genkit.status, .localMock)
        XCTAssertTrue(session.requiresUserApprovalForExternalActions)
    }

    func testCareerGraphSyncPreparationRequestBuildsBackendSafeSnapshotAndLocalMockPreparation() async throws {
        let now = Date(timeIntervalSince1970: 13_500)
        let attachment = ProofAttachment(
            id: UUID(uuidString: "D1D1D1D1-D1D1-D1D1-D1D1-D1D1D1D1D1D1")!,
            fileName: "proof-upload.png",
            originalFileName: "private-proof-upload.png",
            contentType: "image/png",
            byteCount: 77_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let proof = ProofRecord(
            id: UUID(uuidString: "D2D2D2D2-D2D2-D2D2-D2D2-D2D2D2D2D2D2")!,
            questID: UUID(uuidString: "D3D3D3D3-D3D3-D3D3-D3D3-D3D3D3D3D3D3")!,
            questTitle: "Create one tiny proof artifact",
            kind: .proof,
            text: "I shipped a real SwiftUI proof artifact and saved the screenshot locally.",
            link: "https://example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Real artifact",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        state.userProfile?.privacy.memoryMode = .cloudReady
        let session = BackendUserSession.localOnly(for: state)

        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )
        let result = try await LocalMockCareerGraphSyncService().prepareSync(request)

        XCTAssertEqual(request.snapshot.ownerUserID, session.ownerUserID)
        XCTAssertEqual(request.firestoreRootPath, "users/\(session.ownerUserID)")
        XCTAssertFalse(request.snapshot.policy.allowsLongTermMemoryWrite)
        XCTAssertEqual(request.integrationRoutes.map(\.kind), [
            .firebaseAuth,
            .firestore,
            .firebaseStorage,
            .cloudFunctions,
            .cloudRun,
            .genkit
        ])
        XCTAssertEqual(result.status, .preparedLocally)
        XCTAssertFalse(result.didContactNetwork)
        XCTAssertTrue(result.requiresAuthenticationToSync)
        XCTAssertTrue(result.firestoreDocumentPaths.contains("users/\(session.ownerUserID)/proofRecords/\(proof.id.uuidString)"))
        XCTAssertEqual(result.uploadIntents.map(\.storagePath), [
            "users/\(session.ownerUserID)/proofAttachments/\(attachment.id.uuidString)"
        ])

        let encoded = try JSONEncoder().encode(request)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("localRelativePath"))
        XCTAssertFalse(json.contains("private-device-path"))
        XCTAssertFalse(json.contains("sk-"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("api key"))
    }

    func testCareerGraphSyncManifestListsGoalProfileDocumentsAndFileUploadsForAdapters() async throws {
        let now = Date(timeIntervalSince1970: 13_525)
        var state = privacySensitiveCloudState(now: now)
        state.userProfile?.privacy.shareWins = false
        let session = BackendUserSession.localOnly(for: state)
        let attachment = try XCTUnwrap(state.progress.recentProof.first?.attachments.first)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: true
        )

        let result = try await LocalMockCareerGraphSyncService().prepareSync(request)
        let manifest = result.syncManifest

        XCTAssertEqual(manifest.ownerUserID, session.ownerUserID)
        XCTAssertEqual(manifest.firestoreRootPath, "users/\(session.ownerUserID)")
        XCTAssertEqual(manifest.documentWrites.map(\.documentType), [
            .profile,
            .goal,
            .targetRole,
            .proofRecord,
            .proofAttachment,
            .readinessSnapshot
        ])
        XCTAssertTrue(manifest.documentWrites.allSatisfy { $0.operation == .upsert })
        XCTAssertEqual(result.firestoreDocumentPaths, manifest.documentWrites.map(\.documentPath))
        XCTAssertTrue(manifest.documentWrites.contains {
            $0.documentPath.hasPrefix("users/\(session.ownerUserID)/goals/")
        })
        XCTAssertEqual(manifest.storageUploads.map(\.storagePath), [
            "users/\(session.ownerUserID)/proofAttachments/\(attachment.id.uuidString)"
        ])
        XCTAssertEqual(manifest.storageUploads.map(\.proofDocumentPath), [
            "users/\(session.ownerUserID)/proofRecords/\(state.progress.recentProof[0].id.uuidString)"
        ])
        XCTAssertEqual(manifest.storageUploads.map(\.attachmentDocumentPath), [
            "users/\(session.ownerUserID)/proofAttachments/\(attachment.id.uuidString)"
        ])
        XCTAssertEqual(manifest.requiredRoutes.map(\.kind), [
            .firebaseAuth,
            .firestore,
            .firebaseStorage
        ])
        XCTAssertEqual(result.integrationRoutes.map(\.kind), manifest.requiredRoutes.map(\.kind))
        XCTAssertEqual(
            CareerGraphSyncPreview(request: request, result: result).integrationRoutes.map(\.kind),
            manifest.requiredRoutes.map(\.kind)
        )
        XCTAssertFalse(result.didContactNetwork)

        let manifestJSON = String(
            decoding: try JSONEncoder().encode(manifest),
            as: UTF8.self
        )
        assertNoPrivateCloudExportLeaks(manifestJSON)
        XCTAssertNoThrow(try JSONDecoder().decode(
            CareerGraphSyncManifest.self,
            from: try JSONEncoder().encode(manifest)
        ))
    }

    func testCareerGraphSyncRequestAndManifestDoNotLeakPrivateEvidenceByDefault() async throws {
        let now = Date(timeIntervalSince1970: 13_530)
        let state = privacySensitiveCloudState(now: now)
        let session = BackendUserSession.localOnly(for: state)
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: false
        )

        let encodedRequest = String(
            decoding: try JSONEncoder().encode(request),
            as: UTF8.self
        )
        assertNoPrivateCloudExportLeaks(encodedRequest)
        XCTAssertNil(request.session.accountID)
        XCTAssertNil(request.session.email)
        XCTAssertNil(request.snapshot.goal?.privateContext)
        XCTAssertTrue(request.snapshot.proofRecords.isEmpty)

        let result = try await LocalMockCareerGraphSyncService().prepareSync(request)
        let manifest = result.syncManifest

        XCTAssertFalse(manifest.documentWrites.map(\.documentType).contains(.proofRecord))
        XCTAssertFalse(manifest.documentWrites.map(\.documentType).contains(.proofAttachment))
        XCTAssertTrue(manifest.storageUploads.isEmpty)
        XCTAssertEqual(manifest.requiredRoutes.map(\.kind), [
            .firebaseAuth,
            .firestore
        ])
        XCTAssertEqual(result.integrationRoutes.map(\.kind), manifest.requiredRoutes.map(\.kind))
        XCTAssertEqual(
            CareerGraphSyncPreview(request: request, result: result).integrationRoutes.map(\.kind),
            manifest.requiredRoutes.map(\.kind)
        )

        let encodedManifest = String(
            decoding: try JSONEncoder().encode(manifest),
            as: UTF8.self
        )
        assertNoPrivateCloudExportLeaks(encodedManifest)
    }

    func testCareerGraphSyncPreparationRequestRedactsAuthenticatedSessionIdentifiers() throws {
        let now = Date(timeIntervalSince1970: 13_535)
        let state = privacySensitiveCloudState(now: now)
        let session = BackendUserSession(
            ownerUserID: "firebase_uid_123",
            isAuthenticated: true,
            authProvider: .firebaseAuth,
            accountID: "acct_private_123",
            email: "langqi@example.com",
            auth: BackendIntegrationRoute(kind: .firebaseAuth, status: .connected),
            firestore: BackendIntegrationRoute(kind: .firestore, status: .connected),
            storage: BackendIntegrationRoute(kind: .firebaseStorage, status: .configured),
            functions: BackendIntegrationRoute(kind: .cloudFunctions, status: .configured),
            cloudRun: BackendIntegrationRoute(kind: .cloudRun, status: .configured),
            genkit: BackendIntegrationRoute(kind: .genkit, status: .configured)
        )

        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: now,
            includePrivateEvidence: false
        )

        XCTAssertTrue(request.session.isAuthenticated)
        XCTAssertEqual(request.session.authProvider, .firebaseAuth)
        XCTAssertNil(request.session.accountID)
        XCTAssertNil(request.session.email)
        XCTAssertEqual(request.firestoreRootPath, "users/firebase_uid_123")

        let encodedRequest = String(
            decoding: try JSONEncoder().encode(request),
            as: UTF8.self
        )
        assertNoPrivateCloudExportLeaks(encodedRequest)
    }

    func testCareerGraphSyncPreparationRequestDerivesPrivateEvidenceFromSharingPreference() {
        let now = Date(timeIntervalSince1970: 13_550)
        var privateState = OpenLARPEngine.confirmGoal(goal, now: now)
        privateState.userProfile?.privacy.shareWins = false
        let privateSession = BackendUserSession.localOnly(for: privateState)

        let privateRequest = CareerGraphSyncPreparationRequest(
            state: privateState,
            session: privateSession,
            requestedAt: now
        )

        XCTAssertFalse(privateRequest.includePrivateEvidence)
        XCTAssertFalse(privateRequest.snapshot.policy.includePrivateEvidence)

        var shareableState = OpenLARPEngine.confirmGoal(goal, now: now)
        shareableState.userProfile?.privacy.shareWins = true
        let shareableSession = BackendUserSession.localOnly(for: shareableState)

        let shareableRequest = CareerGraphSyncPreparationRequest(
            state: shareableState,
            session: shareableSession,
            requestedAt: now
        )

        XCTAssertTrue(shareableRequest.includePrivateEvidence)
        XCTAssertTrue(shareableRequest.snapshot.policy.includePrivateEvidence)
    }

    func testCareerGraphSetupStatusContentShowsMissingSetupActions() {
        let emptyContent = CareerGraphSetupStatusContent(
            state: .empty,
            session: BackendUserSession.localOnly(for: .empty)
        )

        XCTAssertEqual(emptyContent.nextActionTitle, "Set career goal")
        XCTAssertEqual(emptyContent.rows.first { $0.title == "Goal" }?.value, "Missing")
        XCTAssertEqual(emptyContent.rows.first { $0.title == "Account" }?.value, "Device only")
        XCTAssertEqual(emptyContent.rows.first { $0.title == "File backup" }?.value, "Local only")

        let goalState = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 13_600))
        let goalContent = CareerGraphSetupStatusContent(
            state: goalState,
            session: BackendUserSession.localOnly(for: goalState)
        )

        XCTAssertEqual(goalContent.nextActionTitle, "Add first proof")
        XCTAssertEqual(goalContent.rows.first { $0.title == "Goal" }?.value, "Set")
        XCTAssertEqual(goalContent.rows.first { $0.title == "Agent context" }?.value, "On-device")
    }

    func testCareerGraphSetupStatusContentSummarizesConnectedEvidenceAndPrivacy() {
        let now = Date(timeIntervalSince1970: 13_700)
        let proof = proofRecord(
            id: UUID(uuidString: "D4D4D4D4-D4D4-D4D4-D4D4-D4D4D4D4D4D4")!,
            questTitle: "Create one tiny proof artifact",
            submittedAt: now
        )
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "D5D5D5D5-D5D5-D5D5-D5D5-D5D5D5D5D5D5")!,
            kind: .interview,
            title: "Scheduled first recruiter screen",
            organizationName: "Example Labs",
            note: "Private notes should not show in setup status.",
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        state.outcomeLog = [outcome]
        state.userProfile?.privacy.memoryMode = .cloudReady
        state.userProfile?.privacy.shareWins = true

        let content = CareerGraphSetupStatusContent(
            state: state,
            session: BackendUserSession.localOnly(for: state)
        )

        XCTAssertEqual(content.summaryTitle, "Career Graph")
        XCTAssertEqual(content.rows.first { $0.title == "Proof receipts" }?.value, "1 saved")
        XCTAssertEqual(content.rows.first { $0.title == "Proof receipts" }?.detail, "Latest: Create one tiny proof artifact")
        XCTAssertEqual(content.rows.first { $0.title == "Outcomes" }?.value, "1 logged")
        XCTAssertEqual(content.rows.first { $0.title == "Outcomes" }?.detail, "Latest: Interview")
        XCTAssertEqual(content.rows.first { $0.title == "Memory" }?.value, "Cloud-ready")
        XCTAssertEqual(content.rows.first { $0.title == "Sharing" }?.value, "Allowed later")
        XCTAssertEqual(content.nextActionTitle, "Connect account later")

        let displayText = content.rows.flatMap { [$0.title, $0.value, $0.detail] }.joined(separator: " ")
        XCTAssertFalse(displayText.contains(proof.id.uuidString))
        XCTAssertFalse(displayText.contains(outcome.id.uuidString))
        XCTAssertFalse(displayText.contains("Private notes"))
    }

    @MainActor
    func testStorePreparesCareerGraphSyncPreviewWithoutContactingNetwork() async throws {
        let now = Date(timeIntervalSince1970: 13_800)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let attachment = ProofAttachment(
            id: UUID(uuidString: "E1E1E1E1-E1E1-E1E1-E1E1-E1E1E1E1E1E1")!,
            fileName: "proof-upload.png",
            originalFileName: "private-proof-upload.png",
            contentType: "image/png",
            byteCount: 77_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let proof = ProofRecord(
            id: UUID(uuidString: "E2E2E2E2-E2E2-E2E2-E2E2-E2E2E2E2E2E2")!,
            questID: UUID(uuidString: "E3E3E3E3-E3E3-E3E3-E3E3-E3E3E3E3E3E3")!,
            questTitle: "Create one tiny proof artifact",
            kind: .proof,
            text: "I shipped a real SwiftUI proof artifact and saved the screenshot locally.",
            link: "https://example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Real artifact",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now }
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)
        store.state.progress.recentProof = [proof]
        store.state.progress.proofCount = 1
        store.state.userProfile?.privacy.memoryMode = .cloudReady
        store.state.userProfile?.privacy.shareWins = true

        await store.prepareCareerGraphSyncPreview()

        let preview = try XCTUnwrap(store.careerGraphSyncPreview)
        XCTAssertEqual(syncService.requests.count, 1)
        XCTAssertEqual(preview.status, .preparedLocally)
        XCTAssertEqual(preview.documentCount, 6)
        XCTAssertEqual(preview.proofUploadCount, 1)
        XCTAssertEqual(preview.proofUploadByteCount, attachment.byteCount)
        XCTAssertEqual(preview.includedPrivateEvidence, true)
        XCTAssertEqual(preview.allowsLongTermMemoryWrite, false)
        XCTAssertEqual(preview.didContactNetwork, false)
        XCTAssertEqual(preview.requiresAuthenticationToSync, true)
        XCTAssertEqual(preview.preparedAt, now)
        XCTAssertFalse(store.isPreparingCareerGraphSyncPreview)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(syncService.requests.first?.includePrivateEvidence, true)
        XCTAssertFalse(syncService.requests.first?.snapshot.policy.allowsLongTermMemoryWrite ?? true)
    }

    @MainActor
    func testStoreCareerGraphSyncPreviewKeepsPrivateEvidenceOutByDefault() async {
        let now = Date(timeIntervalSince1970: 13_850)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let attachment = ProofAttachment(
            id: UUID(uuidString: "E4E4E4E4-E4E4-E4E4-E4E4-E4E4E4E4E4E4")!,
            fileName: "proof-upload.png",
            originalFileName: "private-proof-upload.png",
            contentType: "image/png",
            byteCount: 77_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let proof = ProofRecord(
            id: UUID(uuidString: "E5E5E5E5-E5E5-E5E5-E5E5-E5E5E5E5E5E5")!,
            questID: UUID(uuidString: "E6E6E6E6-E6E6-E6E6-E6E6-E6E6E6E6E6E6")!,
            questTitle: "Create one tiny proof artifact",
            kind: .proof,
            text: "This proof should stay out of the local backup preview by default.",
            link: "https://example.com/private-proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 82,
                label: "Strong proof",
                reason: "Concrete enough to count.",
                improvement: "Tie it to one role requirement.",
                xpEarned: 100,
                readinessDelta: 6
            )
        )
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now }
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)
        store.state.progress.recentProof = [proof]
        store.state.progress.proofCount = 1
        store.state.userProfile?.privacy.shareWins = false

        await store.prepareCareerGraphSyncPreview()

        XCTAssertEqual(syncService.requests.first?.includePrivateEvidence, false)
        XCTAssertEqual(syncService.requests.first?.snapshot.proofRecords.count, 0)
        XCTAssertEqual(store.careerGraphSyncPreview?.includedPrivateEvidence, false)
        XCTAssertEqual(store.careerGraphSyncPreview?.proofUploadCount, 0)
    }

    @MainActor
    func testStoreBlocksCareerGraphSyncPreviewUntilGoalExists() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService
        )

        await store.prepareCareerGraphSyncPreview()

        XCTAssertNil(store.careerGraphSyncPreview)
        XCTAssertEqual(syncService.requests.count, 0)
        XCTAssertEqual(store.errorMessage, "Set a career goal before previewing your career graph.")
        XCTAssertFalse(store.isPreparingCareerGraphSyncPreview)
    }

    @MainActor
    func testStoreSurfacesCareerGraphSyncPreviewFailureAndClearsStalePreview() async {
        let now = Date(timeIntervalSince1970: 13_900)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now }
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)

        await store.prepareCareerGraphSyncPreview()
        XCTAssertNotNil(store.careerGraphSyncPreview)
        syncService.shouldThrow = true

        await store.prepareCareerGraphSyncPreview()

        XCTAssertNil(store.careerGraphSyncPreview)
        XCTAssertEqual(store.errorMessage, "The local career graph preview could not be prepared.")
        XCTAssertFalse(store.isPreparingCareerGraphSyncPreview)
    }

    @MainActor
    func testStoreClearsCareerGraphSyncPreviewWhenPrivacyChanges() async {
        let now = Date(timeIntervalSince1970: 13_950)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now }
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)

        await store.prepareCareerGraphSyncPreview()
        XCTAssertNotNil(store.careerGraphSyncPreview)

        store.updateProfilePrivacy(memoryMode: CareerMemoryMode.off, shareWins: false)

        XCTAssertNil(store.careerGraphSyncPreview)
    }

    @MainActor
    func testStoreClearsCareerGraphSyncPreviewWhenProofIsClaimed() async {
        let now = Date(timeIntervalSince1970: 13_960)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now },
            calendar: testCalendar
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I created a real proof artifact, connected it to the target role, and saved the steps I took.",
            link: "https://example.com/proof"
        )
        await store.prepareCareerGraphSyncPreview()
        XCTAssertNotNil(store.careerGraphSyncPreview)

        store.claimPendingQualityResult()

        XCTAssertNil(store.careerGraphSyncPreview)
    }

    @MainActor
    func testStoreClearsCareerGraphSyncPreviewWhenOutcomeChanges() async {
        let now = Date(timeIntervalSince1970: 13_970)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncService = RecordingCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now }
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)
        await store.prepareCareerGraphSyncPreview()
        XCTAssertNotNil(store.careerGraphSyncPreview)

        store.logOutcome(
            kind: .applied,
            title: "Applied to iOS internship",
            organizationName: "Example Labs",
            occurredAt: now,
            isPrivate: true
        )

        XCTAssertNil(store.careerGraphSyncPreview)
    }

    @MainActor
    func testStoreDoesNotPublishStaleCareerGraphSyncPreviewAfterPrivacyChangesDuringPreparation() async {
        let now = Date(timeIntervalSince1970: 13_975)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let syncService = DeferredCareerGraphSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerGraphSyncService: syncService,
            now: { now }
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: now)
        store.state.userProfile?.privacy.shareWins = true

        let previewTask = Task {
            await store.prepareCareerGraphSyncPreview()
        }
        for _ in 0..<20 where syncService.pendingContinuation == nil {
            await Task.yield()
        }
        XCTAssertEqual(syncService.requests.count, 1)

        store.updateProfilePrivacy(memoryMode: CareerMemoryMode.off, shareWins: false)
        syncService.resume()
        await previewTask.value

        XCTAssertNil(store.careerGraphSyncPreview)
        XCTAssertFalse(store.isPreparingCareerGraphSyncPreview)
    }

    func testCareerGraphSyncPreviewContentDescribesLocalOnlyPreparedState() {
        let now = Date(timeIntervalSince1970: 14_000)
        let preview = CareerGraphSyncPreview(
            status: .preparedLocally,
            requestedAt: now,
            preparedAt: now,
            documentCount: 6,
            proofUploadCount: 1,
            proofUploadByteCount: 77_000,
            includedPrivateEvidence: true,
            allowsLongTermMemoryWrite: false,
            didContactNetwork: false,
            requiresAuthenticationToSync: true
        )

        let content = CareerGraphSyncPreviewContent(preview: preview)

        XCTAssertEqual(content.title, "Career graph preview ready")
        XCTAssertEqual(content.rows.first { $0.title == "Saved records" }?.value, "6 prepared")
        XCTAssertEqual(content.rows.first { $0.title == "Local files" }?.value, "1 file")
        XCTAssertEqual(content.rows.first { $0.title == "Network" }?.value, "No network contact")
        XCTAssertEqual(content.nextStep, "Sign in will be required before any real account backup.")
        XCTAssertFalse(content.displayText.contains("users/"))
        XCTAssertFalse(content.displayText.contains("private-device-path"))
        XCTAssertFalse(content.displayText.contains("synced"))
        XCTAssertFalse(content.displayText.contains("uploaded"))
    }

    @MainActor
    func testV0AIWorkflowContractsExposeOnlyNarrowV0Jobs() async throws {
        XCTAssertEqual(V0AIWorkflowKind.allCases, [
            .cookedDiagnostic,
            .questPlan,
            .proofQualityCheck,
            .progressSummary
        ])

        let service: any V0AIWorkflowServicing = LocalMockV0AIWorkflowService()
        let requestTime = Date(timeIntervalSince1970: 13_000)
        let diagnostic = try await service.generateDiagnostic(
            V0DiagnosticRequest(goal: goal, requestedAt: requestTime)
        )
        let plan = try await service.generateQuestPlan(
            V0QuestPlanRequest(
                goal: goal,
                diagnostic: diagnostic.diagnostic,
                requestedAt: requestTime
            )
        )

        XCTAssertEqual(diagnostic.run.kind, .cookedDiagnostic)
        XCTAssertEqual(diagnostic.run.providerRoute, .localMock)
        XCTAssertEqual(diagnostic.diagnostic.label, "Medium Cooked")
        XCTAssertEqual(plan.run.kind, .questPlan)
        XCTAssertEqual(plan.quests.count, 7)
        XCTAssertEqual(plan.quests.first?.status, .available)
    }

    func testV0AIWorkflowRequestUsesStructuredSafetyAndPrivacyContext() throws {
        var state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 14_000))
        state.userProfile?.privacy.memoryMode = .off
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: Date(timeIntervalSince1970: 14_000))
        let proof = ProofSubmission(
            kind: .proof,
            text: "I mapped the role requirements into a small artifact plan.",
            submittedAt: Date(timeIntervalSince1970: 14_100)
        )

        let request = V0ProofReviewRequest(
            state: state,
            proof: proof,
            requestedAt: Date(timeIntervalSince1970: 14_200)
        )

        XCTAssertEqual(request.schemaVersion, 1)
        XCTAssertEqual(request.questID, state.currentQuest?.id)
        XCTAssertEqual(request.targetRoleTitle, goal.targetRole)
        XCTAssertEqual(request.privacy.memoryMode, .off)
        XCTAssertFalse(request.allowsLongTermMemoryWrite)
        XCTAssertTrue(request.safetyRules.hardBannedClaims.contains("fake employers"))
        XCTAssertEqual(request.context.currentQuest?.id, state.currentQuest?.id)
        XCTAssertEqual(request.context.progress.proofCount, state.progress.proofCount)
        XCTAssertFalse(String(describing: request).contains("OpenLARPState"))
        XCTAssertFalse(String(describing: request).contains("sk-"))
        XCTAssertFalse(String(describing: request).localizedCaseInsensitiveContains("api key"))
    }

    func testV0AIWorkflowContextSnapshotIncludesSafeOutcomeContextWithoutPrivateNotes() throws {
        let now = Date(timeIntervalSince1970: 14_300)
        let outcome = CareerOutcomeRecord(
            id: UUID(uuidString: "B9B9B9B9-B9B9-B9B9-B9B9-B9B9B9B9B9B9")!,
            kind: .interview,
            title: "Private recruiter screen title",
            organizationName: "Example Labs",
            note: "Sensitive recruiter detail must not enter the narrow agent context.",
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )
        var deletedOutcome = outcome
        deletedOutcome.id = UUID(uuidString: "BABABABA-BABA-BABA-BABA-BABABABABABA")!
        deletedOutcome.deletedAt = now.addingTimeInterval(60)
        deletedOutcome.updatedAt = now.addingTimeInterval(60)
        var state = OpenLARPEngine.confirmGoal(goal, now: now)
        state.outcomeLog = [outcome, deletedOutcome]

        let request = V0ProgressSummaryRequest(
            state: state,
            requestedAt: now.addingTimeInterval(120)
        )

        XCTAssertEqual(request.context.outcomes.activeOutcomeCount, 1)
        XCTAssertEqual(request.context.outcomes.latestOutcomeKind, .interview)
        XCTAssertEqual(request.context.outcomes.latestOutcomeOccurredAt, now)
        XCTAssertEqual(request.context.outcomes.recentOutcomeKinds, [.interview])
        XCTAssertFalse(String(describing: request.context.outcomes).contains("Sensitive recruiter detail"))
        XCTAssertFalse(String(describing: request.context.outcomes).contains("Private recruiter screen title"))
    }

    @MainActor
    func testV0AIWorkflowFallbackReturnsLocalMockOutputWhenPrimaryThrows() async throws {
        let fallback = FallbackV0AIWorkflowService(
            primary: ThrowingV0AIWorkflowService(),
            fallback: LocalMockV0AIWorkflowService()
        )
        let response = try await fallback.generateDiagnostic(
            V0DiagnosticRequest(
                goal: goal,
                requestedAt: Date(timeIntervalSince1970: 15_000)
            )
        )

        XCTAssertEqual(response.diagnostic.label, "Medium Cooked")
        XCTAssertEqual(response.run.providerRoute, .localMock)
        XCTAssertTrue(response.run.usedFallback)
        XCTAssertEqual(response.run.kind, .cookedDiagnostic)
    }

    @MainActor
    func testStorePersistsAIWorkflowAuditRunsForGoalSetupAndProofCheck() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        await store.confirmGoal(goal)

        XCTAssertEqual(store.state.aiWorkflowRuns.map(\.kind), [
            .cookedDiagnostic,
            .questPlan
        ])
        XCTAssertEqual(store.state.aiWorkflowRuns.map(\.providerRoute), [
            .localMock,
            .localMock
        ])
        XCTAssertTrue(store.state.aiWorkflowRuns.allSatisfy { !$0.usedFallback })
        XCTAssertTrue(store.state.aiWorkflowRuns.allSatisfy { $0.failureSummary == nil })

        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I mapped target-role requirements into a concrete proof artifact.",
            link: "https://example.com/proof"
        )

        XCTAssertEqual(store.state.aiWorkflowRuns.map(\.kind), [
            .cookedDiagnostic,
            .questPlan,
            .proofQualityCheck
        ])

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.aiWorkflowRuns, store.state.aiWorkflowRuns)
        XCTAssertEqual(reloaded.aiWorkflowRuns.last?.kind, .proofQualityCheck)
        XCTAssertFalse(String(describing: reloaded.aiWorkflowRuns).contains("target-role requirements"))
        XCTAssertFalse(String(describing: reloaded.aiWorkflowRuns).contains("example.com/proof"))
    }

    @MainActor
    func testStoreRecordsFallbackAIWorkflowAuditWithoutPrivateErrorDetails() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            aiWorkflowService: FallbackV0AIWorkflowService(
                primary: SensitiveThrowingV0AIWorkflowService(),
                fallback: LocalMockV0AIWorkflowService()
            )
        )

        await store.confirmGoal(goal)

        XCTAssertEqual(store.state.aiWorkflowRuns.map(\.kind), [
            .cookedDiagnostic,
            .questPlan
        ])
        XCTAssertTrue(store.state.aiWorkflowRuns.allSatisfy(\.usedFallback))
        XCTAssertEqual(Set(store.state.aiWorkflowRuns.compactMap(\.failureSummary)), [
            "Primary workflow failed; local fallback handled this run."
        ])

        let encodedRuns = String(
            decoding: try JSONEncoder().encode(store.state.aiWorkflowRuns),
            as: UTF8.self
        )
        XCTAssertFalse(encodedRuns.contains("langqi@example.com"))
        XCTAssertFalse(encodedRuns.contains("sk-test-secret"))
        XCTAssertFalse(encodedRuns.contains("private-device-path"))
        XCTAssertFalse(encodedRuns.localizedCaseInsensitiveContains("api key"))
    }

    func testLegacyStateWithoutAIWorkflowRunsDecodesWithEmptyAuditTrail() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 15_250))
        let encoded = try encoder.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "aiWorkflowRuns")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.aiWorkflowRuns, [])
    }

    func testMalformedAIWorkflowRunsAreDroppedWithoutLosingState() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var original = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 15_300))
        original.aiWorkflowRuns = [
            AIWorkflowAuditRecord(
                kind: .cookedDiagnostic,
                providerRoute: .localMock,
                requestedAt: Date(timeIntervalSince1970: 15_300),
                completedAt: Date(timeIntervalSince1970: 15_301)
            )
        ]
        let encoded = try encoder.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["aiWorkflowRuns"] = [
            [
                "schemaVersion": 1,
                "kind": "cookedDiagnostic",
                "providerRoute": "localMock",
                "requestedAt": "1970-01-01T04:15:00Z",
                "completedAt": "1970-01-01T04:15:01Z",
                "usedFallback": false
            ],
            [
                "schemaVersion": 1,
                "kind": "futureWorkflowKind",
                "providerRoute": "localMock",
                "requestedAt": "1970-01-01T04:15:00Z",
                "completedAt": "1970-01-01T04:15:01Z",
                "usedFallback": false
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OpenLARPState.self, from: data)

        XCTAssertEqual(decoded.goal, original.goal)
        XCTAssertEqual(decoded.aiWorkflowRuns.count, 1)
        XCTAssertEqual(decoded.aiWorkflowRuns.first?.kind, .cookedDiagnostic)
    }

    func testAIWorkflowAuditRecordsUseStableUniqueIDsForSameSecondRuns() throws {
        let timestamp = Date(timeIntervalSince1970: 15_400.9)
        let first = AIWorkflowAuditRecord(
            kind: .proofQualityCheck,
            providerRoute: .localMock,
            requestedAt: timestamp,
            completedAt: timestamp
        )
        let second = AIWorkflowAuditRecord(
            kind: .proofQualityCheck,
            providerRoute: .localMock,
            requestedAt: timestamp,
            completedAt: timestamp
        )

        XCTAssertNotEqual(first.id, second.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode([first, second])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([AIWorkflowAuditRecord].self, from: encoded)

        XCTAssertEqual(decoded.map(\.id), [first.id, second.id])
    }

    @MainActor
    func testStorePersistsProofAuditWhenProofResponseBecomesStale() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let service = StateChangingProofReviewService()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            aiWorkflowService: service
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let auditCountBeforeProof = store.state.aiWorkflowRuns.count
        service.onReviewProof = {
            var replacementState = OpenLARPEngine.confirmGoal(
                self.goal,
                now: Date(timeIntervalSince1970: 15_450)
            )
            replacementState.aiWorkflowRuns = store.state.aiWorkflowRuns
            store.state = replacementState
        }

        await store.checkProof(
            kind: .proof,
            text: "This stale response should not attach proof to the new quest.",
            link: "https://example.com/stale-proof"
        )

        XCTAssertEqual(store.state.aiWorkflowRuns.count, auditCountBeforeProof + 1)
        XCTAssertEqual(store.state.aiWorkflowRuns.last?.kind, .proofQualityCheck)
        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.pendingQualityResult)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.aiWorkflowRuns, store.state.aiWorkflowRuns)
    }

    func testBackendEventRecordCreatesPrivacySafeOutboxReceipt() throws {
        let timestamp = Date(timeIntervalSince1970: 15_500)
        let proofID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let privateRole = "/Users/langqi/private/sk-test-secret-api-key.txt"

        let event = BackendEventRecord(
            kind: .proofReviewed,
            ownerUserID: "local_user",
            occurredAt: timestamp,
            entityID: proofID.uuidString,
            summary: BackendEventSummary(
                targetRoleTitle: privateRole,
                proofID: proofID,
                readinessOverall: 49,
                proofCount: 1,
                qualityAccepted: true,
                qualityScore: 82
            )
        )

        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.syncStatus, .pending)
        XCTAssertEqual(event.retryCount, 0)
        XCTAssertEqual(event.idempotencyKey, "local_user-proofReviewed-\(proofID.uuidString)")
        XCTAssertEqual(event.summary.targetRoleTitle, "career goal")
        XCTAssertEqual(event.summary.proofID, proofID)
        XCTAssertEqual(event.summary.readinessOverall, 49)
        XCTAssertTrue(event.summary.qualityAccepted ?? false)
        XCTAssertEqual(event.summary.qualityScore, 82)

        let encoded = String(
            decoding: try JSONEncoder.openLARPPersistence.encode(event),
            as: UTF8.self
        )
        XCTAssertFalse(encoded.contains("/Users"))
        XCTAssertFalse(encoded.contains("sk-test-secret"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(encoded.contains(".txt"))
    }

    @MainActor
    func testStorePersistsBackendEventJournalForSyncableActionsWithoutPrivatePayload() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let syncService = RecordingCareerGraphSyncService()
        let attachment = ProofAttachment(
            id: UUID(uuidString: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD")!,
            fileName: "local-private-proof.png",
            originalFileName: "secret-screenshot.png",
            contentType: "image/png",
            byteCount: 40_000,
            createdAt: Date(timeIntervalSince1970: 15_650),
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            careerGraphSyncService: syncService,
            now: { Date(timeIntervalSince1970: 15_600) }
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "Private proof text with langqi@example.com and sk-test-secret details.",
            link: "https://private.example.com/proof",
            attachments: [attachment]
        )
        store.claimPendingQualityResult()
        store.logOutcome(
            kind: .interview,
            title: "Private recruiter screen",
            organizationName: "Example Labs",
            note: "Sensitive recruiter detail should not enter the backend journal.",
            occurredAt: Date(timeIntervalSince1970: 15_600)
        )
        store.updateProfilePrivacy(memoryMode: .cloudReady, shareWins: true)
        await store.prepareCareerGraphSyncPreview()

        XCTAssertEqual(store.state.backendEvents.map(\.kind), [
            .goalConfirmed,
            .questStarted,
            .proofReviewed,
            .proofClaimed,
            .outcomeLogged,
            .privacyUpdated,
            .syncPreviewPrepared
        ])
        XCTAssertTrue(store.state.backendEvents.allSatisfy { $0.syncStatus == .pending })
        XCTAssertEqual(Set(store.state.backendEvents.map(\.idempotencyKey)).count, store.state.backendEvents.count)
        XCTAssertEqual(store.state.backendEvents.first?.summary.targetRoleTitle, goal.targetRole)
        XCTAssertEqual(store.state.backendEvents.first { $0.kind == .proofClaimed }?.summary.proofCount, 1)
        XCTAssertEqual(store.state.backendEvents.first { $0.kind == .outcomeLogged }?.summary.outcomeKind, .interview)
        XCTAssertEqual(store.state.backendEvents.first { $0.kind == .privacyUpdated }?.summary.memoryMode, .cloudReady)
        XCTAssertEqual(store.state.backendEvents.first { $0.kind == .syncPreviewPrepared }?.summary.documentCount, store.careerGraphSyncPreview?.documentCount)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)

        let encodedJournal = String(
            decoding: try JSONEncoder.openLARPPersistence.encode(reloaded.backendEvents),
            as: UTF8.self
        )
        XCTAssertFalse(encodedJournal.contains("Private proof text"))
        XCTAssertFalse(encodedJournal.contains("langqi@example.com"))
        XCTAssertFalse(encodedJournal.contains("private.example.com"))
        XCTAssertFalse(encodedJournal.contains("secret-screenshot"))
        XCTAssertFalse(encodedJournal.contains("private-device-path"))
        XCTAssertFalse(encodedJournal.contains("Sensitive recruiter detail"))
        XCTAssertFalse(encodedJournal.contains("sk-test-secret"))
    }

    @MainActor
    func testRepeatedPrivacyUpdatesCreateDistinctBackendEvents() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        var clock = Date(timeIntervalSince1970: 15_625)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { clock }
        )

        await store.confirmGoal(goal)
        store.updateProfilePrivacy(memoryMode: .cloudReady, shareWins: false)
        clock = clock.addingTimeInterval(1)
        store.updateProfilePrivacy(memoryMode: .localOnly, shareWins: true)

        let privacyEvents = store.state.backendEvents.filter { $0.kind == .privacyUpdated }
        XCTAssertEqual(privacyEvents.count, 2)
        XCTAssertEqual(Set(privacyEvents.map(\.idempotencyKey)).count, 2)
        XCTAssertEqual(privacyEvents.map(\.summary.memoryMode), [.cloudReady, .localOnly])
        XCTAssertEqual(privacyEvents.map(\.summary.shareWins), [false, true])

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    @MainActor
    func testStoreJournalsOutcomeUpdateAndDeleteWithoutPrivatePayload() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        var clock = Date(timeIntervalSince1970: 15_640)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            now: { clock }
        )

        await store.confirmGoal(goal)
        store.logOutcome(
            kind: .applied,
            title: "Applied with private referral note",
            organizationName: "Private Example Labs",
            note: "Recruiter email langqi@example.com and token sk-test-secret",
            occurredAt: clock,
            isPrivate: true
        )
        let outcomeID = try XCTUnwrap(store.state.outcomeLog.first?.id)
        clock = clock.addingTimeInterval(1)
        store.updateOutcome(
            id: outcomeID,
            kind: .interview,
            title: "Interview with private.example.com",
            organizationName: "private.example.com",
            note: "Private device path /Users/langqi/private-outcome-note.md",
            occurredAt: clock,
            isPrivate: false
        )
        clock = clock.addingTimeInterval(1)
        store.deleteOutcome(id: outcomeID)

        let outcomeEvents = store.state.backendEvents.filter {
            [.outcomeLogged, .outcomeUpdated, .outcomeDeleted].contains($0.kind)
        }
        XCTAssertEqual(outcomeEvents.map(\.kind), [.outcomeLogged, .outcomeUpdated, .outcomeDeleted])
        XCTAssertEqual(Set(outcomeEvents.map(\.idempotencyKey)).count, 3)
        XCTAssertEqual(Set(outcomeEvents.compactMap { $0.summary.outcomeID }), [outcomeID])
        XCTAssertEqual(outcomeEvents.compactMap { $0.summary.outcomeKind }, [.applied, .interview, .interview])

        let encodedJournal = String(
            decoding: try JSONEncoder.openLARPPersistence.encode(store.state.backendEvents),
            as: UTF8.self
        )
        XCTAssertFalse(encodedJournal.contains("Applied with private referral note"))
        XCTAssertFalse(encodedJournal.contains("Private Example Labs"))
        XCTAssertFalse(encodedJournal.contains("langqi@example.com"))
        XCTAssertFalse(encodedJournal.contains("sk-test-secret"))
        XCTAssertFalse(encodedJournal.contains("private.example.com"))
        XCTAssertFalse(encodedJournal.contains("private-outcome-note"))

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    func testBackendEventJournalMigratesLossilyAndPreservesPendingOutboxEvents() throws {
        let now = Date(timeIntervalSince1970: 15_700)
        let encoder = JSONEncoder.openLARPPersistence
        var original = OpenLARPEngine.confirmGoal(goal, now: now)
        original.backendEvents = [
            BackendEventRecord(
                kind: .goalConfirmed,
                ownerUserID: "local_user",
                occurredAt: now,
                entityID: "current-goal",
                summary: BackendEventSummary(targetRoleTitle: goal.targetRole)
            )
        ]
        let encoded = try encoder.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["backendEvents"] = [
            [
                "schemaVersion": 1,
                "id": UUID().uuidString,
                "kind": "goalConfirmed",
                "syncStatus": "pending",
                "ownerUserID": "local_user",
                "idempotencyKey": "local_user-goalConfirmed-current-goal",
                "occurredAt": "1970-01-01T04:21:40Z",
                "retryCount": 0,
                "summary": [
                    "targetRoleTitle": "iOS engineering internship"
                ]
            ],
            [
                "schemaVersion": 1,
                "id": UUID().uuidString,
                "kind": "futureBackendEvent",
                "syncStatus": "pending",
                "ownerUserID": "local_user",
                "idempotencyKey": "local_user-futureBackendEvent-current-goal",
                "occurredAt": "1970-01-01T04:21:40Z",
                "retryCount": 0,
                "summary": [:]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder.openLARPPersistence
        let decoded = try decoder.decode(OpenLARPState.self, from: data)

        XCTAssertEqual(decoded.goal, original.goal)
        XCTAssertEqual(decoded.backendEvents.count, 1)
        XCTAssertEqual(decoded.backendEvents.first?.kind, .goalConfirmed)

        var cappedState = OpenLARPState.empty
        for index in 0..<(BackendEventRecord.maxStoredCount + 12) {
            cappedState.recordBackendEvent(
                BackendEventRecord(
                    kind: .questStarted,
                    ownerUserID: "local_user",
                    occurredAt: now.addingTimeInterval(TimeInterval(index)),
                    entityID: "quest-\(index)",
                    summary: BackendEventSummary(questDay: index)
                )
            )
        }

        XCTAssertEqual(cappedState.backendEvents.count, BackendEventRecord.maxStoredCount + 12)
        XCTAssertEqual(cappedState.backendEvents.first?.summary.questDay, 0)
        XCTAssertEqual(cappedState.backendEvents.last?.summary.questDay, BackendEventRecord.maxStoredCount + 11)

        for index in 0..<(BackendEventRecord.maxStoredCount + 12) {
            cappedState.recordBackendEvent(
                BackendEventRecord(
                    kind: .syncPreviewPrepared,
                    syncStatus: .acknowledged,
                    ownerUserID: "local_user",
                    occurredAt: now.addingTimeInterval(TimeInterval(index)),
                    entityID: "preview-\(index)",
                    summary: BackendEventSummary(documentCount: index)
                )
            )
        }

        let acknowledgedEvents = cappedState.backendEvents.filter { $0.syncStatus == .acknowledged }
        let pendingEvents = cappedState.backendEvents.filter { $0.syncStatus == .pending }
        XCTAssertEqual(acknowledgedEvents.count, BackendEventRecord.maxStoredCount)
        XCTAssertEqual(acknowledgedEvents.first?.summary.documentCount, 12)
        XCTAssertEqual(acknowledgedEvents.last?.summary.documentCount, BackendEventRecord.maxStoredCount + 11)
        XCTAssertEqual(pendingEvents.count, BackendEventRecord.maxStoredCount + 12)
        XCTAssertEqual(pendingEvents.first?.summary.questDay, 0)
    }

    func testLegacyStateWithoutBackendEventsDecodesWithEmptyOutbox() throws {
        let encoder = JSONEncoder.openLARPPersistence
        let original = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 15_760))
        let encoded = try encoder.encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "backendEvents")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.backendEvents, [])
    }

    @MainActor
    func testStoreDoesNotJournalProofReviewWhenProofResponseBecomesStale() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let service = StateChangingProofReviewService()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            aiWorkflowService: service
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let backendEventKindsBeforeProof = store.state.backendEvents.map(\.kind)
        service.onReviewProof = {
            var replacementState = OpenLARPEngine.confirmGoal(
                self.goal,
                now: Date(timeIntervalSince1970: 15_780)
            )
            replacementState.aiWorkflowRuns = store.state.aiWorkflowRuns
            replacementState.backendEvents = store.state.backendEvents
            store.state = replacementState
        }

        await store.checkProof(
            kind: .proof,
            text: "This stale response should not create a backend proof event.",
            link: "https://example.com/stale-proof"
        )

        XCTAssertEqual(store.state.backendEvents.map(\.kind), backendEventKindsBeforeProof)
        XCTAssertFalse(store.state.backendEvents.map(\.kind).contains(.proofReviewed))
        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.pendingQualityResult)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    @MainActor
    func testStoreSyncsPendingBackendEventsThroughBackendServiceAndPersistsReceipts() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let syncService = DeferredBackendEventSyncService()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            now: { Date(timeIntervalSince1970: 15_820) }
        )

        await store.confirmGoal(goal)
        let eventID = try XCTUnwrap(store.state.backendEvents.first?.id)

        let syncTask = Task { await store.syncBackendEvents() }
        for _ in 0..<20 where syncService.pendingContinuation == nil {
            await Task.yield()
        }

        XCTAssertEqual(syncService.requests.count, 1)
        XCTAssertEqual(syncService.requests.first?.events.map(\.id), [eventID])
        XCTAssertEqual(syncService.requests.first?.events.first?.syncStatus, .inFlight)
        XCTAssertEqual(try persistence.load().backendEvents.first?.syncStatus, .inFlight)

        syncService.resume()
        await syncTask.value

        let syncedEvent = try XCTUnwrap(store.state.backendEvents.first)
        XCTAssertEqual(syncedEvent.id, eventID)
        XCTAssertEqual(syncedEvent.syncStatus, .acknowledged)
        XCTAssertEqual(syncedEvent.lastAttemptAt, Date(timeIntervalSince1970: 15_820))
        XCTAssertEqual(syncedEvent.retryCount, 0)
        XCTAssertNil(syncedEvent.failureSummary)
        XCTAssertFalse(store.isSyncingBackendEvents)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    @MainActor
    func testStoreMarksBackendEventsFailedWithSafeRetryStateWhenSyncThrows() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let syncService = RecordingBackendEventSyncService()
        syncService.errorToThrow = SensitiveBackendEventSyncError()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            now: { Date(timeIntervalSince1970: 15_840) }
        )

        await store.confirmGoal(goal)
        await store.syncBackendEvents()

        XCTAssertEqual(syncService.requests.count, 1)
        let failedEvent = try XCTUnwrap(store.state.backendEvents.first)
        XCTAssertEqual(failedEvent.syncStatus, .failed)
        XCTAssertEqual(failedEvent.retryCount, 1)
        XCTAssertEqual(failedEvent.lastAttemptAt, Date(timeIntervalSince1970: 15_840))
        XCTAssertEqual(failedEvent.failureSummary, BackendEventRecord.safeSyncFailureSummary)
        XCTAssertEqual(store.errorMessage, "Backend event sync could not finish. OpenLARP will retry later.")

        let encodedJournal = String(
            decoding: try JSONEncoder.openLARPPersistence.encode(store.state.backendEvents),
            as: UTF8.self
        )
        XCTAssertFalse(encodedJournal.contains("langqi@example.com"))
        XCTAssertFalse(encodedJournal.contains("sk-test-secret"))
        XCTAssertFalse(encodedJournal.contains("private.example.com"))
        XCTAssertFalse(encodedJournal.contains("/Users/langqi"))

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    @MainActor
    func testStoreRetriesFailedAndStaleInFlightEventsWithoutDuplicatingFreshInFlightOrAcknowledged() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let now = Date(timeIntervalSince1970: 15_900)
        let pending = BackendEventRecord(
            kind: .goalConfirmed,
            ownerUserID: "local_user",
            occurredAt: now.addingTimeInterval(-500),
            entityID: "pending",
            summary: BackendEventSummary(targetRoleTitle: goal.targetRole)
        )
        let failedRecent = BackendEventRecord(
            kind: .privacyUpdated,
            syncStatus: .failed,
            ownerUserID: "local_user",
            occurredAt: now.addingTimeInterval(-400),
            entityID: "failed-recent",
            retryCount: 1,
            lastAttemptAt: now.addingTimeInterval(-120),
            failureSummary: "raw failure",
            summary: BackendEventSummary(memoryMode: .cloudReady)
        )
        let failedOld = BackendEventRecord(
            kind: .questStarted,
            syncStatus: .failed,
            ownerUserID: "local_user",
            occurredAt: now.addingTimeInterval(-300),
            entityID: "failed-old",
            retryCount: 1,
            lastAttemptAt: now.addingTimeInterval(-420),
            failureSummary: "raw failure",
            summary: BackendEventSummary(questDay: 1)
        )
        let inFlightRecent = BackendEventRecord(
            kind: .proofReviewed,
            syncStatus: .inFlight,
            ownerUserID: "local_user",
            occurredAt: now.addingTimeInterval(-200),
            entityID: "inflight-recent",
            lastAttemptAt: now.addingTimeInterval(-300),
            summary: BackendEventSummary(qualityAccepted: true)
        )
        let inFlightStale = BackendEventRecord(
            kind: .proofClaimed,
            syncStatus: .inFlight,
            ownerUserID: "local_user",
            occurredAt: now.addingTimeInterval(-100),
            entityID: "inflight-stale",
            lastAttemptAt: now.addingTimeInterval(-1_200),
            summary: BackendEventSummary(proofCount: 1)
        )
        let acknowledged = BackendEventRecord(
            kind: .syncPreviewPrepared,
            syncStatus: .acknowledged,
            ownerUserID: "local_user",
            occurredAt: now,
            entityID: "acknowledged",
            lastAttemptAt: now.addingTimeInterval(-2_000),
            summary: BackendEventSummary(documentCount: 4)
        )
        var state = OpenLARPState.empty
        state.backendEvents = [
            pending,
            failedRecent,
            failedOld,
            inFlightRecent,
            inFlightStale,
            acknowledged
        ]
        try persistence.save(state)
        let syncService = RecordingBackendEventSyncService()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            now: { now }
        )

        await store.syncBackendEvents()

        XCTAssertEqual(syncService.requests.count, 1)
        XCTAssertEqual(syncService.requests.first?.events.map(\.id), [
            pending.id,
            failedOld.id,
            inFlightStale.id
        ])
        XCTAssertEqual(store.state.backendEvents.map(\.syncStatus), [
            .acknowledged,
            .failed,
            .acknowledged,
            .inFlight,
            .acknowledged,
            .acknowledged
        ])
        XCTAssertEqual(store.state.backendEvents[1].retryCount, 1)
        XCTAssertEqual(store.state.backendEvents[3].lastAttemptAt, inFlightRecent.lastAttemptAt)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    @MainActor
    func testConcurrentBackendEventSyncsSendEachEventAtMostOnce() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let syncService = DeferredBackendEventSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            now: { Date(timeIntervalSince1970: 15_940) }
        )

        await store.confirmGoal(goal)
        let firstSync = Task { await store.syncBackendEvents() }
        let secondSync = Task { await store.syncBackendEvents() }
        for _ in 0..<20 where syncService.pendingContinuation == nil {
            await Task.yield()
        }

        XCTAssertEqual(syncService.requests.count, 1)
        syncService.resume()
        await firstSync.value
        await secondSync.value

        XCTAssertEqual(syncService.requests.count, 1)
        XCTAssertEqual(store.state.backendEvents.first?.syncStatus, .acknowledged)
    }

    @MainActor
    func testBackendEventSyncDoesNotContactServiceWhenInFlightClaimCannotPersist() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let syncService = RecordingBackendEventSyncService()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            now: { Date(timeIntervalSince1970: 15_960) }
        )

        await store.confirmGoal(goal)
        let originalEvents = store.state.backendEvents
        try FileManager.default.removeItem(at: directory)
        try "not a directory".write(
            to: directory,
            atomically: true,
            encoding: .utf8
        )

        await store.syncBackendEvents()

        XCTAssertEqual(syncService.requests.count, 0)
        XCTAssertEqual(store.state.backendEvents, originalEvents)
        XCTAssertEqual(store.errorMessage, "Local progress could not be saved.")
    }

    @MainActor
    func testStoreFallsBackToLocalPlanWhenWorkflowReturnsInvalidQuestPlan() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            aiWorkflowService: InvalidPlanV0AIWorkflowService()
        )

        await store.confirmGoal(goal)

        XCTAssertEqual(store.state.diagnostic?.label, "Medium Cooked")
        XCTAssertEqual(store.state.progress.readiness.overall, 42)
        XCTAssertEqual(store.state.plan.count, 7)
        XCTAssertEqual(store.state.currentQuest?.status, .available)
        XCTAssertEqual(store.errorMessage, "OpenLARP built a local plan on this device because the agent service was unavailable.")
    }

    @MainActor
    func testStoreClearsStalePersistedDraftWhenNoQuestIsActive() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        var staleState = OpenLARPEngine.resetGoal(now: Date(timeIntervalSince1970: 16_500))
        staleState.proofDraft = ProofSubmission(kind: .proof, text: "Stale draft", link: "https://example.com")
        staleState.proofDraftQualityResult = QualityCheckResult(
            isAccepted: false,
            qualityScore: 45,
            label: "Needs stronger proof",
            reason: "Old draft",
            improvement: "Add real evidence.",
            xpEarned: 30,
            readinessDelta: 1
        )
        try persistence.save(staleState)

        _ = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        let reloaded = try persistence.load()
        XCTAssertNil(reloaded.proofDraft)
        XCTAssertNil(reloaded.proofDraftQualityResult)
    }

    @MainActor
    func testSkipCurrentQuestDoesNotRunWhileProofCheckIsInFlight() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let currentQuestID = store.state.currentQuest?.id
        store.isProofChecking = true
        store.skipCurrentQuest()

        XCTAssertEqual(store.state.currentQuest?.id, currentQuestID)
        XCTAssertEqual(store.state.currentQuest?.status, .inProgress)
        XCTAssertEqual(store.errorMessage, "Wait for the proof check to finish before skipping today.")
    }

    @MainActor
    func testImproveWeakProofKeepsDraftTextLinkKindAndCurrentQuest() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "Too thin",
            link: "notaurl"
        )

        XCTAssertEqual(store.pendingQualityResult?.label, "Needs stronger proof")
        store.improvePendingProofDraft()

        XCTAssertEqual(store.pendingProof?.kind, .proof)
        XCTAssertEqual(store.pendingProof?.text, "Too thin")
        XCTAssertEqual(store.pendingProof?.link, "notaurl")
        XCTAssertNil(store.pendingQualityResult)
        XCTAssertEqual(store.state.currentQuest?.status, .inProgress)

        let reloaded = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertEqual(reloaded.pendingProof?.kind, .proof)
        XCTAssertEqual(reloaded.pendingProof?.text, "Too thin")
        XCTAssertEqual(reloaded.pendingProof?.link, "notaurl")
        XCTAssertNil(reloaded.pendingQualityResult)
        XCTAssertEqual(reloaded.state.currentQuest?.status, .inProgress)
    }

    @MainActor
    func testImproveWeakProofKeepsDraftAttachmentsOnDisk() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        let attachment = try store.saveProofImage(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            originalFileName: "weak-self-report.png"
        )
        await store.checkProof(
            kind: .selfReport,
            text: "I did something but need to make the evidence stronger.",
            link: "",
            attachments: [attachment]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))
        store.improvePendingProofDraft()

        XCTAssertEqual(store.pendingProof?.attachments, [attachment])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.localURL(for: attachment).path))
        XCTAssertNil(store.pendingQualityResult)

        let reloaded = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertEqual(reloaded.pendingProof?.attachments.first?.id, attachment.id)
        XCTAssertEqual(reloaded.pendingProof?.attachments.first?.localRelativePath, attachment.localRelativePath)
        XCTAssertEqual(reloaded.pendingProof?.attachments.first?.originalFileName, attachment.originalFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reloaded.localURL(for: attachment).path))
        XCTAssertNil(reloaded.pendingQualityResult)
    }

    @MainActor
    func testStoreUpdatesProfilePrivacyAndPersistsAcrossReload() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        await store.confirmGoal(goal)
        store.updateProfilePrivacy(memoryMode: .off, shareWins: false)

        XCTAssertEqual(store.state.userProfile?.privacy.memoryMode, .off)
        XCTAssertEqual(store.state.userProfile?.privacy.shareWins, false)
        XCTAssertEqual(store.state.userProfile?.privacy.requireApprovalForExternalActions, true)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.userProfile?.privacy.memoryMode, .off)
        XCTAssertEqual(reloaded.userProfile?.privacy.shareWins, false)
    }

    @MainActor
    func testResetGoalPreservesProfilePrivacyControls() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        await store.confirmGoal(goal)
        store.updateProfilePrivacy(memoryMode: .off, shareWins: false)
        store.resetGoal()

        XCTAssertTrue(store.state.needsGoalSetup)
        XCTAssertEqual(store.state.userProfile?.privacy.memoryMode, .off)
        XCTAssertEqual(store.state.userProfile?.privacy.shareWins, false)
    }

    @MainActor
    func testReconfirmingGoalPreservesLocalOwnerIdentityForBackendJournal() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )
        let secondGoal = CareerGoal(
            currentStatus: .careerSwitcher,
            targetRole: "AI product analyst",
            timeline: "45 days",
            background: "Former support specialist with SQL coursework and two customer research projects.",
            existingProof: "Support analytics dashboard and customer interview notes",
            confidence: 4,
            biggestBlocker: "I need stronger proof that my analytics work can translate into product roles."
        )

        await store.confirmGoal(goal)
        let originalProfile = try XCTUnwrap(store.state.userProfile)
        let originalOwnerID = BackendUserSession.localOnly(for: store.state).ownerUserID
        store.updateProfilePrivacy(memoryMode: .cloudReady, shareWins: true)
        let updatedPrivacy = try XCTUnwrap(store.state.userProfile?.privacy)
        store.resetGoal()
        await store.confirmGoal(secondGoal)

        let refreshedProfile = try XCTUnwrap(store.state.userProfile)
        XCTAssertEqual(refreshedProfile.id, originalProfile.id)
        XCTAssertEqual(refreshedProfile.createdAt, originalProfile.createdAt)
        XCTAssertEqual(refreshedProfile.privacy, updatedPrivacy)
        XCTAssertEqual(refreshedProfile.segment, secondGoal.currentStatus)
        XCTAssertEqual(refreshedProfile.backgroundSummary, secondGoal.background)
        XCTAssertEqual(store.state.goal, secondGoal)
        XCTAssertTrue(store.state.backendEvents.allSatisfy { $0.ownerUserID == originalOwnerID })

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.userProfile?.id, originalProfile.id)
        XCTAssertTrue(reloaded.backendEvents.allSatisfy { $0.ownerUserID == originalOwnerID })
    }

    func testAppTabsMatchProductSurfaces() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Today", "Map", "Progress", "Agent", "Profile"])
        XCTAssertEqual(AppTab.allCases.map(\.systemImage), ["bolt.fill", "map.fill", "chart.line.uptrend.xyaxis", "sparkles", "person.crop.circle"])
    }

    private func proofRecord(
        id: UUID,
        questID: UUID = UUID(),
        questTitle: String,
        submittedAt: Date
    ) -> ProofRecord {
        ProofRecord(
            id: id,
            questID: questID,
            questTitle: questTitle,
            kind: .proof,
            text: "Saved proof text",
            link: "",
            submittedAt: submittedAt,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 80,
                label: "Strong proof",
                reason: "Concrete enough to count.",
                improvement: "Connect it to a target-role requirement.",
                xpEarned: 100,
                readinessDelta: 6
            )
        )
    }

    private func privacySensitiveCloudState(now: Date) -> OpenLARPState {
        let privateGoal = CareerGoal(
            currentStatus: .student,
            targetRole: "AI product internship",
            timeline: "30 days",
            background: "Private background with langqi@example.com, visa concern, campus office, and sk-test-secret api key notes.",
            existingProof: "Secret Project Falcon, private repo, and https://private.example.com/proof.",
            confidence: 2,
            biggestBlocker: "Confidential blocker with family money stress."
        )
        let attachment = ProofAttachment(
            id: UUID(uuidString: "EBEBEBEB-EBEB-EBEB-EBEB-EBEBEBEBEBEB")!,
            fileName: "proof-upload.png",
            originalFileName: "private-proof-upload.png",
            contentType: "image/png",
            byteCount: 77_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        let proof = ProofRecord(
            id: UUID(uuidString: "ECECECEC-ECEC-ECEC-ECEC-ECECECECECEC")!,
            questID: UUID(uuidString: "EDEDEDED-EDED-EDED-EDED-EDEDEDEDEDED")!,
            questTitle: "Create one tiny proof artifact",
            kind: .proof,
            text: "Sensitive proof text references Secret Project Falcon and should not export unless explicitly allowed.",
            link: "https://private.example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Real artifact",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
        var state = OpenLARPEngine.confirmGoal(privateGoal, now: now)
        state.userProfile?.accountID = "acct_private_123"
        state.userProfile?.email = "langqi@example.com"
        state.userProfile?.backgroundSummary = "Private background with visa concern and campus office details."
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        return state
    }

    private func assertNoPrivateCloudExportLeaks(
        _ json: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let blockedFragments = [
            "langqi@example.com",
            "visa",
            "campus office",
            "Secret Project Falcon",
            "private repo",
            "private.example.com",
            "family money",
            "sk-test-secret",
            "api key",
            "acct_private_123",
            "private-device-path",
            "localRelativePath"
        ]

        for fragment in blockedFragments {
            XCTAssertFalse(
                json.localizedCaseInsensitiveContains(fragment),
                "Cloud export leaked private fragment: \(fragment)",
                file: file,
                line: line
            )
        }
    }

    private func completedFirstQuestState(claimTime: Date) throws -> OpenLARPState {
        var state = OpenLARPEngine.confirmGoal(goal, now: claimTime)
        state = try OpenLARPEngine.startCurrentQuest(in: state, now: claimTime)
        let proof = ProofSubmission(
            kind: .proof,
            text: "I mapped repeated iOS internship requirements, chose one proof-building path, and saved notes that connect the work to a target role.",
            link: "https://example.com/requirements",
            submittedAt: claimTime
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        return try OpenLARPEngine.claim(
            result,
            proof: proof,
            in: state,
            now: claimTime,
            calendar: testCalendar
        )
    }

    private func localDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        testCalendar.date(from: DateComponents(
            timeZone: testCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}

private struct LegacyCloudCareerGraphSnapshotPayload: Codable {
    var schemaVersion: Int
    var ownerUserID: String
    var generatedAt: Date
    var userProfile: CloudUserProfileDocument?
    var goal: CareerGoal?
    var targetRoles: [CloudTargetRoleDocument]
    var proofRecords: [CloudProofRecordDocument]
    var outcomes: [CloudCareerOutcomeDocument]
    var readinessSnapshots: [CloudReadinessSnapshotDocument]
    var currentReadiness: ReadinessMetrics
    var policy: CloudExportPolicy
}

private struct ThrowingV0AIWorkflowService: V0AIWorkflowServicing {
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        throw TestWorkflowError.expectedFailure
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        throw TestWorkflowError.expectedFailure
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        throw TestWorkflowError.expectedFailure
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        throw TestWorkflowError.expectedFailure
    }
}

private struct SensitiveThrowingV0AIWorkflowService: V0AIWorkflowServicing {
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        throw SensitiveWorkflowError()
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        throw SensitiveWorkflowError()
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        throw SensitiveWorkflowError()
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        throw SensitiveWorkflowError()
    }
}

private struct SensitiveWorkflowError: Error, CustomStringConvertible {
    var description: String {
        "backend failure for langqi@example.com with sk-test-secret api key at ProofAttachments/private-device-path.png"
    }
}

private struct InvalidPlanV0AIWorkflowService: V0AIWorkflowServicing {
    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        V0DiagnosticResponse(
            run: V0AIWorkflowRun(
                kind: .cookedDiagnostic,
                providerRoute: .localMock,
                requestedAt: request.requestedAt
            ),
            diagnostic: CookedDiagnostic(
                score: 91,
                label: "Backend Diagnostic",
                mainGap: "Backend returned a diagnostic.",
                strongestSignal: "A real proof signal.",
                fastestFix: "Keep building proof.",
                readinessBaseline: 64
            )
        )
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        V0QuestPlanResponse(
            run: V0AIWorkflowRun(
                kind: .questPlan,
                providerRoute: .localMock,
                requestedAt: request.requestedAt
            ),
            quests: []
        )
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        try await LocalMockV0AIWorkflowService().reviewProof(request)
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        try await LocalMockV0AIWorkflowService().summarizeProgress(request)
    }
}

private final class StateChangingProofReviewService: V0AIWorkflowServicing {
    var onReviewProof: (() -> Void)?

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        try await LocalMockV0AIWorkflowService().generateDiagnostic(request)
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        try await LocalMockV0AIWorkflowService().generateQuestPlan(request)
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        let response = try await LocalMockV0AIWorkflowService().reviewProof(request)
        onReviewProof?()
        return response
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        try await LocalMockV0AIWorkflowService().summarizeProgress(request)
    }
}

private enum TestWorkflowError: Error {
    case expectedFailure
}

private struct SensitiveBackendEventSyncError: LocalizedError {
    var errorDescription: String? {
        "Sync failed for langqi@example.com with sk-test-secret at https://private.example.com/proof from /Users/langqi/private.txt"
    }
}

private final class RecordingBackendEventSyncService: BackendEventSyncServicing {
    var requests: [BackendEventSyncRequest] = []
    var errorToThrow: Error?
    var receipts: [BackendEventSyncReceipt]?

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        requests.append(request)
        if let errorToThrow {
            throw errorToThrow
        }
        return BackendEventSyncResult(
            request: request,
            completedAt: request.requestedAt,
            didContactNetwork: false,
            receipts: receipts ?? request.events.map {
                BackendEventSyncReceipt(
                    eventID: $0.id,
                    idempotencyKey: $0.idempotencyKey,
                    status: .acknowledged,
                    acceptedAt: request.requestedAt
                )
            }
        )
    }
}

private final class DeferredBackendEventSyncService: BackendEventSyncServicing {
    var requests: [BackendEventSyncRequest] = []
    var pendingContinuation: CheckedContinuation<Void, Never>?

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        requests.append(request)
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
        return BackendEventSyncResult(
            request: request,
            completedAt: request.requestedAt,
            didContactNetwork: false,
            receipts: request.events.map {
                BackendEventSyncReceipt(
                    eventID: $0.id,
                    idempotencyKey: $0.idempotencyKey,
                    status: .acknowledged,
                    acceptedAt: request.requestedAt
                )
            }
        )
    }

    func resume() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }
}

private final class RecordingCareerGraphSyncService: CareerGraphSyncServicing, @unchecked Sendable {
    var requests: [CareerGraphSyncPreparationRequest] = []
    var shouldThrow = false

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        requests.append(request)
        if shouldThrow {
            throw TestWorkflowError.expectedFailure
        }
        return try await LocalMockCareerGraphSyncService().prepareSync(request)
    }
}

private final class DeferredCareerGraphSyncService: CareerGraphSyncServicing, @unchecked Sendable {
    var requests: [CareerGraphSyncPreparationRequest] = []
    var pendingContinuation: CheckedContinuation<Void, Never>?

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        requests.append(request)
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
        return try await LocalMockCareerGraphSyncService().prepareSync(request)
    }

    func resume() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }
}
