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

struct ProofAttachment: Codable, Equatable, Identifiable {
    var id: UUID
    var fileName: String
    var originalFileName: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
    var localRelativePath: String

    init(
        id: UUID = UUID(),
        fileName: String,
        originalFileName: String = "",
        contentType: String,
        byteCount: Int,
        createdAt: Date = Date(),
        localRelativePath: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.localRelativePath = localRelativePath ?? "ProofAttachments/\(fileName)"
    }

    var isImage: Bool {
        contentType.hasPrefix("image/")
    }
}

struct ProofSubmission: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: ProofKind
    var text: String
    var link: String
    var attachments: [ProofAttachment]
    var submittedAt: Date

    init(
        id: UUID = UUID(),
        kind: ProofKind,
        text: String,
        link: String = "",
        attachments: [ProofAttachment] = [],
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.link = link
        self.attachments = attachments
        self.submittedAt = submittedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case link
        case attachments
        case submittedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ProofKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        link = try container.decode(String.self, forKey: .link)
        attachments = try container.decodeIfPresent([ProofAttachment].self, forKey: .attachments) ?? []
        submittedAt = try container.decode(Date.self, forKey: .submittedAt)
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
    var attachments: [ProofAttachment]
    var submittedAt: Date
    var quality: QualityCheckResult?

    var attachmentSummary: String {
        let imageCount = attachments.filter(\.isImage).count
        guard imageCount > 0 else { return "No attachments" }
        return imageCount == 1 ? "1 image" : "\(imageCount) images"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case questID
        case questTitle
        case kind
        case text
        case link
        case attachments
        case submittedAt
        case quality
    }

    init(
        id: UUID,
        questID: UUID,
        questTitle: String,
        kind: ProofKind,
        text: String,
        link: String,
        attachments: [ProofAttachment] = [],
        submittedAt: Date,
        quality: QualityCheckResult?
    ) {
        self.id = id
        self.questID = questID
        self.questTitle = questTitle
        self.kind = kind
        self.text = text
        self.link = link
        self.attachments = attachments
        self.submittedAt = submittedAt
        self.quality = quality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        questID = try container.decode(UUID.self, forKey: .questID)
        questTitle = try container.decode(String.self, forKey: .questTitle)
        kind = try container.decode(ProofKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        link = try container.decode(String.self, forKey: .link)
        attachments = try container.decodeIfPresent([ProofAttachment].self, forKey: .attachments) ?? []
        submittedAt = try container.decode(Date.self, forKey: .submittedAt)
        quality = try container.decodeIfPresent(QualityCheckResult.self, forKey: .quality)
    }
}

struct ProofDetailContent: Equatable {
    var questTitle: String
    var proofType: String
    var submittedAt: Date
    var qualityLabel: String
    var xpText: String
    var reason: String
    var improvement: String
    var proofText: String?
    var proofLinkText: String?
    var proofURL: URL?

    init(proof: ProofRecord) {
        let trimmedText = proof.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = proof.link.trimmingCharacters(in: .whitespacesAndNewlines)

        questTitle = proof.questTitle
        proofType = proof.kind.label
        submittedAt = proof.submittedAt
        qualityLabel = proof.quality?.label ?? proof.kind.label
        xpText = "\(proof.quality?.xpEarned ?? 0) XP"
        reason = proof.quality?.reason ?? "No quality check is attached to this receipt yet."
        improvement = proof.quality?.improvement ?? "Submit stronger proof on the next quest to get sharper feedback."
        proofText = trimmedText.isEmpty ? nil : trimmedText
        proofLinkText = trimmedLink.isEmpty ? nil : trimmedLink
        proofURL = trimmedLink.hasPrefix("http://") || trimmedLink.hasPrefix("https://") ? URL(string: trimmedLink) : nil
    }
}

struct ProofArchiveContent: Equatable {
    var receipts: [ProofRecord]
    var countText: String
    var emptyMessage: String

    init(proofs: [ProofRecord]) {
        receipts = proofs.sorted { lhs, rhs in
            lhs.submittedAt > rhs.submittedAt
        }
        countText = receipts.count == 1 ? "1 proof receipt" : "\(receipts.count) proof receipts"
        emptyMessage = "Proof receipts appear here after you submit quest proof."
    }
}

struct CompletedQuestDetailContent: Equatable {
    var dayText: String
    var statusText: String
    var title: String
    var objectiveText: String
    var stepTexts: [String]
    var proofRequiredText: String
    var gapText: String
    var xpRewardText: String
    var savedProof: ProofRecord?
    var noProofMessage: String

    init(quest: Quest, proofs: [ProofRecord]) {
        dayText = "Day \(quest.day)"
        statusText = quest.status.label
        title = quest.title
        objectiveText = quest.purpose
        stepTexts = quest.steps
        proofRequiredText = quest.proofRequired
        gapText = quest.gap.title
        xpRewardText = "\(quest.xpReward) XP"
        savedProof = proofs.first { $0.questID == quest.id }
        noProofMessage = "No proof receipt saved for this completed quest."
    }
}

struct QuestPreviewContent: Equatable {
    var dayText: String
    var statusText: String
    var title: String
    var objectiveText: String
    var stepTexts: [String]
    var proofRequiredText: String
    var gapText: String
    var xpRewardText: String
    var timeEstimateText: String
    var difficultyText: String
    var todayCTATitle: String?
    var canOpenToday: Bool

    init(quest: Quest) {
        dayText = "Day \(quest.day)"
        statusText = quest.status.label
        title = quest.title
        objectiveText = quest.purpose
        stepTexts = quest.steps
        proofRequiredText = quest.proofRequired
        gapText = quest.gap.title
        xpRewardText = "\(quest.xpReward) XP"
        timeEstimateText = quest.timeEstimate
        difficultyText = quest.difficulty

        switch quest.status {
        case .available:
            todayCTATitle = "Go to Today to Start"
            canOpenToday = true
        case .inProgress:
            todayCTATitle = "Go to Today to Continue"
            canOpenToday = true
        case .locked, .completed, .skipped:
            todayCTATitle = nil
            canOpenToday = false
        }
    }
}

struct TodayCompletionContent: Equatable {
    var completedQuestTitle: String
    var resultSummary: String
    var xpText: String
    var streakText: String
    var proofRecord: ProofRecord?
    var nextQuestTitle: String?
    var nextQuestObjectiveText: String?
    var nextQuestMetaText: String?
    var nextQuestStatusText: String
    var unlockMessage: String

    init?(
        state: OpenLARPState,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard let completedAt = state.dailyCadence.completedAt,
              calendar.isDate(completedAt, inSameDayAs: now)
        else {
            return nil
        }

        let completedQuest = state.dailyCadence.lastCompletedQuestID.flatMap { questID in
            state.plan.first { $0.id == questID }
        }
        let proof = state.dailyCadence.lastCompletedQuestID.flatMap { questID in
            state.progress.recentProof.first { $0.questID == questID }
        }

        completedQuestTitle = state.dailyCadence.completedQuestTitle ?? completedQuest?.title ?? "Today's quest"
        resultSummary = state.dailyCadence.resultLabel ?? proof?.quality?.label ?? "Quest complete"
        xpText = "+\(state.dailyCadence.xpEarned ?? proof?.quality?.xpEarned ?? 0) XP"

        let streakCount = state.dailyCadence.streakCountAfterCompletion ?? state.progress.streakCount
        streakText = streakCount == 1 ? "1-day streak" : "\(streakCount)-day streak"
        proofRecord = proof

        if let nextQuestID = state.dailyCadence.nextQuestID,
           let nextQuest = state.plan.first(where: { $0.id == nextQuestID }) {
            nextQuestTitle = nextQuest.title
            nextQuestObjectiveText = nextQuest.purpose
            nextQuestMetaText = "\(nextQuest.timeEstimate), \(nextQuest.difficulty), +\(nextQuest.xpReward) XP"
            nextQuestStatusText = "Locked until tomorrow"
            unlockMessage = "Your next quest unlocks tomorrow."
        } else {
            nextQuestTitle = nil
            nextQuestObjectiveText = nil
            nextQuestMetaText = nil
            nextQuestStatusText = "Track complete"
            unlockMessage = "You finished the local seven-day track."
        }
    }
}

struct SkippedTodayContent: Equatable {
    var skippedQuestTitle: String
    var title: String
    var bodyText: String
    var previousStreakText: String
    var activeStreakText: String
    var preservedProgressText: String
    var nextQuestTitle: String?
    var nextQuestObjectiveText: String?
    var nextQuestMetaText: String?
    var nextQuestStatusText: String
    var unlockMessage: String

    init?(
        state: OpenLARPState,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard let skippedAt = state.skippedToday.skippedAt,
              calendar.isDate(skippedAt, inSameDayAs: now)
        else {
            return nil
        }

        let skippedQuest = state.skippedToday.skippedQuestID.flatMap { questID in
            state.plan.first { $0.id == questID }
        }
        skippedQuestTitle = state.skippedToday.skippedQuestTitle ?? skippedQuest?.title ?? "Today's quest"
        title = "Skipped today"
        bodyText = "Your active streak reset to 0. Your earlier XP, proof receipts, badges, and completed quests are still saved."

        let previousStreakCount = state.skippedToday.previousStreakCount
        previousStreakText = previousStreakCount == 1 ? "Previous streak: 1 day" : "Previous streak: \(previousStreakCount) days"
        let activeStreakCount = state.progress.streakCount
        activeStreakText = activeStreakCount == 1 ? "Active streak: 1 day" : "Active streak: \(activeStreakCount) days"
        preservedProgressText = "\(state.progress.xp) XP, \(state.progress.proofCount) proof receipts, and \(state.progress.completedQuestCount) completed quests preserved."

        if let nextQuestID = state.skippedToday.nextQuestID,
           let nextQuest = state.plan.first(where: { $0.id == nextQuestID }) {
            nextQuestTitle = nextQuest.title
            nextQuestObjectiveText = nextQuest.purpose
            nextQuestMetaText = "\(nextQuest.timeEstimate), \(nextQuest.difficulty), +\(nextQuest.xpReward) XP"
            nextQuestStatusText = "Locked until tomorrow"
            unlockMessage = "Your next quest unlocks tomorrow."
        } else {
            nextQuestTitle = nil
            nextQuestObjectiveText = nil
            nextQuestMetaText = nil
            nextQuestStatusText = "Track complete"
            unlockMessage = "You skipped the final local quest. The track is finished for now."
        }
    }
}

struct MissedDayRecoveryContent: Equatable {
    var title: String
    var missedDaysText: String
    var bodyText: String
    var previousStreakText: String
    var activeStreakText: String
    var nextQuestTitle: String
    var nextQuestObjectiveText: String
    var nextQuestMetaText: String
    var primaryActionTitle: String

    init?(state: OpenLARPState) {
        guard state.missedDayRecovery.startedAt != nil,
              let nextQuestID = state.missedDayRecovery.nextQuestID,
              let nextQuest = state.plan.first(where: { $0.id == nextQuestID })
        else {
            return nil
        }

        title = "Streak reset, track still alive"
        let missedDayCount = max(1, state.missedDayRecovery.missedDayCount)
        missedDaysText = missedDayCount == 1 ? "You missed 1 quest day." : "You missed \(missedDayCount) quest days."
        bodyText = "No shame. Your XP and proof receipts are still here. Start the next quest to rebuild from today."

        let previousStreakCount = state.missedDayRecovery.previousStreakCount
        previousStreakText = previousStreakCount == 1 ? "Previous streak: 1 day" : "Previous streak: \(previousStreakCount) days"
        let activeStreakCount = state.progress.streakCount
        activeStreakText = activeStreakCount == 1 ? "Active streak: 1 day" : "Active streak: \(activeStreakCount) days"

        nextQuestTitle = nextQuest.title
        nextQuestObjectiveText = nextQuest.purpose
        nextQuestMetaText = "\(nextQuest.timeEstimate), \(nextQuest.difficulty), +\(nextQuest.xpReward) XP"
        primaryActionTitle = "Continue Next Quest"
    }
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

struct DailyCadenceState: Codable, Equatable {
    var lastCompletedQuestID: UUID?
    var completedQuestTitle: String?
    var completedAt: Date?
    var resultLabel: String?
    var xpEarned: Int?
    var streakCountAfterCompletion: Int?
    var nextQuestID: UUID?
    var nextUnlockDate: Date?

    static let empty = DailyCadenceState(
        lastCompletedQuestID: nil,
        completedQuestTitle: nil,
        completedAt: nil,
        resultLabel: nil,
        xpEarned: nil,
        streakCountAfterCompletion: nil,
        nextQuestID: nil,
        nextUnlockDate: nil
    )
}

struct MissedDayRecoveryState: Codable, Equatable {
    var startedAt: Date?
    var missedDayCount: Int
    var lastCompletedQuestID: UUID?
    var nextQuestID: UUID?
    var previousStreakCount: Int

    static let empty = MissedDayRecoveryState(
        startedAt: nil,
        missedDayCount: 0,
        lastCompletedQuestID: nil,
        nextQuestID: nil,
        previousStreakCount: 0
    )
}

struct SkippedTodayState: Codable, Equatable {
    var skippedQuestID: UUID?
    var skippedQuestTitle: String?
    var skippedAt: Date?
    var previousStreakCount: Int
    var nextQuestID: UUID?
    var nextUnlockDate: Date?

    static let empty = SkippedTodayState(
        skippedQuestID: nil,
        skippedQuestTitle: nil,
        skippedAt: nil,
        previousStreakCount: 0,
        nextQuestID: nil,
        nextUnlockDate: nil
    )
}

struct OpenLARPState: Codable, Equatable {
    var goal: CareerGoal?
    var diagnostic: CookedDiagnostic?
    var plan: [Quest]
    var progress: ProgressState
    var updatedAt: Date
    var dailyCadence: DailyCadenceState = .empty
    var missedDayRecovery: MissedDayRecoveryState = .empty
    var skippedToday: SkippedTodayState = .empty

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
        if dailyCadence.completedAt != nil || skippedToday.skippedAt != nil {
            return nil
        }
        return plan.first { $0.status == .inProgress } ?? plan.first { $0.status == .available }
    }
}

extension OpenLARPState {
    private enum CodingKeys: String, CodingKey {
        case goal
        case diagnostic
        case plan
        case progress
        case updatedAt
        case dailyCadence
        case missedDayRecovery
        case skippedToday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decodeIfPresent(CareerGoal.self, forKey: .goal)
        diagnostic = try container.decodeIfPresent(CookedDiagnostic.self, forKey: .diagnostic)
        plan = try container.decode([Quest].self, forKey: .plan)
        progress = try container.decode(ProgressState.self, forKey: .progress)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dailyCadence = try container.decodeIfPresent(DailyCadenceState.self, forKey: .dailyCadence) ?? .empty
        missedDayRecovery = try container.decodeIfPresent(MissedDayRecoveryState.self, forKey: .missedDayRecovery) ?? .empty
        skippedToday = try container.decodeIfPresent(SkippedTodayState.self, forKey: .skippedToday) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(goal, forKey: .goal)
        try container.encodeIfPresent(diagnostic, forKey: .diagnostic)
        try container.encode(plan, forKey: .plan)
        try container.encode(progress, forKey: .progress)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(dailyCadence, forKey: .dailyCadence)
        try container.encode(missedDayRecovery, forKey: .missedDayRecovery)
        try container.encode(skippedToday, forKey: .skippedToday)
    }
}

enum OpenLARPError: Error, LocalizedError, Equatable {
    case noCurrentQuest
    case questNotAvailable
    case emptyProof
    case attachmentStorageFailed

    var errorDescription: String? {
        switch self {
        case .noCurrentQuest: "There is no current quest to work on."
        case .questNotAvailable: "This quest is not available yet."
        case .emptyProof: "Add a short proof note, link, photo, or screenshot before checking quality."
        case .attachmentStorageFailed: "That image could not be saved locally. Try another screenshot or photo."
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
