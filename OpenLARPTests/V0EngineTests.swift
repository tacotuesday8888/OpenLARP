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
    func testStoreSkipInProgressQuestClearsPendingProofAndQualityResult() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let skipTime = localDate(year: 2026, month: 5, day: 31, hour: 10)
        let store = OpenLARPStore(
            persistence: persistence,
            now: { skipTime },
            calendar: testCalendar
        )

        store.confirmGoal(goal)
        store.startCurrentQuest()
        store.checkProof(
            kind: .proof,
            text: "I mapped repeated iOS internship requirements, chose one proof-building path, and saved notes that connect the work to a target role.",
            link: "https://example.com/requirements"
        )

        XCTAssertNotNil(store.pendingProof)
        XCTAssertNotNil(store.pendingQualityResult)

        store.skipCurrentQuest()

        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.pendingQualityResult)
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

    func testDesignCatalogMatchesHTMLReferenceScreensAndTabs() {
        XCTAssertEqual(AppTab.allCases.map(\.title), ["Path", "Quest", "Cooked", "Proof", "Stats"])
        XCTAssertEqual(
            OpenLARPDesignCatalog.screenTitles,
            [
                "Set your goal",
                "The roast report",
                "Proof Sprint",
                "Public proof",
                "Add evidence",
                "Review result",
                "Comeback Map",
                "Less cooked",
                "Evidence bank",
                "Not over",
                "Career Hub",
                "Settings"
            ]
        )
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
