import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    let store: OpenLARPStore
    @State private var showingResetConfirmation = false
    @State private var selectedProof: ProofRecord?
    @State private var showingProofArchive = false
    @State private var outcomeSheetDestination: OutcomeSheetDestination?
    @State private var authenticationPresentationAnchor: OpenLARPAuthenticationPresentationAnchor?
    @State private var showingBackupCleanupConfirmation = false
    @State private var showingAccountDeletionConfirmation = false
    @State private var accountDeletionConfirmationText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .profile,
                    eyebrow: "Me",
                    title: "Career Hub",
                    subtitle: store.state.goal?.currentStatus.rawValue ?? "Set a goal to start the first proof sprint.",
                    stat: "L\(max(1, store.state.progress.completedQuestCount + 1))"
                )

                careerSummaryCard
                accountProfileCard
                accountDataControlsCard
                subscriptionStatusCard
                careerGraphSetupStatusCard
                betaMeasurementCard
                activeGoalCard
                recentOutcomesCard
                streakCard
                privacyCard
                badgeCard
                proofCard
                rulesCard
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProof) { proof in
            ProofDetailView(proof: proof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .sheet(isPresented: $showingProofArchive) {
            ProofArchiveView(proofs: store.state.progress.recentProof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .sheet(item: $outcomeSheetDestination) { destination in
            outcomeSheet(for: destination)
        }
        .confirmationDialog(
            "Change goal?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Goal And Local Plan", role: .destructive) {
                store.resetGoal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local diagnostic and questline so you can set a new target.")
        }
        .confirmationDialog(
            "Delete synced private proof backups?",
            isPresented: $showingBackupCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Eligible Backups", role: .destructive) {
                let attachmentIDs = privateEvidenceBackupDeletionIDs
                Task {
                    await store.deletePrivateEvidenceBackups(attachmentIDs: attachmentIDs)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(privateEvidenceBackupDeletionIDs.count) uploaded private proof backup file(s) that the backend reports as safe to delete. Local proof stays on this device.")
        }
        .alert(
            "Delete cloud account?",
            isPresented: $showingAccountDeletionConfirmation,
            actions: {
                TextField(AccountDeletionRequest.confirmationText, text: $accountDeletionConfirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Delete Cloud Account", role: .destructive) {
                    let confirmationText = accountDeletionConfirmationText
                    accountDeletionConfirmationText = ""
                    Task {
                        await store.deleteCloudAccount(confirmationText: confirmationText)
                    }
                }
                Button("Cancel", role: .cancel) {
                    accountDeletionConfirmationText = ""
                }
            },
            message: {
                Text("Type \(AccountDeletionRequest.confirmationText) exactly. This deletes cloud account data and Firebase Auth. Local on-device progress remains.")
            }
        )
        .alert(
            "OpenLARP",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .background(authenticationPresentationAnchorReader)
    }

    private var betaMeasurementCard: some View {
        let content = BetaMeasurementSummaryContent(state: store.state)

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .agent, eyebrow: "Local beta", title: "Measurement export")

                HStack(spacing: 8) {
                    SummaryTile(value: "\(content.totalEvents)", label: "Events", color: .openLARPBlue)
                    SummaryTile(value: "\(content.completedQuestCount)", label: "Done", color: .openLARPGreen)
                    SummaryTile(value: "\(content.readinessOverall)%", label: "Ready", color: .openLARPCoral)
                }

                Text(content.privacyNotice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                ShareLink(item: content.searchableText) {
                    Label("Export Beta Summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func outcomeSheet(for destination: OutcomeSheetDestination) -> some View {
        switch destination {
        case .log:
            OutcomeLogSheet { kind, title, organizationName, note, occurredAt, isPrivate in
                store.logOutcome(
                    kind: kind,
                    title: title,
                    organizationName: organizationName,
                    note: note,
                    occurredAt: occurredAt,
                    isPrivate: isPrivate
                )
            }
        case .detail(let outcome):
            OutcomeDetailView(
                outcome: outcome,
                isEditable: !store.state.needsGoalSetup,
                edit: {
                    outcomeSheetDestination = .edit(outcome)
                },
                delete: {
                    store.deleteOutcome(id: outcome.id)
                }
            )
        case .edit(let outcome):
            OutcomeLogSheet(outcome: outcome) { kind, title, organizationName, note, occurredAt, isPrivate in
                store.updateOutcome(
                    id: outcome.id,
                    kind: kind,
                    title: title,
                    organizationName: organizationName,
                    note: note,
                    occurredAt: occurredAt,
                    isPrivate: isPrivate
                )
            }
        }
    }

    private var careerSummaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .quest, eyebrow: "Sprint", title: "Momentum")

                SprintStrip(completed: store.state.progress.completedQuestCount)

                HStack(spacing: 8) {
                    SummaryTile(value: "\(store.state.progress.proofCount)", label: "Proof", color: .openLARPGreen)
                    SummaryTile(value: "\(store.state.progress.streakCount)", label: "Streak", color: .openLARPCoral)
                    SummaryTile(value: "\(store.state.progress.readiness.overall)%", label: "Ready", color: .openLARPBlue)
                }
            }
        }
    }

    private var subscriptionStatusCard: some View {
        let access = store.subscriptionAccess()

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .profile, eyebrow: "Access", title: "OpenLARP sprint")

                HStack(spacing: 8) {
                    SummaryTile(value: access.status.label, label: "Status", color: access.isEntitled ? .openLARPGreen : .openLARPCoral)
                    SummaryTile(value: "\(access.daysRemaining)", label: "Days", color: .openLARPBlue)
                }

                Text(subscriptionDetail(for: access))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await store.refreshSubscriptionStatus()
                        }
                    } label: {
                        if store.isRefreshingSubscriptionStatus {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Checking")
                            }
                        } else {
                            Label("Check Status", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.isRefreshingSubscriptionStatus || store.isRestoringPurchases)

                    if access.shouldShowPaywall {
                        restorePurchasesButton
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        restorePurchasesButton
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var restorePurchasesButton: some View {
        Button {
            Task {
                await store.restorePurchases()
            }
        } label: {
            if store.isRestoringPurchases {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Restoring")
                }
            } else {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        }
        .disabled(store.isRefreshingSubscriptionStatus || store.isRestoringPurchases)
    }

    private func subscriptionDetail(for access: OpenLARPSubscriptionAccess) -> String {
        switch access.status {
        case .notStarted:
            return "The first proof sprint starts when you set a career goal. No live RevenueCat purchase is required in local beta mode."
        case .active:
            return "A RevenueCat-shaped entitlement is active. Live SDK purchase verification still waits for App Store and RevenueCat setup."
        case .freeSprint:
            return "Your local free sprint is active. New quest and proof actions remain available while it is running."
        case .expired:
            return "Your sprint access has ended. Saved proof remains available, but new quest, proof, and agent actions require active access."
        case .offline:
            return "Offline entitlement access is active from cached RevenueCat customer info."
        case .restoreInProgress:
            return "OpenLARP is checking purchase history. New sprint actions wait until restore finishes."
        case .restoreFailed:
            return "No active subscription was restored. Restore again after RevenueCat and App Store products are configured."
        }
    }

    private var accountProfileCard: some View {
        let session = store.currentBackendSessionSnapshot()
        let result = store.authenticationResult

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .profile, eyebrow: "Account-ready", title: "User profile")

                if let profile = store.state.userProfile {
                    HStack(spacing: 8) {
                        SummaryTile(value: profile.segment.rawValue, label: "Segment", color: .openLARPBlue)
                        SummaryTile(value: "\(profile.minutesPerDay)m", label: "Daily", color: .openLARPGreen)
                    }

                    ProfileDetailRow(title: "Display name", value: profile.displayName)
                    ProfileDetailRow(title: "Memory mode", value: profile.privacy.memoryMode.label)
                    ProfileDetailRow(title: "Account sync", value: accountSyncStatusTitle(session: session, result: result))
                    if let email = session.email ?? profile.email {
                        ProfileDetailRow(title: "Account email", value: email)
                    }
                    ProfileDetailRow(title: "Profile record", value: "Saved on this device")
                    accountActionArea(session: session, result: result)
                } else {
                    Text("A local user profile is created after goal setup and can be linked to account sync later.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var accountDataControlsCard: some View {
        let session = store.currentBackendSessionSnapshot()
        let cleanupResult = store.privateEvidenceBackupCleanupResult
        let deletionResult = store.accountDeletionResult

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .privacy, eyebrow: "Account data", title: "Cloud controls")

                Text(accountDataControlsDetail(session: session))
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Private proof backups", systemImage: "externaldrive.badge.xmark")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text(privateEvidenceBackupCleanupSummary(cleanupResult))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let cleanupResult, !cleanupResult.candidates.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(cleanupResult.candidates.prefix(3)) { candidate in
                                PrivateEvidenceBackupCleanupCandidateRow(candidate: candidate)
                            }
                        }
                        if cleanupResult.candidates.count > 3 {
                            Text("\(cleanupResult.candidates.count - 3) more synced backup candidate(s) are included in the latest report.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await store.checkPrivateEvidenceBackupCleanupCandidates()
                            }
                        } label: {
                            if store.isCheckingPrivateEvidenceBackups {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Checking")
                                }
                            } else {
                                Label("Check Backups", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(
                            !session.isAuthenticated ||
                                store.isAuthenticationOperationInFlight ||
                                store.isCheckingPrivateEvidenceBackups ||
                                store.isDeletingPrivateEvidenceBackups ||
                                store.isDeletingAccount
                        )

                        Button {
                            showingBackupCleanupConfirmation = true
                        } label: {
                            if store.isDeletingPrivateEvidenceBackups {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Deleting")
                                }
                            } else {
                                Label("Delete Eligible", systemImage: "trash")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(
                            privateEvidenceBackupDeletionIDs.isEmpty ||
                                store.isAuthenticationOperationInFlight ||
                                store.isCheckingPrivateEvidenceBackups ||
                                store.isDeletingPrivateEvidenceBackups ||
                                store.isDeletingAccount
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Cloud account deletion", systemImage: "person.crop.circle.badge.xmark")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Color.openLARPInk)

                    Text(accountDeletionSummary(deletionResult))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deletionResult?.status == .partial ? Color.openLARPCoral : Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let deletionResult {
                        VStack(spacing: 8) {
                            AccountDeletionScopeRow(title: "Firestore data", result: deletionResult.firestoreUserTree)
                            AccountDeletionScopeRow(title: "Storage files", result: deletionResult.storageUserPrefix)
                            AccountDeletionScopeRow(title: "Quota records", result: deletionResult.quotaUsageTree)
                            AccountDeletionAuthRow(title: "Firebase Auth", result: deletionResult.firebaseAuthUser)
                            AccountDeletionMarkerRow(title: "Deletion marker", result: deletionResult.deletionRequestMarker)
                        }
                    }

                    Button {
                        accountDeletionConfirmationText = ""
                        showingAccountDeletionConfirmation = true
                    } label: {
                        if store.isDeletingAccount {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Deleting")
                            }
                        } else {
                            Label("Delete Cloud Account", systemImage: "trash.slash")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(
                        !session.isAuthenticated ||
                            store.isAuthenticationOperationInFlight ||
                            store.isCheckingPrivateEvidenceBackups ||
                            store.isDeletingPrivateEvidenceBackups ||
                            store.isDeletingAccount
                    )
                }
            }
        }
    }

    private var careerGraphSetupStatusCard: some View {
        let session = store.currentBackendSessionSnapshot()
        let content = CareerGraphSetupStatusContent(
            state: store.state,
            session: session
        )
        let syncAction = CareerGraphSyncActionContent(
            isAuthenticated: session.isAuthenticated,
            privateEvidenceCloudSyncEnabled: store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync ?? false,
            proofFileCount: shareableProofFileCount
        )

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .agent, eyebrow: "Account-ready", title: content.summaryTitle)

                Text(content.summarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(content.nextActionTitle, systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPBlue)
                    Pill(
                        title: session.isAuthenticated ? "Firestore metadata" : "Local only",
                        systemImage: session.isAuthenticated ? "icloud.fill" : "lock.fill",
                        color: session.isAuthenticated ? .openLARPBlue : .openLARPGreen
                    )
                }

                Text(content.nextActionDetail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(content.rows) { row in
                        CareerGraphStatusRow(row: row)
                    }
                }

                if let preview = store.careerGraphSyncPreview {
                    CareerGraphSyncPreviewSummary(content: CareerGraphSyncPreviewContent(preview: preview))
                }

                Button {
                    Task {
                        await store.prepareCareerGraphSyncPreview()
                    }
                } label: {
                    if store.isPreparingCareerGraphSyncPreview {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text(syncAction.progressLabel)
                        }
                    } else {
                        Label(
                            syncAction.title,
                            systemImage: syncAction.systemImage
                        )
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isPreparingCareerGraphSyncPreview || store.state.needsGoalSetup)
                .opacity(store.state.needsGoalSetup ? 0.45 : 1)

                Text(store.state.needsGoalSetup
                    ? "Set a career goal before previewing your career graph."
                    : syncAction.footnote)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shareableProofFileCount: Int {
        store.state.progress.recentProof.reduce(0) { count, proof in
            count + proof.attachments.count
        }
    }

    private var privateEvidenceBackupDeletionIDs: [String] {
        guard let result = store.privateEvidenceBackupCleanupResult else { return [] }
        return result.candidates
            .filter(\.canDelete)
            .map(\.attachmentID)
    }

    private func accountDataControlsDetail(session: BackendUserSession) -> String {
        if session.isAuthenticated {
            return "Use these controls for cloud data created by account sync. Local on-device progress is kept separate."
        }

        return "Sign in to check or delete cloud backups. Local on-device progress is still available without an account."
    }

    private func privateEvidenceBackupCleanupSummary(_ result: PrivateEvidenceBackupCleanupResult?) -> String {
        guard let result else {
            return "Check synced backups after turning off private evidence cloud sync or before deleting account data."
        }

        switch result.mode {
        case .reportOnly:
            if result.eligibleCount == 0 {
                return "Checked \(result.scannedCount) synced backup records. No eligible private proof backups were found."
            }
            return "\(result.eligibleCount) of \(result.scannedCount) synced private proof backups are eligible for deletion."
        case .deleteSyncedEvidence:
            if result.partialFailureCount > 0 {
                return "Deleted \(result.deletedCount) synced backups. \(result.partialFailureCount) item(s) still need retry or support."
            }
            return "Deleted \(result.deletedCount) synced private proof backup(s). Local proof receipts remain on this device."
        }
    }

    private func accountDeletionSummary(_ result: AccountDeletionResult?) -> String {
        guard let result else {
            return "Cloud account deletion requires recent sign-in and the exact confirmation phrase. Local progress remains on this device."
        }

        switch result.status {
        case .deleted:
            return "Cloud account deletion completed. Firebase Auth and account-owned cloud data were removed."
        case .partial:
            return "Cloud account deletion is partial. Retry after reauthenticating or keep this result for support."
        }
    }

    @ViewBuilder
    private var authenticationPresentationAnchorReader: some View {
        #if canImport(UIKit)
        AuthenticationPresentationAnchorReader { anchor in
            authenticationPresentationAnchor = anchor
        }
        #else
        EmptyView()
        #endif
    }

    private func accountActionArea(
        session: BackendUserSession,
        result: OpenLARPAuthenticationResult?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(accountSyncDetail(session: session, result: result))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)

            if let message = result?.message, !message.isEmpty {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.isAuthenticated {
                Button {
                    Task {
                        await store.signOutOfAccount()
                    }
                } label: {
                    if store.isSigningOutOfAccount {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Signing Out")
                        }
                    } else {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(store.isAuthenticationOperationInFlight || store.isAccountDataOperationInFlight)
            } else {
                VStack(spacing: 8) {
                    Button {
                        Task {
                            await store.signInWithGoogle(presenting: authenticationPresentationAnchor)
                        }
                    } label: {
                        if store.isSigningInWithGoogle {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Opening Google")
                            }
                        } else {
                            Label("Continue With Google", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.isAuthenticationOperationInFlight || store.isAccountDataOperationInFlight)

                    Button {
                        Task {
                            await store.restorePreviousAuthenticationSession()
                        }
                    } label: {
                        if store.isRestoringAuthenticationSession {
                            HStack {
                                ProgressView()
                                Text("Checking Session")
                            }
                        } else {
                            Label("Restore Previous Session", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.isAuthenticationOperationInFlight || store.isAccountDataOperationInFlight)
                }
            }
        }
        .padding(.top, 2)
    }

    private func accountSyncStatusTitle(
        session: BackendUserSession,
        result: OpenLARPAuthenticationResult?
    ) -> String {
        if session.isAuthenticated {
            return "Linked"
        }

        switch result?.status {
        case .configurationMissing:
            return "Firebase config needed"
        case .providerSetupRequired:
            return "Google provider needed"
        case .sdkUnavailable:
            return "SDK unavailable"
        case .presentationRequired:
            return "Sign-in presenter needed"
        case .failed:
            return "Sign-in failed"
        case .signedOut:
            return "Signed out"
        case .authenticated:
            return "Linked"
        case nil:
            return "Not connected yet"
        }
    }

    private func accountSyncDetail(
        session: BackendUserSession,
        result: OpenLARPAuthenticationResult?
    ) -> String {
        if session.isAuthenticated {
            return "OpenLARP can now assign backend events and future career graph uploads to your Firebase account."
        }

        switch result?.status {
        case .configurationMissing:
            return "The app is Firebase-ready, but this local build needs GoogleService-Info.plist and the Google callback URL scheme."
        case .providerSetupRequired:
            return "Enable the Google provider in Firebase Auth and add the reversed client ID URL scheme before live sign-in."
        case .sdkUnavailable:
            return "FirebaseAuth and GoogleSignIn must be linked in this build before live account sync."
        case .presentationRequired:
            return "Google Sign-In needs a presentation anchor from the current iOS screen."
        case .failed:
            return "The account session did not finish. Local OpenLARP progress is still available on this device."
        default:
            return "Connect Google to make this device profile account-backed. Local progress still works without signing in."
        }
    }

    @ViewBuilder
    private var recentOutcomesCard: some View {
        let content = OutcomeLogContent(outcomes: store.state.outcomeLog)
        if !content.outcomes.isEmpty {
            OutcomeLogCard(
                content: content,
                feature: .profile,
                eyebrow: "Private history",
                title: "Recent outcomes",
                recentLimit: 2,
                availability: store.state.needsGoalSetup
                    ? .readOnly("Set a new career goal before logging more outcomes. Existing outcomes stay saved as private history.")
                    : .available
            ) { outcome in
                outcomeSheetDestination = .detail(outcome)
            } logOutcome: {
                outcomeSheetDestination = .log
            }
        }
    }

    private var activeGoalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .profile, eyebrow: "Goal", title: "Active goal")

                if let goal = store.state.goal {
                    Text(goal.targetRole)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Pill(title: goal.timeline, systemImage: "calendar", color: .openLARPCoral)
                        Pill(title: "\(store.state.progress.proofCount) proof items", systemImage: "checkmark.seal", color: .openLARPGreen)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let targetRole = store.state.targetRoles.first {
                            ProfileDetailRow(title: "Role family", value: targetRole.roleFamily.rawValue)
                            ProfileDetailRow(title: "Seniority", value: targetRole.seniority.rawValue)
                            ProfileDetailRow(title: "Keywords", value: targetRole.keywords.joined(separator: ", "))
                        }
                        ProfileDetailRow(title: "Background", value: goal.background.isEmpty ? "Not provided yet" : goal.background)
                        ProfileDetailRow(title: "Existing proof", value: goal.existingProof.isEmpty ? "Thin or not provided yet" : goal.existingProof)
                        ProfileDetailRow(title: "Biggest blocker", value: goal.biggestBlocker.isEmpty ? "Not provided yet" : goal.biggestBlocker)
                    }

                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Change goal", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Text("Set a career target from Today to unlock the diagnostic, quest map, and progress baseline.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                }
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .privacy, eyebrow: "Private by default", title: "Memory and sharing")

                if store.state.userProfile == nil {
                    Text("Set a goal first to create local privacy controls for memory and sharing.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PrivacyToggleRow(
                        title: "Long-term memory",
                        detail: "Keep local context on this device.",
                        isOn: memoryBinding
                    )
                    PrivacyToggleRow(
                        title: "Shareable wins",
                        detail: "Allow proof wins to be shared later.",
                        isOn: shareWinsBinding
                    )
                    PrivacyToggleRow(
                        title: "Private evidence cloud sync",
                        detail: "Allow future proof, files, links, and private notes in account backup.",
                        isOn: privateEvidenceCloudSyncBinding
                    )
                    .disabled(store.isUpdatingPrivateEvidenceCloudSyncConsent)

                    Text("Turning this off stops future private evidence sync. Removing already synced proof backups is a separate cleanup request and is not full account deletion.")
                        .font(.caption)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(memoryEnabled ? "Local memory is on for this device. Real cloud memory is not built yet." : "Memory is off for future sensitive chats on this device.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("External actions always require approval.", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var memoryEnabled: Bool {
        store.state.userProfile?.privacy.memoryMode != .off
    }

    private var memoryBinding: Binding<Bool> {
        Binding(
            get: { memoryEnabled },
            set: { isOn in
                store.updateProfilePrivacy(memoryMode: isOn ? .localOnly : .off)
            }
        )
    }

    private var shareWinsBinding: Binding<Bool> {
        Binding(
            get: { store.state.userProfile?.privacy.shareWins ?? false },
            set: { isOn in
                store.updateProfilePrivacy(shareWins: isOn)
            }
        )
    }

    private var privateEvidenceCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync ?? false },
            set: { isOn in
                Task {
                    await store.setPrivateEvidenceCloudSyncEnabled(isOn)
                }
            }
        )
    }

    @ViewBuilder
    private var streakCard: some View {
        if !store.state.needsGoalSetup {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(feature: .recovery, eyebrow: "Not over", title: "Active streak")

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(store.state.progress.streakCount)")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(Color.openLARPCoral)

                        Text(store.state.progress.streakCount == 1 ? "day" : "days")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }

                    if let recovery = MissedDayRecoveryContent(state: store.state) {
                        Text("\(recovery.previousStreakText). \(recovery.missedDaysText) Continue from Today to rebuild the active streak.")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let skipped = SkippedTodayContent(state: store.state) {
                        Text("\(skipped.previousStreakText). \(skipped.unlockMessage)")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("This is the current live streak for the local quest track.")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var badgeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Proof wins", title: "Badges")

                if store.state.progress.badges.isEmpty {
                    Text("Lock a goal and submit proof to earn the first badges.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    FlowLayout(items: store.state.progress.badges.map(\.rawValue))
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Evidence bank", title: "Proof receipts")

                Button {
                    showingProofArchive = true
                } label: {
                    Label("Proof archive", systemImage: "archivebox")
                }
                .buttonStyle(SecondaryButtonStyle())

                if store.state.progress.recentProof.isEmpty {
                    Text("Recent proof will show up here after you complete a quest.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(store.state.progress.recentProof.prefix(3)) { proof in
                        Button {
                            selectedProof = proof
                        } label: {
                            ProofReceiptRow(proof: proof) { attachment in
                                store.localURL(for: attachment)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(feature: .privacy, eyebrow: "Rules", title: "Product guardrails")

                Label("Package real experience aggressively.", systemImage: "sparkles")
                Label("Never invent employers, schools, certificates, titles, dates, projects, or ownership.", systemImage: "checkmark.shield")
                Label("The agent drafts. You approve external actions.", systemImage: "hand.tap")
            }
            .font(.subheadline)
            .foregroundStyle(Color.openLARPSoftInk)
        }
    }
}

private struct PrivateEvidenceBackupCleanupCandidateRow: View {
    let candidate: PrivateEvidenceBackupCleanupCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: candidate.deleted ? "checkmark.circle.fill" : "doc.badge.gearshape")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .frame(width: 25, height: 25)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(candidate.attachmentID)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Text(candidate.status.rawValue)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(candidate.reason)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusColor: Color {
        if candidate.deleted {
            return .openLARPGreen
        }

        if candidate.canDelete {
            return .openLARPBlue
        }

        switch candidate.status {
        case .storageDeleteFailed, .firestoreDeleteFailed:
            return .openLARPCoral
        case .eligible, .deleted, .missingFirestoreAttachment, .firestoreReceiptMismatch, .storageObjectMissing, .storageMetadataMismatch:
            return .openLARPSoftInk
        }
    }
}

private struct AccountDeletionScopeRow: View {
    let title: String
    let result: AccountDeletionScopeResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.status == .completed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .frame(width: 25, height: 25)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Text(result.status.rawValue)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detail: String {
        var parts = ["deleted \(result.deletedCount)"]
        if let attemptedCount = result.attemptedCount {
            parts.append("attempted \(attemptedCount)")
        }
        if let failedCount = result.failedCount, failedCount > 0 {
            parts.append("failed \(failedCount)")
        }
        if result.status == .failed {
            parts.append("retry or contact support")
        }
        return parts.joined(separator: " | ")
    }

    private var statusColor: Color {
        result.status == .completed ? .openLARPGreen : .openLARPCoral
    }
}

private struct AccountDeletionAuthRow: View {
    let title: String
    let result: AccountDeletionAuthResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .frame(width: 25, height: 25)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Text(result.status.rawValue)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var isComplete: Bool {
        result.status == .deleted || result.status == .alreadyMissing
    }

    private var detail: String {
        switch result.status {
        case .deleted:
            return "Firebase Auth user was deleted."
        case .alreadyMissing:
            return "Firebase Auth user was already missing."
        case .skipped:
            return "Firebase Auth deletion was skipped because cloud data cleanup is incomplete."
        case .failed:
            return "Firebase Auth deletion failed. Retry after reauthenticating or contact support."
        }
    }

    private var statusColor: Color {
        isComplete ? .openLARPGreen : .openLARPCoral
    }
}

private struct AccountDeletionMarkerRow: View {
    let title: String
    let result: AccountDeletionMarkerResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.status == .completed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .frame(width: 25, height: 25)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Text(result.status.rawValue)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detail: String {
        result.status == .completed
            ? "Deletion marker finalized."
            : "Deletion marker finalization failed. Retry or contact support."
    }

    private var statusColor: Color {
        result.status == .completed ? .openLARPGreen : .openLARPCoral
    }
}

private struct CareerGraphStatusRow: View {
    let row: CareerGraphSetupStatusRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.systemImage)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .frame(width: 25, height: 25)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Text(row.value)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        if row.isComplete {
            return .openLARPGreen
        }

        let normalized = row.value.lowercased()
        if normalized.contains("local") || normalized.contains("mock") {
            return .openLARPPurple
        }

        if normalized.contains("missing") || normalized.contains("not connected") {
            return .openLARPCoral
        }

        return .openLARPSoftInk
    }
}

private struct CareerGraphSyncPreviewSummary: View {
    let content: CareerGraphSyncPreviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Label(content.title, systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.openLARPGreen)

                Text(content.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(content.rows) { row in
                    CareerGraphStatusRow(row: row)
                }
            }

            Text(content.nextStep)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

#if canImport(UIKit)
private struct AuthenticationPresentationAnchorReader: UIViewControllerRepresentable {
    let onResolve: (OpenLARPAuthenticationPresentationAnchor) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            onResolve(controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            onResolve(uiViewController)
        }
    }
}
#endif

private struct PrivacyToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.openLARPInk)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(.openLARPBlue)
        }
        .padding(12)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.openLARPGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.openLARPGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
