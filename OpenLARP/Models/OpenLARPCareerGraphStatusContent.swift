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
                title: "Account",
                value: session.isAuthenticated ? "Connected" : "Device only",
                detail: session.authProvider == .localMock ? "Local profile only" : session.authProvider.rawValue,
                systemImage: "person.crop.circle.badge.checkmark",
                isComplete: session.isAuthenticated
            ),
            CareerGraphSetupStatusRow(
                title: "Agent context",
                value: session.genkit.status == .localMock ? "On-device" : session.genkit.status.label,
                detail: "Career graph preview runs on this device",
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
                title: "File backup",
                value: Self.proofUploadValue(for: session.storage.status),
                detail: session.storage.status == .connected ? "File backup is available" : "Files stay on this device",
                systemImage: "folder.fill",
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
            nextActionDetail = "Your graph is prepared locally. Account setup is still future work."
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

struct CareerGraphSyncPreviewContent: Equatable {
    var title: String
    var subtitle: String
    var rows: [CareerGraphSetupStatusRow]
    var nextStep: String

    var displayText: String {
        ([title, subtitle, nextStep] + rows.flatMap { [$0.title, $0.value, $0.detail] })
            .joined(separator: " ")
    }

    init(preview: CareerGraphSyncPreview) {
        title = preview.status == .failed
            ? "Career graph preview needs retry"
            : "Career graph preview ready"
        subtitle = "OpenLARP prepared your saved career graph locally. This preview did not upload or sync anything."
        nextStep = preview.requiresAuthenticationToSync
            ? "Sign in will be required before any real account backup."
            : "Account backup can run once the backend route is connected."

        rows = [
            CareerGraphSetupStatusRow(
                title: "Saved records",
                value: preview.documentCount == 1 ? "1 prepared" : "\(preview.documentCount) prepared",
                detail: "Profile, goal, proof, outcomes, and readiness records",
                systemImage: "doc.on.doc.fill",
                isComplete: preview.documentCount > 0
            ),
            CareerGraphSetupStatusRow(
                title: "Local files",
                value: Self.fileCountText(preview.proofUploadCount),
                detail: preview.proofUploadCount > 0
                    ? "\(Self.byteCountText(preview.proofUploadByteCount)) would need backup later"
                    : "No proof files need backup",
                systemImage: "folder.fill",
                isComplete: preview.proofUploadCount > 0
            ),
            CareerGraphSetupStatusRow(
                title: "Privacy",
                value: preview.includedPrivateEvidence ? "In local preview" : "Held back",
                detail: preview.allowsLongTermMemoryWrite
                    ? "Memory writes are allowed after account setup"
                    : "No long-term memory write is allowed by this preview",
                systemImage: "lock.shield.fill",
                isComplete: !preview.allowsLongTermMemoryWrite
            ),
            CareerGraphSetupStatusRow(
                title: "Network",
                value: preview.didContactNetwork ? "Backend adapter" : "No network contact",
                detail: preview.didContactNetwork
                    ? "A backend adapter handled this preview"
                    : "This preview was built on this device",
                systemImage: "antenna.radiowaves.left.and.right",
                isComplete: !preview.didContactNetwork
            )
        ]
    }

    private static func fileCountText(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    private static func byteCountText(_ byteCount: Int) -> String {
        guard byteCount > 0 else { return "No bytes" }
        if byteCount < 1_000 {
            return "\(byteCount) bytes"
        }
        if byteCount < 1_000_000 {
            return "\(byteCount / 1_000) KB"
        }
        return "\(byteCount / 1_000_000) MB"
    }
}
