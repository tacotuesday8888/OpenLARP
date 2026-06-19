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
    case accountSessionRestored
    case accountSignInCompleted
    case accountSignInFailed
    case accountSignedOut
    case syncPreviewPrepared
    case freeSprintStarted
    case subscriptionStatusChecked
    case subscriptionPaywallViewed
    case subscriptionRestoreRequested
    case subscriptionRestoreCompleted
    case subscriptionRestoreFailed
    case privateEvidenceBackupCleanupReported
    case privateEvidenceBackupCleanupDeleted
    case accountDeletionRequested
    case accountDeletionCompleted
    case accountDeletionPartial

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
        case .accountSessionRestored: "Account session restored"
        case .accountSignInCompleted: "Account sign-in completed"
        case .accountSignInFailed: "Account sign-in failed"
        case .accountSignedOut: "Account signed out"
        case .syncPreviewPrepared: "Sync preview prepared"
        case .freeSprintStarted: "Free sprint started"
        case .subscriptionStatusChecked: "Subscription status checked"
        case .subscriptionPaywallViewed: "Subscription paywall viewed"
        case .subscriptionRestoreRequested: "Subscription restore requested"
        case .subscriptionRestoreCompleted: "Subscription restore completed"
        case .subscriptionRestoreFailed: "Subscription restore failed"
        case .privateEvidenceBackupCleanupReported: "Private evidence backup cleanup reported"
        case .privateEvidenceBackupCleanupDeleted: "Private evidence backup cleanup deleted"
        case .accountDeletionRequested: "Account deletion requested"
        case .accountDeletionCompleted: "Account deletion completed"
        case .accountDeletionPartial: "Account deletion partial"
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

struct AIWorkflowRunCount: Codable, Equatable, Identifiable {
    var kind: V0AIWorkflowKind
    var count: Int

    var id: V0AIWorkflowKind { kind }
}

struct AIWorkflowProviderCount: Codable, Equatable, Identifiable {
    var providerRoute: V0AIProviderRoute
    var count: Int

    var id: V0AIProviderRoute { providerRoute }
}

struct BetaMeasurementSummaryContent: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let totalEvents: Int
    let eventCounts: [BetaMeasurementEventCount]
    let aiWorkflowRunCount: Int
    let aiWorkflowFallbackCount: Int
    let aiWorkflowKindCounts: [AIWorkflowRunCount]
    let aiWorkflowProviderCounts: [AIWorkflowProviderCount]
    let paymentEventCount: Int
    let subscriptionHasAccess: Bool
    let subscriptionAccessStatus: OpenLARPSubscriptionAccessStatus
    let subscriptionAccessSource: OpenLARPSubscriptionAccessSource
    let subscriptionNeedsPaywall: Bool
    let subscriptionFreeSprintDaysRemaining: Int?
    let subscriptionRestoreStatus: OpenLARPSubscriptionRestoreStatus
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
        aiWorkflowRunCount = state.aiWorkflowRuns.count
        aiWorkflowFallbackCount = state.aiWorkflowRuns.filter(\.usedFallback).count
        aiWorkflowKindCounts = V0AIWorkflowKind.allCases.compactMap { kind in
            let count = state.aiWorkflowRuns.filter { $0.kind == kind }.count
            return count > 0 ? AIWorkflowRunCount(kind: kind, count: count) : nil
        }
        aiWorkflowProviderCounts = V0AIProviderRoute.allCases.compactMap { providerRoute in
            let count = state.aiWorkflowRuns.filter { $0.providerRoute == providerRoute }.count
            return count > 0 ? AIWorkflowProviderCount(providerRoute: providerRoute, count: count) : nil
        }
        paymentEventCount = state.betaEvents.filter { Self.paymentEventKinds.contains($0.kind) }.count
        let subscriptionAccess = state.subscriptionState.access(at: generatedAt)
        subscriptionHasAccess = subscriptionAccess.isEntitled
        subscriptionAccessStatus = subscriptionAccess.status
        subscriptionAccessSource = subscriptionAccess.source
        subscriptionNeedsPaywall = subscriptionAccess.shouldShowPaywall
        subscriptionFreeSprintDaysRemaining = subscriptionAccess.daysRemaining
        subscriptionRestoreStatus = state.subscriptionState.restoreState.status
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
        privacyNotice = "Private proof text, links, attachment paths, local file paths, and private notes are not included. Payment product IDs, customer identifiers, and management URLs are not included."
    }

    var searchableText: String {
        var lines = [
            "OpenLARP Beta Measurement Summary",
            "Generated: \(Self.formattedDate(generatedAt))",
            "Goal setup complete: \(goalSetupComplete ? "Yes" : "No")",
            "Total events: \(totalEvents)",
            "AI workflow runs: \(aiWorkflowRunCount)",
            "AI fallbacks: \(aiWorkflowFallbackCount)",
            "Payment events: \(paymentEventCount)",
            "Subscription access: \(subscriptionAccessStatus.label)",
            "Subscription source: \(subscriptionAccessSource.label)",
            "Subscription has access: \(subscriptionHasAccess ? "Yes" : "No")",
            "Subscription paywall needed: \(subscriptionNeedsPaywall ? "Yes" : "No")",
            "Subscription restore: \(subscriptionRestoreStatus.label)",
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

        if let subscriptionFreeSprintDaysRemaining {
            lines.append("Free sprint days remaining: \(subscriptionFreeSprintDaysRemaining)")
        }

        for count in eventCounts {
            lines.append("\(count.kind.label): \(count.count)")
        }
        for count in aiWorkflowKindCounts {
            lines.append("\(count.kind.rawValue): \(count.count)")
        }
        for count in aiWorkflowProviderCounts {
            lines.append("\(count.providerRoute.rawValue): \(count.count)")
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

    private static let paymentEventKinds: Set<BetaEventKind> = [
        .freeSprintStarted,
        .subscriptionStatusChecked,
        .subscriptionPaywallViewed,
        .subscriptionRestoreRequested,
        .subscriptionRestoreCompleted,
        .subscriptionRestoreFailed
    ]
}

extension JSONEncoder {
    static var openLARPBetaExport: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
