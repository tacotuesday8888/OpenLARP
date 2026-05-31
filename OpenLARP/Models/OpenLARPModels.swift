import Foundation
import SwiftUI

enum CurrentStatus: String, Codable, CaseIterable, Identifiable {
    case student = "Student"
    case newGrad = "New grad"
    case careerSwitcher = "Career switcher"
    case unemployed = "Unemployed"
    case employed = "Employed"

    var id: String { rawValue }
}

struct CareerGoal: Codable, Equatable {
    var currentStatus: CurrentStatus
    var targetRole: String
    var timeline: String
    var background: String
    var existingProof: String
    var confidence: Int
    var biggestBlocker: String

    static let empty = CareerGoal(
        currentStatus: .student,
        targetRole: "",
        timeline: "30 days",
        background: "",
        existingProof: "",
        confidence: 3,
        biggestBlocker: ""
    )
}

struct CookedDiagnostic: Codable, Equatable {
    var score: Int
    var label: String
    var mainGap: String
    var strongestSignal: String
    var fastestFix: String
    var readinessBaseline: Int
}

enum CareerGap: String, Codable, CaseIterable, Identifiable {
    case targetClarity
    case proofStrength
    case confidence
    case consistency
    case networking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .targetClarity: "Target clarity"
        case .proofStrength: "Proof strength"
        case .confidence: "Confidence"
        case .consistency: "Consistency"
        case .networking: "Networking"
        }
    }
}

enum QuestStatus: String, Codable, CaseIterable {
    case locked
    case available
    case inProgress
    case completed
    case skipped

    var label: String {
        switch self {
        case .locked: "Locked"
        case .available: "Today"
        case .inProgress: "In progress"
        case .completed: "Complete"
        case .skipped: "Skipped"
        }
    }

    var color: Color {
        switch self {
        case .locked: .openLARPGray
        case .available: .openLARPCoral
        case .inProgress: .openLARPYellow
        case .completed: .openLARPGreen
        case .skipped: .openLARPGray
        }
    }
}

struct Quest: Codable, Equatable, Identifiable {
    var id: UUID
    var day: Int
    var title: String
    var purpose: String
    var timeEstimateMinutes: Int
    var difficulty: String
    var gap: CareerGap
    var proofRequired: String
    var xpReward: Int
    var steps: [String]
    var status: QuestStatus

    var timeEstimate: String { "\(timeEstimateMinutes) min" }

    init(
        id: UUID = UUID(),
        day: Int = 1,
        title: String,
        purpose: String,
        timeEstimateMinutes: Int = 25,
        difficulty: String = "Adaptive",
        gap: CareerGap = .proofStrength,
        proofRequired: String,
        xpReward: Int,
        steps: [String] = [],
        status: QuestStatus = .available
    ) {
        self.id = id
        self.day = day
        self.title = title
        self.purpose = purpose
        self.timeEstimateMinutes = timeEstimateMinutes
        self.difficulty = difficulty
        self.gap = gap
        self.proofRequired = proofRequired
        self.xpReward = xpReward
        self.steps = steps
        self.status = status
    }

    init(
        id: UUID = UUID(),
        title: String,
        purpose: String,
        timeEstimate: String,
        difficulty: String,
        proofRequired: String,
        xpReward: Int
    ) {
        let minutes = Int(timeEstimate.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 25
        self.init(
            id: id,
            title: title,
            purpose: purpose,
            timeEstimateMinutes: minutes,
            difficulty: difficulty,
            proofRequired: proofRequired,
            xpReward: xpReward
        )
    }
}

enum ProofKind: String, Codable, CaseIterable, Identifiable {
    case proof
    case selfReport

    var id: String { rawValue }

    var label: String {
        switch self {
        case .proof: "Proof"
        case .selfReport: "Self-report"
        }
    }
}

struct ProofSubmission: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: ProofKind
    var text: String
    var link: String
    var submittedAt: Date

    init(
        id: UUID = UUID(),
        kind: ProofKind,
        text: String,
        link: String = "",
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.link = link
        self.submittedAt = submittedAt
    }
}

struct QualityCheckResult: Codable, Equatable {
    var isAccepted: Bool
    var qualityScore: Int
    var label: String
    var reason: String
    var improvement: String
    var xpEarned: Int
    var readinessDelta: Int
}

struct ProofRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var questID: UUID
    var questTitle: String
    var kind: ProofKind
    var text: String
    var link: String
    var submittedAt: Date
    var quality: QualityCheckResult?
}

struct ReadinessMetrics: Codable, Equatable {
    var overall: Int
    var proofStrength: Int
    var confidence: Int
    var consistency: Int

    static let baseline = ReadinessMetrics(
        overall: 42,
        proofStrength: 42,
        confidence: 36,
        consistency: 28
    )
}

enum Badge: String, Codable, CaseIterable, Identifiable {
    case firstGoal = "First target locked"
    case firstProof = "First proof submitted"
    case strongProof = "Strong proof"
    case threeDayStreak = "3-day streak"
    case weeklyStreak = "7-day streak"

    var id: String { rawValue }
}

struct ProgressState: Codable, Equatable {
    var xp: Int
    var xpGoal: Int
    var streakCount: Int
    var completedQuestCount: Int
    var proofCount: Int
    var badges: [Badge]
    var readiness: ReadinessMetrics
    var recentProof: [ProofRecord]

    static let empty = ProgressState(
        xp: 0,
        xpGoal: 1_000,
        streakCount: 0,
        completedQuestCount: 0,
        proofCount: 0,
        badges: [],
        readiness: .baseline,
        recentProof: []
    )
}

struct OpenLARPState: Codable, Equatable {
    var goal: CareerGoal?
    var diagnostic: CookedDiagnostic?
    var plan: [Quest]
    var progress: ProgressState
    var updatedAt: Date

    static let empty = OpenLARPState(
        goal: nil,
        diagnostic: nil,
        plan: [],
        progress: .empty,
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    var needsGoalSetup: Bool {
        goal == nil || diagnostic == nil || plan.isEmpty
    }

    var currentQuest: Quest? {
        plan.first { $0.status == .inProgress } ?? plan.first { $0.status == .available }
    }
}

enum OpenLARPError: Error, LocalizedError, Equatable {
    case noCurrentQuest
    case questNotAvailable
    case emptyProof

    var errorDescription: String? {
        switch self {
        case .noCurrentQuest: "There is no current quest to work on."
        case .questNotAvailable: "This quest is not available yet."
        case .emptyProof: "Add a short proof note or self-report before checking quality."
        }
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
