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
                detail: session.storage.status == .connected || session.storage.status == .configured
                    ? "Proof file backup also requires private evidence sync consent"
                    : "Files stay on this device",
                systemImage: "folder.fill",
                isComplete: (session.storage.status == .connected || session.storage.status == .configured)
                    && privacy.allowsPrivateEvidenceCloudSync
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
                detail: privacy.shareWins ? "Public share cards can mention wins" : "Public sharing stays off",
                systemImage: "square.and.arrow.up",
                isComplete: privacy.shareWins
            ),
            CareerGraphSetupStatusRow(
                title: "Private sync",
                value: privacy.allowsPrivateEvidenceCloudSync ? "Allowed" : "Local only",
                detail: privacy.allowsPrivateEvidenceCloudSync
                    ? "Private proof and outcomes may be included in account backup"
                    : "Private proof, files, and notes stay off cloud sync",
                systemImage: "lock.icloud.fill",
                isComplete: privacy.allowsPrivateEvidenceCloudSync
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
            : preview.didContactNetwork
                ? "Career graph synced"
                : "Career graph preview ready"
        subtitle = preview.didContactNetwork
            ? "OpenLARP synced metadata and uploaded available proof files through the backend-ready Firebase route."
            : "OpenLARP prepared your saved career graph locally. This preview did not upload or sync anything."
        nextStep = preview.requiresAuthenticationToSync
            ? "Sign in will be required before any real account backup."
            : preview.didContactNetwork
                ? "Your backed-up proof files now have upload receipts in the career graph metadata."
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
                value: preview.proofUploadedCount > 0
                    ? "\(preview.proofUploadedCount)/\(preview.proofUploadCount) backed up"
                    : Self.fileCountText(preview.proofUploadCount),
                detail: preview.didContactNetwork && preview.proofUploadedCount == preview.proofUploadCount
                    ? "\(Self.byteCountText(preview.proofUploadByteCount)) backed up to Firebase Storage"
                    : preview.proofUploadCount > 0
                    ? "\(Self.byteCountText(preview.proofUploadByteCount)) needs backup"
                    : "No proof files need backup",
                systemImage: "folder.fill",
                isComplete: preview.proofUploadedCount == preview.proofUploadCount
            ),
            CareerGraphSetupStatusRow(
                title: "Privacy",
                value: preview.includedPrivateEvidence
                    ? (preview.didContactNetwork ? "Synced to account" : "Included in preview")
                    : "Held back",
                detail: preview.allowsLongTermMemoryWrite
                    ? "Memory writes are allowed after account setup"
                    : "No long-term memory write is allowed by this preview",
                systemImage: "lock.shield.fill",
                isComplete: !preview.allowsLongTermMemoryWrite
            ),
            CareerGraphSetupStatusRow(
                title: "Network",
                value: preview.didContactNetwork ? "Firebase adapter" : "No network contact",
                detail: preview.didContactNetwork
                    ? "Firestore and Storage handled this account sync"
                    : "This preview was built on this device",
                systemImage: "antenna.radiowaves.left.and.right",
                isComplete: preview.didContactNetwork
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

struct CareerGraphSyncActionContent: Equatable {
    var title: String
    var progressLabel: String
    var systemImage: String
    var footnote: String

    init(
        isAuthenticated: Bool,
        privateEvidenceCloudSyncEnabled: Bool,
        proofFileCount: Int
    ) {
        if !isAuthenticated {
            title = "Preview Saved Career Graph"
            progressLabel = "Building Preview"
            systemImage = "arrow.triangle.2.circlepath"
            footnote = "This prepares a local preview only. It does not upload or sync anything."
            return
        }

        if privateEvidenceCloudSyncEnabled && proofFileCount > 0 {
            title = "Sync Career Graph & Proof Files"
            progressLabel = "Syncing Proof Files"
            systemImage = "icloud.and.arrow.up.fill"
            footnote = "This writes account-owned career graph metadata and private proof text, links, outcomes, and notes to Firestore, then uploads \(Self.proofFileCountText(proofFileCount)) to Firebase Storage because private evidence cloud sync is on."
            return
        }

        if privateEvidenceCloudSyncEnabled {
            title = "Sync Career Graph & Private Proof"
            progressLabel = "Syncing Private Proof"
            systemImage = "icloud.and.arrow.up.fill"
            footnote = "This writes account-owned career graph metadata plus private proof text, links, outcomes, and notes to Firestore. There are no proof files to upload yet."
            return
        }

        title = "Sync Career Graph Metadata"
        progressLabel = "Syncing Metadata"
        systemImage = "icloud.and.arrow.up"
        footnote = "This writes account-owned career graph metadata to Firestore. Private proof, files, and notes are not uploaded while private evidence sync is off."
    }

    private static func proofFileCountText(_ count: Int) -> String {
        count == 1 ? "1 proof file" : "\(count) proof files"
    }
}
