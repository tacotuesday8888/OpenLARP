import XCTest
@testable import OpenLARP

final class QuestJourneyContentTests: XCTestCase {
    func testFirstChapterShowsReviewProgressAndLockedAdaptiveSecondChapter() {
        let quests = makeQuests(days: 1...7, completedThrough: 3)
        let sprint = CareerSprintState(
            targetRoleTitle: "iOS Engineer",
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            initialReadiness: .baseline
        )

        let content = QuestJourneyContent(plan: quests, sprint: sprint)

        XCTAssertEqual(content.chapters.count, 2)
        XCTAssertEqual(content.chapters[0].questRangeText, "Days 1–7")
        XCTAssertEqual(content.chapters[0].status, .active)
        XCTAssertEqual(content.chapters[0].completedQuestCount, 3)
        XCTAssertEqual(content.chapters[0].focusGaps, [.proofStrength, .networking])
        XCTAssertEqual(content.chapters[0].milestone.state, .locked)
        XCTAssertEqual(content.chapters[0].milestone.detail, "4 actions until your level-up review")

        XCTAssertEqual(content.chapters[1].questRangeText, "Days 8–14")
        XCTAssertEqual(content.chapters[1].status, .locked)
        XCTAssertTrue(content.chapters[1].quests.isEmpty)
        XCTAssertEqual(content.chapters[1].milestone.state, .locked)
        XCTAssertEqual(content.chapters[1].milestone.detail, "Unlocks after your Day 7 review")
        XCTAssertEqual(
            content.chapters[1].lockedExplanation,
            "OpenLARP adapts these seven actions after your Day 7 review."
        )
    }

    func testDaySevenReviewReadyStateIsDistinctFromCompletedReview() {
        let quests = makeQuests(days: 1...7, completedThrough: 7)
        let sprint = CareerSprintState(
            targetRoleTitle: "iOS Engineer",
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            initialReadiness: .baseline,
            phase: .chapterOneReview
        )

        let content = QuestJourneyContent(plan: quests, sprint: sprint)

        XCTAssertEqual(content.chapters[0].status, .reviewReady)
        XCTAssertEqual(content.chapters[0].milestone.state, .ready)
        XCTAssertEqual(content.chapters[0].milestone.detail, "Ready now · See what changed before Chapter Two")
    }

    func testSecondChapterUsesGeneratedQuestsAndCompletedCheckpointReports() {
        let quests = makeQuests(days: 1...14, completedThrough: 9)
        let daySevenReport = makeReport(day: 7, completedQuestCount: 7)
        let sprint = CareerSprintState(
            targetRoleTitle: "iOS Engineer",
            startedAt: Date(timeIntervalSince1970: 1_900_000_000),
            initialReadiness: .baseline,
            phase: .chapterTwo,
            reports: [daySevenReport]
        )

        let content = QuestJourneyContent(plan: quests, sprint: sprint)

        XCTAssertEqual(content.chapters[0].status, .complete)
        XCTAssertEqual(content.chapters[0].milestone.state, .complete)
        XCTAssertEqual(content.chapters[1].status, .active)
        XCTAssertEqual(content.chapters[1].completedQuestCount, 2)
        XCTAssertEqual(content.chapters[1].quests.map(\.day), Array(8...14))
        XCTAssertEqual(content.chapters[1].focusGaps, [.networking, .proofStrength])
        XCTAssertEqual(content.chapters[1].milestone.detail, "5 actions until your sprint review")
    }

    private func makeQuests(days: ClosedRange<Int>, completedThrough: Int) -> [Quest] {
        days.map { day in
            Quest(
                day: day,
                title: "Action \(day)",
                purpose: "Create truthful career progress.",
                gap: day.isMultiple(of: 2) ? .networking : .proofStrength,
                proofRequired: "A short proof note.",
                xpReward: 120,
                status: day <= completedThrough ? .completed : (day == completedThrough + 1 ? .available : .locked)
            )
        }
    }

    private func makeReport(day: Int, completedQuestCount: Int) -> CareerSprintCheckpointReport {
        CareerSprintCheckpointReport(
            id: UUID(),
            sprintID: UUID(),
            checkpointDay: day,
            completedQuestCount: completedQuestCount,
            proofCount: completedQuestCount,
            outcomeCount: 0,
            startReadiness: .baseline,
            endReadiness: .baseline,
            readinessDelta: 0,
            summary: "Grounded progress summary.",
            nextFocus: "Keep building real evidence.",
            strongestProofTitle: nil,
            providerRoute: .localMock,
            usedFallback: true,
            createdAt: Date(timeIntervalSince1970: 1_900_000_100)
        )
    }
}
