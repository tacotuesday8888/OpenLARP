import Foundation
import SwiftUI

struct UserSnapshot {
    let name: String
    let targetRole: String
    let targetTimeline: String
    let cookedLabel: String
    let cookedScore: Int
    let mainGap: String
    let streakCount: Int
    let xp: Int
    let xpGoal: Int
    let todayQuest: Quest
    let proofCount: Int
    let readiness: [ReadinessGap]
}

struct Quest: Identifiable {
    let id: UUID
    let title: String
    let purpose: String
    let timeEstimate: String
    let difficulty: String
    let proofRequired: String
    let xpReward: Int

    init(
        id: UUID = UUID(),
        title: String,
        purpose: String,
        timeEstimate: String,
        difficulty: String,
        proofRequired: String,
        xpReward: Int
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.timeEstimate = timeEstimate
        self.difficulty = difficulty
        self.proofRequired = proofRequired
        self.xpReward = xpReward
    }
}

struct QuestDay: Identifiable {
    let id: UUID
    let day: Int
    let title: String
    let focus: String
    let status: QuestStatus
    let xpReward: Int

    init(
        id: UUID = UUID(),
        day: Int,
        title: String,
        focus: String,
        status: QuestStatus,
        xpReward: Int
    ) {
        self.id = id
        self.day = day
        self.title = title
        self.focus = focus
        self.status = status
        self.xpReward = xpReward
    }
}

enum QuestStatus {
    case complete
    case current
    case locked

    var label: String {
        switch self {
        case .complete: "Complete"
        case .current: "Today"
        case .locked: "Locked"
        }
    }

    var color: Color {
        switch self {
        case .complete: .openLARPGreen
        case .current: .openLARPCoral
        case .locked: .openLARPGray
        }
    }
}

struct ReadinessGap: Identifiable {
    let id: UUID
    let title: String
    let value: Double
    let label: String
    let color: Color

    init(id: UUID = UUID(), title: String, value: Double, label: String, color: Color) {
        self.id = id
        self.title = title
        self.value = value
        self.label = label
        self.color = color
    }
}

struct AgentPrompt: Identifiable {
    let id: UUID
    let title: String
    let description: String

    init(id: UUID = UUID(), title: String, description: String) {
        self.id = id
        self.title = title
        self.description = description
    }
}

struct ProfileSummary {
    let name: String
    let status: String
    let goal: String
    let timeline: String
    let memoryMode: String
    let proofItems: Int
    let badges: [String]
}
