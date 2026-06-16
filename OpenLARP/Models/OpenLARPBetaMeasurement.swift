import Foundation

enum BetaEventKind: String, Codable, CaseIterable, Identifiable {
    case goalConfirmed
    case diagnosticShown
    case firstQuestStarted
    case questStarted
    case questSkipped
    case proofSubmitted
    case proofAccepted
    case proofNeedsImprovement
    case xpClaimed
    case nextDayReturn
    case cookedCardPrepared
    case outcomeLogged
    case syncPreviewPrepared

    var id: String { rawValue }

    var label: String {
        switch self {
        case .goalConfirmed: "Goal confirmed"
        case .diagnosticShown: "Diagnostic shown"
        case .firstQuestStarted: "First quest started"
        case .questStarted: "Quest started"
        case .questSkipped: "Quest skipped"
        case .proofSubmitted: "Proof submitted"
        case .proofAccepted: "Proof accepted"
        case .proofNeedsImprovement: "Proof needs improvement"
        case .xpClaimed: "XP claimed"
        case .nextDayReturn: "Next-day return"
        case .cookedCardPrepared: "Cooked card prepared"
        case .outcomeLogged: "Outcome logged"
        case .syncPreviewPrepared: "Sync preview prepared"
        }
    }
}

struct BetaEventRecord: Codable, Equatable {
    var kind: BetaEventKind
    var occurredAt: Date
    var day: Int?

    init(
        kind: BetaEventKind,
        occurredAt: Date = Date(),
        day: Int? = nil
    ) {
        self.kind = kind
        self.occurredAt = occurredAt
        self.day = day
    }
}

struct LossyBetaEventRecordList: Decodable {
    var records: [BetaEventRecord]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodedRecords: [BetaEventRecord] = []

        while !container.isAtEnd {
            if let record = try? container.decode(BetaEventRecord.self) {
                decodedRecords.append(record)
            } else if (try? container.decode(DiscardedBetaEventRecord.self)) == nil {
                break
            }
        }

        records = decodedRecords
    }
}

private struct DiscardedBetaEventRecord: Decodable {}

struct BetaMeasurementEventCount: Codable, Equatable, Identifiable {
    var kind: BetaEventKind
    var count: Int

    var id: BetaEventKind { kind }
}

struct BetaMeasurementSummaryContent: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let totalEvents: Int
    let eventCounts: [BetaMeasurementEventCount]
    let goalSetupComplete: Bool
    let planQuestCount: Int
    let availableQuestCount: Int
    let inProgressQuestCount: Int
    let completedQuestCount: Int
    let skippedQuestCount: Int
    let lockedQuestCount: Int
    let xp: Int
    let streakCount: Int
    let proofCount: Int
    let acceptedProofCount: Int
    let weakProofCount: Int
    let outcomeCount: Int
    let readinessOverall: Int
    let completedToday: Bool
    let skippedToday: Bool
    let hasPendingProofDraft: Bool
    let firstEventAt: Date?
    let latestEventAt: Date?
    let privacyNotice: String

    init(state: OpenLARPState, generatedAt: Date = Date()) {
        schemaVersion = 1
        self.generatedAt = generatedAt
        totalEvents = state.betaEvents.count
        eventCounts = BetaEventKind.allCases.compactMap { kind in
            let count = state.betaEvents.filter { $0.kind == kind }.count
            return count > 0 ? BetaMeasurementEventCount(kind: kind, count: count) : nil
        }
        goalSetupComplete = !state.needsGoalSetup
        planQuestCount = state.plan.count
        availableQuestCount = state.plan.filter { $0.status == .available }.count
        inProgressQuestCount = state.plan.filter { $0.status == .inProgress }.count
        completedQuestCount = state.progress.completedQuestCount
        skippedQuestCount = state.plan.filter { $0.status == .skipped }.count
        lockedQuestCount = state.plan.filter { $0.status == .locked }.count
        xp = state.progress.xp
        streakCount = state.progress.streakCount
        proofCount = state.progress.proofCount
        acceptedProofCount = state.progress.recentProof.filter { $0.quality?.isAccepted == true }.count
        weakProofCount = state.progress.recentProof.filter { $0.quality?.isAccepted == false }.count
        outcomeCount = state.outcomeLog.filter { $0.deletedAt == nil }.count
        readinessOverall = state.progress.readiness.overall
        completedToday = state.dailyCadence.completedAt != nil
        skippedToday = state.skippedToday.skippedAt != nil
        hasPendingProofDraft = state.proofDraft != nil
        firstEventAt = state.betaEvents.map(\.occurredAt).min()
        latestEventAt = state.betaEvents.map(\.occurredAt).max()
        privacyNotice = "Private proof text, links, attachment paths, local file paths, and private notes are not included."
    }

    var searchableText: String {
        var lines = [
            "OpenLARP Beta Measurement Summary",
            "Generated: \(Self.formattedDate(generatedAt))",
            "Goal setup complete: \(goalSetupComplete ? "Yes" : "No")",
            "Total events: \(totalEvents)",
            "Plan quests: \(planQuestCount)",
            "Completed quests: \(completedQuestCount)",
            "Available quests: \(availableQuestCount)",
            "In-progress quests: \(inProgressQuestCount)",
            "Skipped quests: \(skippedQuestCount)",
            "Locked quests: \(lockedQuestCount)",
            "XP: \(xp)",
            "Streak: \(streakCount)",
            "Proof submitted: \(proofCount)",
            "Proof accepted: \(acceptedProofCount)",
            "Proof needs improvement: \(weakProofCount)",
            "Outcomes logged: \(outcomeCount)",
            "Readiness: \(readinessOverall)%",
            "Completed today: \(completedToday ? "Yes" : "No")",
            "Skipped today: \(skippedToday ? "Yes" : "No")",
            "Pending proof draft: \(hasPendingProofDraft ? "Yes" : "No")"
        ]

        for count in eventCounts {
            lines.append("\(count.kind.label): \(count.count)")
        }

        if let firstEventAt {
            lines.append("First event: \(Self.formattedDate(firstEventAt))")
        }
        if let latestEventAt {
            lines.append("Latest event: \(Self.formattedDate(latestEventAt))")
        }

        lines.append(privacyNotice)
        return lines.joined(separator: "\n")
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

extension JSONEncoder {
    static var openLARPBetaExport: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
