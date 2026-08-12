import Foundation

enum QuestJourneyChapterStatus: Equatable {
    case active
    case locked
    case reviewReady
    case complete
}

enum QuestJourneyMilestoneState: Equatable {
    case locked
    case ready
    case complete
}

struct QuestJourneyMilestone: Equatable {
    var title: String
    var detail: String
    var state: QuestJourneyMilestoneState
}

struct QuestJourneyChapter: Equatable, Identifiable {
    var id: Int { number }

    var number: Int
    var questRangeText: String
    var title: String
    var subtitle: String
    var quests: [Quest]
    var focusGaps: [CareerGap]
    var completedQuestCount: Int
    var totalQuestCount: Int
    var status: QuestJourneyChapterStatus
    var milestone: QuestJourneyMilestone
    var lockedExplanation: String?
}

struct QuestJourneyContent: Equatable {
    var chapters: [QuestJourneyChapter]

    init(plan: [Quest], sprint: CareerSprintState?) {
        let orderedPlan = plan.sorted { $0.day < $1.day }
        let firstChapterQuests = orderedPlan.filter { (1...7).contains($0.day) }
        let secondChapterQuests = orderedPlan.filter { (8...14).contains($0.day) }
        let completedReviewDays = Set(sprint?.reports.map(\.checkpointDay) ?? [])

        chapters = [
            Self.chapter(
                number: 1,
                questRangeText: "Days 1–7",
                title: "Build credible proof",
                subtitle: "Turn your real experience into evidence you can use.",
                quests: firstChapterQuests,
                reviewDay: 7,
                completedReviewDays: completedReviewDays,
                phase: sprint?.phase,
                lockedExplanation: nil
            ),
            Self.chapter(
                number: 2,
                questRangeText: "Days 8–14",
                title: "Apply the proof",
                subtitle: "Use what worked in focused outreach, applications, and next-step actions.",
                quests: secondChapterQuests,
                reviewDay: 14,
                completedReviewDays: completedReviewDays,
                phase: sprint?.phase,
                lockedExplanation: secondChapterQuests.isEmpty
                    ? "OpenLARP adapts these seven actions after your Day 7 review."
                    : nil
            )
        ]
    }

    private static func chapter(
        number: Int,
        questRangeText: String,
        title: String,
        subtitle: String,
        quests: [Quest],
        reviewDay: Int,
        completedReviewDays: Set<Int>,
        phase: CareerSprintPhase?,
        lockedExplanation: String?
    ) -> QuestJourneyChapter {
        let completedCount = quests.filter { $0.status == .completed }.count
        let reviewComplete = completedReviewDays.contains(reviewDay) || (reviewDay == 14 && phase == .completed)
        let reviewReady = reviewDay == 7 ? phase == .chapterOneReview : phase == .finalReview
        let status: QuestJourneyChapterStatus

        if reviewComplete {
            status = .complete
        } else if reviewReady {
            status = .reviewReady
        } else if quests.isEmpty {
            status = .locked
        } else {
            status = .active
        }

        let remainingCount = max(7 - completedCount, 0)
        let milestoneTitle = reviewDay == 7 ? "Day 7 · Level-up review" : "Day 14 · Sprint review"
        let milestone: QuestJourneyMilestone

        if reviewComplete {
            milestone = QuestJourneyMilestone(
                title: milestoneTitle,
                detail: reviewDay == 7
                    ? "Complete · Chapter Two reflects what changed"
                    : "Complete · Your sprint report is ready",
                state: .complete
            )
        } else if reviewReady {
            milestone = QuestJourneyMilestone(
                title: milestoneTitle,
                detail: reviewDay == 7
                    ? "Ready now · See what changed before Chapter Two"
                    : "Ready now · Review the full sprint",
                state: .ready
            )
        } else {
            let unit = remainingCount == 1 ? "action" : "actions"
            milestone = QuestJourneyMilestone(
                title: milestoneTitle,
                detail: quests.isEmpty && reviewDay == 14
                    ? "Unlocks after your Day 7 review"
                    : "\(remainingCount) \(unit) until your \(reviewDay == 7 ? "level-up review" : "sprint review")",
                state: .locked
            )
        }

        return QuestJourneyChapter(
            number: number,
            questRangeText: questRangeText,
            title: title,
            subtitle: subtitle,
            quests: quests,
            focusGaps: uniqueGaps(in: quests),
            completedQuestCount: completedCount,
            totalQuestCount: 7,
            status: status,
            milestone: milestone,
            lockedExplanation: lockedExplanation
        )
    }

    private static func uniqueGaps(in quests: [Quest]) -> [CareerGap] {
        quests.reduce(into: []) { gaps, quest in
            if !gaps.contains(quest.gap) {
                gaps.append(quest.gap)
            }
        }
    }
}
