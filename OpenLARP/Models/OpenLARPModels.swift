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

enum CareerOutcomeKind: String, Codable, CaseIterable, Identifiable {
    case applied
    case interview
    case rejection
    case offer
    case changedGoal
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .applied: "Applied"
        case .interview: "Interview"
        case .rejection: "Rejection"
        case .offer: "Offer"
        case .changedGoal: "Changed goal"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .applied: "paperplane.fill"
        case .interview: "person.wave.2.fill"
        case .rejection: "arrow.counterclockwise.circle.fill"
        case .offer: "checkmark.seal.fill"
        case .changedGoal: "target"
        case .other: "flag.fill"
        }
    }

    var recoveryPrompt: String {
        switch self {
        case .applied:
            "Save the application receipt and connect it to the proof you used."
        case .interview:
            "Turn the interview into one practice story while the details are fresh."
        case .rejection:
            "Turn the rejection into one recovery quest instead of treating it as proof of failure."
        case .offer:
            "Save the offer as a major outcome, then keep proof attached to the path that got you there."
        case .changedGoal:
            "Run a fresh diagnostic before changing the plan so the new goal has its own baseline."
        case .other:
            "Write what happened and what it changes about the next quest."
        }
    }

    func activitySummary(for outcome: CareerOutcomeRecord) -> String {
        let organization = outcome.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeText = organization.isEmpty ? "" : " at \(organization)"
        return "\(label): \(outcome.displayTitle)\(placeText). \(recoveryPrompt)"
    }
}

struct CareerOutcomeRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: CareerOutcomeKind
    var title: String
    var organizationName: String
    var note: String
    var occurredAt: Date
    var createdAt: Date
    var targetRoleID: UUID?
    var targetRoleTitle: String
    var relatedQuestID: UUID?
    var relatedProofID: UUID?
    var isPrivate: Bool

    init(
        id: UUID = UUID(),
        kind: CareerOutcomeKind,
        title: String,
        organizationName: String = "",
        note: String = "",
        occurredAt: Date,
        createdAt: Date = Date(),
        targetRoleID: UUID? = nil,
        targetRoleTitle: String,
        relatedQuestID: UUID? = nil,
        relatedProofID: UUID? = nil,
        isPrivate: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.organizationName = organizationName
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.targetRoleID = targetRoleID
        self.targetRoleTitle = targetRoleTitle
        self.relatedQuestID = relatedQuestID
        self.relatedProofID = relatedProofID
        self.isPrivate = isPrivate
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? kind.label : trimmedTitle
    }

    var organizationText: String? {
        let trimmed = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct OutcomeLogContent: Equatable {
    var outcomes: [CareerOutcomeRecord]
    var countText: String
    var latestSummary: String?
    var emptyMessage: String

    init(outcomes: [CareerOutcomeRecord]) {
        self.outcomes = outcomes.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.occurredAt > rhs.occurredAt
        }
        countText = self.outcomes.count == 1 ? "1 career outcome" : "\(self.outcomes.count) career outcomes"
        latestSummary = self.outcomes.first.map { "\($0.kind.label): \($0.displayTitle)" }
        emptyMessage = "Log real outcomes here: applied, interview, rejection, offer, or changed goal."
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
    var targetClarity: Int
    var proofStrength: Int
    var confidence: Int
    var consistency: Int
    var skillProof: Int
    var experienceProof: Int
    var profileCredibility: Int
    var networkStrength: Int
    var interviewReadiness: Int
    var applicationExecution: Int

    static let baseline = ReadinessMetrics(
        overall: 42,
        targetClarity: 48,
        proofStrength: 42,
        confidence: 36,
        consistency: 28,
        skillProof: 38,
        experienceProof: 34,
        profileCredibility: 36,
        networkStrength: 31,
        interviewReadiness: 29,
        applicationExecution: 33
    )

    init(
        overall: Int,
        targetClarity: Int = 48,
        proofStrength: Int,
        confidence: Int,
        consistency: Int,
        skillProof: Int = 38,
        experienceProof: Int = 34,
        profileCredibility: Int = 36,
        networkStrength: Int = 31,
        interviewReadiness: Int = 29,
        applicationExecution: Int = 33
    ) {
        self.overall = overall
        self.targetClarity = targetClarity
        self.proofStrength = proofStrength
        self.confidence = confidence
        self.consistency = consistency
        self.skillProof = skillProof
        self.experienceProof = experienceProof
        self.profileCredibility = profileCredibility
        self.networkStrength = networkStrength
        self.interviewReadiness = interviewReadiness
        self.applicationExecution = applicationExecution
    }

    private enum CodingKeys: String, CodingKey {
        case overall
        case targetClarity
        case proofStrength
        case confidence
        case consistency
        case skillProof
        case experienceProof
        case profileCredibility
        case networkStrength
        case interviewReadiness
        case applicationExecution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overall = try container.decode(Int.self, forKey: .overall)
        targetClarity = try container.decodeIfPresent(Int.self, forKey: .targetClarity) ?? 48
        proofStrength = try container.decode(Int.self, forKey: .proofStrength)
        confidence = try container.decode(Int.self, forKey: .confidence)
        consistency = try container.decode(Int.self, forKey: .consistency)
        skillProof = try container.decodeIfPresent(Int.self, forKey: .skillProof) ?? 38
        experienceProof = try container.decodeIfPresent(Int.self, forKey: .experienceProof) ?? 34
        profileCredibility = try container.decodeIfPresent(Int.self, forKey: .profileCredibility) ?? 36
        networkStrength = try container.decodeIfPresent(Int.self, forKey: .networkStrength) ?? 31
        interviewReadiness = try container.decodeIfPresent(Int.self, forKey: .interviewReadiness) ?? 29
        applicationExecution = try container.decodeIfPresent(Int.self, forKey: .applicationExecution) ?? 33
    }
}

enum Badge: String, Codable, CaseIterable, Identifiable {
    case firstGoal = "First target locked"
    case firstProof = "First proof submitted"
    case strongProof = "Strong proof"
    case threeDayStreak = "3-day streak"
    case weeklyStreak = "7-day streak"
    case firstOutcome = "First outcome logged"
    case firstInterview = "First interview signal"
    case firstOffer = "Offer signal"

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
    var readinessHistory: [ReadinessSnapshot]
    var recentProof: [ProofRecord]

    static let empty = ProgressState(
        xp: 0,
        xpGoal: 1_000,
        streakCount: 0,
        completedQuestCount: 0,
        proofCount: 0,
        badges: [],
        readiness: .baseline,
        readinessHistory: [],
        recentProof: []
    )

    init(
        xp: Int,
        xpGoal: Int,
        streakCount: Int,
        completedQuestCount: Int,
        proofCount: Int,
        badges: [Badge],
        readiness: ReadinessMetrics,
        readinessHistory: [ReadinessSnapshot] = [],
        recentProof: [ProofRecord]
    ) {
        self.xp = xp
        self.xpGoal = xpGoal
        self.streakCount = streakCount
        self.completedQuestCount = completedQuestCount
        self.proofCount = proofCount
        self.badges = badges
        self.readiness = readiness
        self.readinessHistory = readinessHistory
        self.recentProof = recentProof
    }

    private enum CodingKeys: String, CodingKey {
        case xp
        case xpGoal
        case streakCount
        case completedQuestCount
        case proofCount
        case badges
        case readiness
        case readinessHistory
        case recentProof
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xp = try container.decode(Int.self, forKey: .xp)
        xpGoal = try container.decode(Int.self, forKey: .xpGoal)
        streakCount = try container.decode(Int.self, forKey: .streakCount)
        completedQuestCount = try container.decode(Int.self, forKey: .completedQuestCount)
        proofCount = try container.decode(Int.self, forKey: .proofCount)
        badges = try container.decode([Badge].self, forKey: .badges)
        readiness = try container.decode(ReadinessMetrics.self, forKey: .readiness)
        readinessHistory = try container.decodeIfPresent([ReadinessSnapshot].self, forKey: .readinessHistory) ?? []
        recentProof = try container.decode([ProofRecord].self, forKey: .recentProof)
    }
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
    var schemaVersion: Int
    var userProfile: CareerUserProfile?
    var goal: CareerGoal?
    var targetRoles: [TargetRole]
    var diagnostic: CookedDiagnostic?
    var plan: [Quest]
    var progress: ProgressState
    var agentBrief: AgentBrief
    var updatedAt: Date
    var dailyCadence: DailyCadenceState = .empty
    var missedDayRecovery: MissedDayRecoveryState = .empty
    var skippedToday: SkippedTodayState = .empty
    var proofDraft: ProofSubmission?
    var proofDraftQualityResult: QualityCheckResult?
    var outcomeLog: [CareerOutcomeRecord]

    init(
        schemaVersion: Int = 4,
        userProfile: CareerUserProfile? = nil,
        goal: CareerGoal?,
        targetRoles: [TargetRole] = [],
        diagnostic: CookedDiagnostic?,
        plan: [Quest],
        progress: ProgressState,
        agentBrief: AgentBrief = .empty,
        updatedAt: Date,
        dailyCadence: DailyCadenceState = .empty,
        missedDayRecovery: MissedDayRecoveryState = .empty,
        skippedToday: SkippedTodayState = .empty,
        proofDraft: ProofSubmission? = nil,
        proofDraftQualityResult: QualityCheckResult? = nil,
        outcomeLog: [CareerOutcomeRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.userProfile = userProfile
        self.goal = goal
        self.targetRoles = targetRoles
        self.diagnostic = diagnostic
        self.plan = plan
        self.progress = progress
        self.agentBrief = agentBrief
        self.updatedAt = updatedAt
        self.dailyCadence = dailyCadence
        self.missedDayRecovery = missedDayRecovery
        self.skippedToday = skippedToday
        self.proofDraft = proofDraft
        self.proofDraftQualityResult = proofDraftQualityResult
        self.outcomeLog = outcomeLog
    }

    static let empty = OpenLARPState(
        schemaVersion: 4,
        userProfile: nil,
        goal: nil,
        targetRoles: [],
        diagnostic: nil,
        plan: [],
        progress: .empty,
        agentBrief: .empty,
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
        case schemaVersion
        case userProfile
        case goal
        case targetRoles
        case diagnostic
        case plan
        case progress
        case agentBrief
        case updatedAt
        case dailyCadence
        case missedDayRecovery
        case skippedToday
        case proofDraft
        case proofDraftQualityResult
        case outcomeLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = 4
        userProfile = try container.decodeIfPresent(CareerUserProfile.self, forKey: .userProfile)
        goal = try container.decodeIfPresent(CareerGoal.self, forKey: .goal)
        targetRoles = try container.decodeIfPresent([TargetRole].self, forKey: .targetRoles) ?? []
        diagnostic = try container.decodeIfPresent(CookedDiagnostic.self, forKey: .diagnostic)
        plan = try container.decode([Quest].self, forKey: .plan)
        progress = try container.decode(ProgressState.self, forKey: .progress)
        agentBrief = try container.decodeIfPresent(AgentBrief.self, forKey: .agentBrief) ?? .empty
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dailyCadence = try container.decodeIfPresent(DailyCadenceState.self, forKey: .dailyCadence) ?? .empty
        missedDayRecovery = try container.decodeIfPresent(MissedDayRecoveryState.self, forKey: .missedDayRecovery) ?? .empty
        skippedToday = try container.decodeIfPresent(SkippedTodayState.self, forKey: .skippedToday) ?? .empty
        proofDraft = try container.decodeIfPresent(ProofSubmission.self, forKey: .proofDraft)
        proofDraftQualityResult = try container.decodeIfPresent(QualityCheckResult.self, forKey: .proofDraftQualityResult)
        outcomeLog = try container.decodeIfPresent([CareerOutcomeRecord].self, forKey: .outcomeLog) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(userProfile, forKey: .userProfile)
        try container.encodeIfPresent(goal, forKey: .goal)
        try container.encode(targetRoles, forKey: .targetRoles)
        try container.encodeIfPresent(diagnostic, forKey: .diagnostic)
        try container.encode(plan, forKey: .plan)
        try container.encode(progress, forKey: .progress)
        try container.encode(agentBrief, forKey: .agentBrief)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(dailyCadence, forKey: .dailyCadence)
        try container.encode(missedDayRecovery, forKey: .missedDayRecovery)
        try container.encode(skippedToday, forKey: .skippedToday)
        try container.encodeIfPresent(proofDraft, forKey: .proofDraft)
        try container.encodeIfPresent(proofDraftQualityResult, forKey: .proofDraftQualityResult)
        try container.encode(outcomeLog, forKey: .outcomeLog)
    }
}

enum OpenLARPError: Error, LocalizedError, Equatable {
    case noCurrentQuest
    case questNotAvailable
    case emptyProof
    case attachmentStorageFailed
    case invalidQuestPlan

    var errorDescription: String? {
        switch self {
        case .noCurrentQuest: "There is no current quest to work on."
        case .questNotAvailable: "This quest is not available yet."
        case .emptyProof: "Add a short proof note, link, photo, or screenshot before checking quality."
        case .attachmentStorageFailed: "That image could not be saved locally. Try another screenshot or photo."
        case .invalidQuestPlan: "The generated plan was not usable, so OpenLARP switched to a local plan."
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
