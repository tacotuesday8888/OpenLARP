import Foundation

struct CareerGraphSetupStatusRow: Codable, Equatable, Identifiable {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var isComplete: Bool

    var id: String { title }

    init(
        title: String,
        value: String,
        detail: String,
        systemImage: String = "circle",
        isComplete: Bool = false
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.isComplete = isComplete
    }
}

struct CareerGraphSetupStatusContent: Equatable {
    var summaryTitle: String
    var summarySubtitle: String
    var rows: [CareerGraphSetupStatusRow]
    var nextActionTitle: String
    var nextActionDetail: String

    init(state: OpenLARPState, session: BackendUserSession) {
        let privacy = state.userProfile?.privacy ?? .localDefault
        let visibleOutcomes = OutcomeLogContent(outcomes: state.outcomeLog).outcomes
        let proofCount = max(state.progress.proofCount, state.progress.recentProof.count)
        let latestProof = state.progress.recentProof.sorted { lhs, rhs in
            lhs.submittedAt > rhs.submittedAt
        }.first
        let hasGoal = state.goal != nil

        summaryTitle = "Career Graph"
        summarySubtitle = "What OpenLARP knows, what stays local, and what is ready for future account sync."
        rows = [
            CareerGraphSetupStatusRow(
                title: "Goal",
                value: hasGoal ? "Set" : "Missing",
                detail: state.goal?.targetRole ?? "No target role yet",
                systemImage: "target",
                isComplete: hasGoal
            ),
            CareerGraphSetupStatusRow(
                title: "Account sync",
                value: session.isAuthenticated ? "Connected" : "Not connected",
                detail: session.authProvider == .localMock ? "Local profile only" : session.authProvider.rawValue,
                systemImage: "person.crop.circle.badge.checkmark",
                isComplete: session.isAuthenticated
            ),
            CareerGraphSetupStatusRow(
                title: "Agent context",
                value: session.genkit.status.label,
                detail: "No client LLM or external action is required",
                systemImage: "sparkles",
                isComplete: session.genkit.status == .localMock || session.genkit.status == .connected
            ),
            CareerGraphSetupStatusRow(
                title: "Proof receipts",
                value: proofCount == 1 ? "1 saved" : "\(proofCount) saved",
                detail: latestProof.map { "Latest: \($0.questTitle)" } ?? "No proof receipts yet",
                systemImage: "doc.fill",
                isComplete: proofCount > 0
            ),
            CareerGraphSetupStatusRow(
                title: "Proof upload",
                value: Self.proofUploadValue(for: session.storage.status),
                detail: session.storage.status == .connected ? "Storage route available" : "Files stay on this device",
                systemImage: "icloud.and.arrow.up",
                isComplete: session.storage.status == .connected || session.storage.status == .configured
            ),
            CareerGraphSetupStatusRow(
                title: "Outcomes",
                value: visibleOutcomes.count == 1 ? "1 logged" : "\(visibleOutcomes.count) logged",
                detail: visibleOutcomes.first.map { "Latest: \($0.kind.label)" } ?? "No outcomes logged yet",
                systemImage: "flag.fill",
                isComplete: !visibleOutcomes.isEmpty
            ),
            CareerGraphSetupStatusRow(
                title: "Memory",
                value: privacy.memoryMode.label,
                detail: privacy.memoryMode == .cloudReady ? "May sync later after account setup" : "No cloud memory writes",
                systemImage: "brain.head.profile",
                isComplete: privacy.memoryMode != .off
            ),
            CareerGraphSetupStatusRow(
                title: "Sharing",
                value: privacy.shareWins ? "Allowed later" : "Private by default",
                detail: privacy.shareWins ? "Wins can be included in a future sync" : "Private evidence stays local by default",
                systemImage: "square.and.arrow.up",
                isComplete: privacy.shareWins
            )
        ]

        if !hasGoal {
            nextActionTitle = "Set career goal"
            nextActionDetail = "Lock a target role so the graph has a real direction."
        } else if proofCount == 0 {
            nextActionTitle = "Add first proof"
            nextActionDetail = "Complete one quest and save evidence the agent can reuse."
        } else if !session.isAuthenticated {
            nextActionTitle = "Connect account later"
            nextActionDetail = "Your graph is prepared locally. Firebase Auth is still future setup."
        } else {
            nextActionTitle = "Review sync status"
            nextActionDetail = "Your account-ready evidence graph has the basics connected."
        }
    }

    private static func proofUploadValue(for status: BackendIntegrationStatus) -> String {
        switch status {
        case .connected, .configured:
            status.label
        case .failed:
            "Needs attention"
        case .needsAuthentication:
            "Needs sign-in"
        case .notConnected, .localMock, .disabled:
            "Local only"
        }
    }
}
