import Foundation
import Observation

@MainActor
@Observable
final class OpenLARPStore {
    private let persistence: OpenLARPPersistence
    private let attachmentStore: OpenLARPAttachmentStore
    private let aiWorkflowService: any V0AIWorkflowServicing
    private let agentService: CareerAgentBriefServicing
    private let careerGraphSyncService: any CareerGraphSyncServicing
    private let authenticationService: any OpenLARPAuthenticationServicing
    private let backendEventSyncService: any BackendEventSyncServicing
    private let privateEvidenceCloudSyncConsentService: any PrivateEvidenceCloudSyncConsentServicing
    private let privateEvidenceBackupCleanupService: any PrivateEvidenceBackupCleanupServicing
    private let accountDeletionService: any AccountDeletionServicing
    private let backendSessionProvider: any BackendSessionProviding
    private let subscriptionService: any OpenLARPSubscriptionServicing
    private let now: () -> Date
    private let calendar: Calendar
    private let backendEventRetryDelay: TimeInterval
    private let staleBackendEventInFlightAge: TimeInterval

    var state: OpenLARPState
    var pendingProof: ProofSubmission?
    var pendingQualityResult: QualityCheckResult?
    var errorMessage: String?
    var isAgentScanning = false
    var isGoalSetupRunning = false
    var isProofChecking = false
    var isPreparingCareerGraphSyncPreview = false
    var isRestoringAuthenticationSession = false
    var isSigningInWithGoogle = false
    var isSigningInWithApple = false
    var isSigningOutOfAccount = false
    var isSyncingBackendEvents = false
    var isUpdatingPrivateEvidenceCloudSyncConsent = false
    var isCheckingPrivateEvidenceBackups = false
    var isDeletingPrivateEvidenceBackups = false
    var isDeletingAccount = false
    var isRefreshingSubscriptionStatus = false
    var isRestoringPurchases = false
    var isLoadingSubscriptionOffering = false
    var isPurchasingSubscriptionPackage = false
    var authenticationResult: OpenLARPAuthenticationResult?
    var careerGraphSyncPreview: CareerGraphSyncPreview?
    var currentSubscriptionOffering: RevenueCatOfferingSnapshot?
    private var careerGraphSyncPreviewGeneration = 0
    private var activePrivateEvidenceBackupCleanupResult: PrivateEvidenceBackupCleanupResult?
    private var activeAccountDeletionResult: AccountDeletionResult?

    var isAccountDataOperationInFlight: Bool {
        isUpdatingPrivateEvidenceCloudSyncConsent ||
            isCheckingPrivateEvidenceBackups ||
            isDeletingPrivateEvidenceBackups ||
            isDeletingAccount
    }

    var privateEvidenceBackupCleanupResult: PrivateEvidenceBackupCleanupResult? {
        activePrivateEvidenceBackupCleanupResult ?? state.privateEvidenceBackupCleanupResult
    }

    var accountDeletionResult: AccountDeletionResult? {
        activeAccountDeletionResult ?? state.accountDeletionResult
    }

    init(
        persistence: OpenLARPPersistence = .live,
        attachmentStore: OpenLARPAttachmentStore = .live,
        aiWorkflowService: any V0AIWorkflowServicing = LocalMockV0AIWorkflowService(),
        agentService: CareerAgentBriefServicing = MockCareerAgentService(),
        careerGraphSyncService: any CareerGraphSyncServicing = LocalMockCareerGraphSyncService(),
        authenticationService: (any OpenLARPAuthenticationServicing)? = nil,
        backendEventSyncService: any BackendEventSyncServicing = LocalMockBackendEventSyncService(),
        privateEvidenceCloudSyncConsentService: any PrivateEvidenceCloudSyncConsentServicing = LocalMockPrivateEvidenceCloudSyncConsentService(),
        privateEvidenceBackupCleanupService: any PrivateEvidenceBackupCleanupServicing = LocalMockPrivateEvidenceBackupCleanupService(),
        accountDeletionService: any AccountDeletionServicing = LocalMockAccountDeletionService(),
        backendSessionProvider: (any BackendSessionProviding)? = nil,
        subscriptionService: any OpenLARPSubscriptionServicing = MockOpenLARPSubscriptionService(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        backendEventRetryDelay: TimeInterval = 300,
        staleBackendEventInFlightAge: TimeInterval = 900
    ) {
        self.persistence = persistence
        self.attachmentStore = attachmentStore
        self.aiWorkflowService = aiWorkflowService
        self.agentService = agentService
        self.careerGraphSyncService = careerGraphSyncService
        let resolvedAuthenticationService = authenticationService ?? MockOpenLARPAuthenticationService()
        self.authenticationService = resolvedAuthenticationService
        self.backendEventSyncService = backendEventSyncService
        self.privateEvidenceCloudSyncConsentService = privateEvidenceCloudSyncConsentService
        self.privateEvidenceBackupCleanupService = privateEvidenceBackupCleanupService
        self.accountDeletionService = accountDeletionService
        self.backendSessionProvider = backendSessionProvider ?? resolvedAuthenticationService
        self.subscriptionService = subscriptionService
        self.now = now
        self.calendar = calendar
        self.backendEventRetryDelay = backendEventRetryDelay
        self.staleBackendEventInFlightAge = staleBackendEventInFlightAge
        do {
            let loadedState = try persistence.load()
            let refreshedState = OpenLARPEngine.refreshDailyAvailability(
                in: loadedState,
                now: now(),
                calendar: calendar
            )
            state = refreshedState
            recordNextDayReturnIfNeeded(previousState: loadedState, refreshedState: refreshedState, at: now())
            if state != loadedState {
                do {
                    try persistence.save(state)
                } catch {
                    errorMessage = "Local progress could not be saved."
                }
            }
        } catch {
            state = .empty
            errorMessage = "Local progress could not be loaded. A fresh state was started."
        }
        restorePersistedProofDraft()
    }

    var isAuthenticationOperationInFlight: Bool {
        isRestoringAuthenticationSession ||
            isSigningInWithGoogle ||
            isSigningInWithApple ||
            isSigningOutOfAccount
    }

    func confirmGoal(_ goal: CareerGoal) async {
        guard !isGoalSetupRunning else { return }
        guard requireSubscriptionAccess(for: .confirmGoal) else { return }
        let previousProfile = state.userProfile
        let previousOutcomeLog = state.outcomeLog
        let previousBetaEvents = state.betaEvents
        let previousAIWorkflowRuns = state.aiWorkflowRuns
        let previousBackendEvents = state.backendEvents
        let previousSubscriptionState = state.subscriptionState
        let previousPrivateEvidenceBackupCleanupResult = state.privateEvidenceBackupCleanupResult
        let previousAccountDeletionResult = state.accountDeletionResult
        var completedAIWorkflowRuns: [V0AIWorkflowRun] = []
        let requestedAt = now()
        isGoalSetupRunning = true
        defer { isGoalSetupRunning = false }
        deletePendingProofAttachments()
        do {
            let diagnosticResponse = try await aiWorkflowService.generateDiagnostic(
                V0DiagnosticRequest(goal: goal, requestedAt: requestedAt)
            )
            completedAIWorkflowRuns.append(diagnosticResponse.run)
            let planResponse = try await aiWorkflowService.generateQuestPlan(
                V0QuestPlanRequest(
                    goal: goal,
                    diagnostic: diagnosticResponse.diagnostic,
                    requestedAt: requestedAt
                )
            )
            completedAIWorkflowRuns.append(planResponse.run)
            guard let plan = OpenLARPEngine.validatedInitialPlan(planResponse.quests) else {
                throw OpenLARPError.invalidQuestPlan
            }
            state = OpenLARPEngine.confirmGoal(
                goal,
                diagnostic: diagnosticResponse.diagnostic,
                plan: plan,
                now: requestedAt
            )
            errorMessage = nil
        } catch {
            state = OpenLARPEngine.confirmGoal(goal, now: requestedAt)
            errorMessage = "OpenLARP built a local plan on this device because the agent service was unavailable."
        }
        if let previousProfile, var refreshedProfile = state.userProfile {
            refreshedProfile.id = previousProfile.id
            refreshedProfile.accountID = previousProfile.accountID
            refreshedProfile.email = previousProfile.email
            refreshedProfile.displayName = previousProfile.displayName
            refreshedProfile.minutesPerDay = previousProfile.minutesPerDay
            refreshedProfile.networkingComfort = previousProfile.networkingComfort
            refreshedProfile.privacy = previousProfile.privacy
            refreshedProfile.createdAt = previousProfile.createdAt
            state.userProfile = refreshedProfile
        }
        state.outcomeLog = previousOutcomeLog
        state.betaEvents = previousBetaEvents
        state.aiWorkflowRuns = previousAIWorkflowRuns
        state.backendEvents = previousBackendEvents
        if previousSubscriptionState.hasStartedAccessLifecycle {
            state.subscriptionState = previousSubscriptionState
        }
        state.privateEvidenceBackupCleanupResult = previousPrivateEvidenceBackupCleanupResult
        state.accountDeletionResult = previousAccountDeletionResult
        let currentSession = currentBackendSession()
        if currentSession.isAuthenticated {
            applyAuthenticatedAccount(currentSession)
        }
        recordAIWorkflowRuns(completedAIWorkflowRuns)
        recordBackendEvent(
            .goalConfirmed,
            occurredAt: requestedAt,
            summary: BackendEventSummary(
                targetRoleTitle: goal.targetRole,
                readinessOverall: state.progress.readiness.overall,
                xp: state.progress.xp,
                proofCount: state.progress.proofCount
            )
        )
        recordBetaEvent(.goalConfirmed, occurredAt: requestedAt)
        recordBetaEvent(.diagnosticShown, occurredAt: requestedAt)
        recordFreeSprintStartedIfNeeded(at: requestedAt)
        state.agentBrief = AgentBriefFactory.makeBrief(for: state, generatedAt: requestedAt)
        pendingProof = nil
        pendingQualityResult = nil
        clearCareerGraphSyncPreview()
        clearPersistedProofDraft()
        save()
    }

    func resetGoal() {
        guard !isProofChecking else {
            errorMessage = "Wait for the proof check to finish before resetting your goal."
            return
        }
        var existingProfile = state.userProfile
        existingProfile?.updatedAt = now()
        let existingOutcomeLog = state.outcomeLog
        let existingBetaEvents = state.betaEvents
        let existingAIWorkflowRuns = state.aiWorkflowRuns
        let existingBackendEvents = state.backendEvents
        let existingSubscriptionState = state.subscriptionState
        let existingPrivateEvidenceBackupCleanupResult = state.privateEvidenceBackupCleanupResult
        let existingAccountDeletionResult = state.accountDeletionResult
        deletePendingProofAttachments()
        state = OpenLARPEngine.resetGoal(now: now())
        state.userProfile = existingProfile
        state.outcomeLog = existingOutcomeLog
        state.betaEvents = existingBetaEvents
        state.aiWorkflowRuns = existingAIWorkflowRuns
        state.backendEvents = existingBackendEvents
        state.subscriptionState = existingSubscriptionState
        state.privateEvidenceBackupCleanupResult = existingPrivateEvidenceBackupCleanupResult
        state.accountDeletionResult = existingAccountDeletionResult
        pendingProof = nil
        pendingQualityResult = nil
        clearCareerGraphSyncPreview()
        clearPersistedProofDraft()
        save()
    }

    func startCurrentQuest() {
        guard requireSubscriptionAccess(for: .startQuest) else { return }
        refreshDailyAvailability()
        let currentQuest = state.currentQuest
        let shouldRecordStart = currentQuest?.status == .available
        let isFirstQuestStart = state.progress.completedQuestCount == 0
            && !state.betaEvents.contains { $0.kind == .firstQuestStarted }
        do {
            state = try OpenLARPEngine.startCurrentQuest(in: state, now: now())
            if shouldRecordStart {
                if let currentQuest {
                    recordBackendEvent(
                        .questStarted,
                        occurredAt: now(),
                        entityID: currentQuest.id.uuidString,
                        summary: BackendEventSummary(
                            targetRoleTitle: state.goal?.targetRole,
                            questID: currentQuest.id,
                            questDay: currentQuest.day,
                            readinessOverall: state.progress.readiness.overall,
                            xp: state.progress.xp,
                            proofCount: state.progress.proofCount
                        )
                    )
                }
                recordBetaEvent(
                    isFirstQuestStart ? .firstQuestStarted : .questStarted,
                    day: currentQuest?.day
                )
            }
            errorMessage = nil
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipCurrentQuest() {
        guard requireSubscriptionAccess(for: .skipQuest) else { return }
        guard !isProofChecking else {
            errorMessage = "Wait for the proof check to finish before skipping today."
            return
        }
        refreshDailyAvailability()
        let skippedQuest = state.currentQuest
        do {
            state = try OpenLARPEngine.skipCurrentQuest(
                in: state,
                now: now(),
                calendar: calendar
            )
            recordBetaEvent(.questSkipped, day: skippedQuest?.day)
            deletePendingProofAttachments()
            pendingProof = nil
            pendingQualityResult = nil
            clearPersistedProofDraft()
            errorMessage = nil
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func swapCurrentQuest() {
        guard requireSubscriptionAccess(for: .swapQuest) else { return }
        mutate {
            try OpenLARPEngine.swappedCurrentQuest(in: state, now: now())
        }
    }

    func checkProof(
        kind: ProofKind,
        text: String,
        link: String,
        attachments: [ProofAttachment] = []
    ) async {
        guard requireSubscriptionAccess(for: .submitProof) else { return }
        guard !isProofChecking else { return }
        let questID = state.currentQuest?.id
        let questDay = state.currentQuest?.day
        let requestedAt = now()
        isProofChecking = true
        defer { isProofChecking = false }
        do {
            let proof = ProofSubmission(kind: kind, text: text, link: link, attachments: attachments, submittedAt: requestedAt)
            let response = try await aiWorkflowService.reviewProof(
                V0ProofReviewRequest(
                    state: state,
                    proof: proof,
                    requestedAt: requestedAt
                )
            )
            recordAIWorkflowRun(response.run)
            guard state.currentQuest?.id == questID else {
                state.updatedAt = now()
                save()
                return
            }
            let result = response.result
            deletePendingProofAttachments(excluding: proof.attachments)
            pendingProof = proof
            pendingQualityResult = result
            recordBackendEvent(
                .proofReviewed,
                occurredAt: requestedAt,
                entityID: proof.id.uuidString,
                summary: BackendEventSummary(
                    targetRoleTitle: state.goal?.targetRole,
                    questID: questID,
                    questDay: questDay,
                    proofID: proof.id,
                    readinessOverall: state.progress.readiness.overall,
                    xp: state.progress.xp,
                    proofCount: state.progress.proofCount,
                    qualityAccepted: result.isAccepted,
                    qualityScore: result.qualityScore
                )
            )
            recordBetaEvent(.proofSubmitted, occurredAt: requestedAt, day: questDay)
            recordBetaEvent(result.isAccepted ? .proofAccepted : .proofNeedsImprovement, occurredAt: requestedAt, day: questDay)
            errorMessage = nil
            persistProofDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func claimPendingQualityResult() {
        guard let pendingProof, let pendingQualityResult else { return }
        guard requireSubscriptionAccess(for: .claimProofXP) else { return }
        let quest = state.currentQuest
        do {
            state = try OpenLARPEngine.claim(
                pendingQualityResult,
                proof: pendingProof,
                in: state,
                now: now(),
                calendar: calendar
            )
            recordBackendEvent(
                .proofClaimed,
                entityID: pendingProof.id.uuidString,
                summary: BackendEventSummary(
                    targetRoleTitle: state.goal?.targetRole,
                    questID: quest?.id,
                    questDay: quest?.day,
                    proofID: pendingProof.id,
                    readinessOverall: state.progress.readiness.overall,
                    xp: state.progress.xp,
                    proofCount: state.progress.proofCount,
                    qualityAccepted: pendingQualityResult.isAccepted,
                    qualityScore: pendingQualityResult.qualityScore
                )
            )
            recordBetaEvent(.xpClaimed, day: quest?.day)
            self.pendingProof = nil
            self.pendingQualityResult = nil
            clearCareerGraphSyncPreview()
            clearPersistedProofDraft()
            errorMessage = nil
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardPendingQualityResult() {
        deletePendingProofAttachments()
        pendingProof = nil
        pendingQualityResult = nil
        clearPersistedProofDraft()
        save()
    }

    func improvePendingProofDraft() {
        pendingQualityResult = nil
        persistProofDraft()
        errorMessage = nil
    }

    func updateProfilePrivacy(
        memoryMode: CareerMemoryMode? = nil,
        shareWins: Bool? = nil
    ) {
        guard var profile = state.userProfile else { return }
        if let memoryMode {
            profile.privacy.memoryMode = memoryMode
        }
        if let shareWins {
            profile.privacy.shareWins = shareWins
        }
        profile.privacy.requireApprovalForExternalActions = true
        applyUpdatedProfilePrivacy(profile)
    }

    func setPrivateEvidenceCloudSyncEnabled(_ isEnabled: Bool) async {
        guard state.userProfile != nil else { return }
        guard !isUpdatingPrivateEvidenceCloudSyncConsent else {
            errorMessage = "Private evidence cloud sync is still updating."
            return
        }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before changing private evidence sync."
            return
        }

        let session = backendSessionProvider.currentSession(for: state)
        guard session.isAuthenticated else {
            if isEnabled {
                errorMessage = "Sign in before enabling private evidence cloud sync."
            } else {
                applyPrivateEvidenceCloudSyncConsent(false)
                errorMessage = nil
            }
            return
        }

        isUpdatingPrivateEvidenceCloudSyncConsent = true
        defer { isUpdatingPrivateEvidenceCloudSyncConsent = false }

        do {
            let request = PrivateEvidenceCloudSyncConsentRequest(
                session: session,
                enabled: isEnabled,
                requestedAt: now()
            )
            let result = try await privateEvidenceCloudSyncConsentService.setConsent(request)
            guard result.status == (isEnabled ? .accepted : .revoked),
                  result.allowsPrivateEvidenceCloudSync == isEnabled,
                  result.externalActionTaken == false
            else {
                throw FirebaseBackendServiceError.contractMismatch(
                    "Private evidence consent result did not match the requested setting."
                )
            }
            let currentSession = backendSessionProvider.currentSession(for: state)
            guard currentSession.isAuthenticated,
                  currentSession.ownerUserID == session.ownerUserID
            else {
                throw FirebaseBackendServiceError.contractMismatch(
                    "The signed-in account changed before private evidence consent finished."
                )
            }
            applyPrivateEvidenceCloudSyncConsent(isEnabled)
            errorMessage = nil
        } catch {
            errorMessage = isEnabled
                ? "Private evidence cloud sync could not be enabled."
                : "Private evidence cloud sync could not be turned off."
        }
    }

    private func applyPrivateEvidenceCloudSyncConsent(_ isEnabled: Bool) {
        guard var profile = state.userProfile else { return }
        profile.privacy.allowsPrivateEvidenceCloudSync = isEnabled
        profile.privacy.requireApprovalForExternalActions = true
        applyUpdatedProfilePrivacy(profile)
    }

    private func applyUpdatedProfilePrivacy(_ profile: CareerUserProfile) {
        var updatedProfile = profile
        updatedProfile.updatedAt = now()
        state.userProfile = updatedProfile
        clearCareerGraphSyncPreview()
        recordBackendEvent(
            .privacyUpdated,
            summary: BackendEventSummary(
                targetRoleTitle: state.goal?.targetRole,
                memoryMode: updatedProfile.privacy.memoryMode,
                shareWins: updatedProfile.privacy.shareWins,
                allowsPrivateEvidenceCloudSync: updatedProfile.privacy.allowsPrivateEvidenceCloudSync
            )
        )
        state.updatedAt = now()
        save()
    }

    func checkPrivateEvidenceBackupCleanupCandidates() async {
        guard !isCheckingPrivateEvidenceBackups else { return }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before checking synced private proof backups."
            return
        }
        let session = currentBackendSession()
        guard session.isAuthenticated else {
            errorMessage = "Sign in before checking synced private proof backups."
            return
        }

        let requestedAt = now()
        let request = PrivateEvidenceBackupCleanupRequest(
            session: session,
            mode: .reportOnly,
            requestedAt: requestedAt
        )

        isCheckingPrivateEvidenceBackups = true
        defer { isCheckingPrivateEvidenceBackups = false }

        do {
            let result = try await privateEvidenceBackupCleanupService.cleanUpBackups(request)
            guard currentBackendSession().ownerUserID == session.ownerUserID else {
                throw FirebaseBackendServiceError.contractMismatch(
                    "The signed-in account changed before backup cleanup reporting finished."
                )
            }
            activePrivateEvidenceBackupCleanupResult = result
            state.privateEvidenceBackupCleanupResult = sanitizedPrivateEvidenceBackupCleanupResult(result)
            recordBetaEvent(.privateEvidenceBackupCleanupReported, occurredAt: requestedAt)
            errorMessage = nil
            save()
        } catch {
            errorMessage = "Synced private proof backups could not be checked."
        }
    }

    func deletePrivateEvidenceBackups(attachmentIDs: [String]) async {
        guard !isDeletingPrivateEvidenceBackups else { return }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before deleting synced private proof backups."
            return
        }
        let session = currentBackendSession()
        guard session.isAuthenticated else {
            errorMessage = "Sign in before deleting synced private proof backups."
            return
        }

        let normalizedAttachmentIDs = Array(
            Set(
                attachmentIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("/") }
            )
        )
        .sorted()
        let eligibleAttachmentIDs = Set(
            activePrivateEvidenceBackupCleanupResult?.candidates
                .filter(\.canDelete)
                .map(\.attachmentID) ?? []
        )
        let deletionAttachmentIDs = normalizedAttachmentIDs.filter { eligibleAttachmentIDs.contains($0) }
        guard !deletionAttachmentIDs.isEmpty else {
            errorMessage = "Check synced proof backups first, then choose eligible attachments to delete."
            return
        }

        let requestedAt = now()
        let request = PrivateEvidenceBackupCleanupRequest(
            session: session,
            mode: .deleteSyncedEvidence,
            attachmentIDs: deletionAttachmentIDs,
            maxAttachments: max(25, deletionAttachmentIDs.count),
            confirmDeletion: true,
            requestedAt: requestedAt
        )

        isDeletingPrivateEvidenceBackups = true
        defer { isDeletingPrivateEvidenceBackups = false }

        do {
            let result = try await privateEvidenceBackupCleanupService.cleanUpBackups(request)
            guard currentBackendSession().ownerUserID == session.ownerUserID else {
                throw FirebaseBackendServiceError.contractMismatch(
                    "The signed-in account changed before backup cleanup deletion finished."
                )
            }
            let requestedAttachmentIDs = Set(deletionAttachmentIDs)
            let returnedAttachmentIDs = Set(result.candidates.map(\.attachmentID))
            guard returnedAttachmentIDs == requestedAttachmentIDs,
                  result.candidates.count == requestedAttachmentIDs.count
            else {
                throw FirebaseBackendServiceError.contractMismatch(
                    "Private evidence backup deletion response did not account for every requested attachment."
                )
            }
            activePrivateEvidenceBackupCleanupResult = result
            state.privateEvidenceBackupCleanupResult = sanitizedPrivateEvidenceBackupCleanupResult(result)
            recordBetaEvent(.privateEvidenceBackupCleanupDeleted, occurredAt: requestedAt)
            errorMessage = result.partialFailureCount > 0 || result.deletedCount < deletionAttachmentIDs.count
                ? "Some synced proof backups could not be deleted. The remaining items are listed in account data controls."
                : nil
            save()
        } catch {
            errorMessage = "Synced private proof backups could not be deleted."
        }
    }

    func deleteCloudAccount(
        confirmationText: String,
        presenting anchor: OpenLARPAuthenticationPresentationAnchor? = nil
    ) async {
        guard !isDeletingAccount else { return }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before deleting the cloud account."
            return
        }
        let session = currentBackendSession()
        guard session.isAuthenticated else {
            errorMessage = "Sign in before deleting the cloud account."
            return
        }
        guard confirmationText == AccountDeletionRequest.confirmationText else {
            errorMessage = "Type \(AccountDeletionRequest.confirmationText) exactly before deleting the cloud account."
            return
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        let preparationResult = await authenticationService.prepareAccountDeletion(
            presenting: anchor,
            for: state
        )
        authenticationResult = preparationResult
        guard preparationResult.status == .authenticated else {
            switch preparationResult.status {
            case .cancelled:
                errorMessage = nil
            case .signedOut:
                errorMessage = preparationResult.message ?? "Sign in again before deleting the cloud account."
            case .configurationMissing, .sdkUnavailable, .providerSetupRequired, .presentationRequired, .failed:
                errorMessage = preparationResult.message ?? "Cloud account deletion needs recent sign-in before it can continue."
            case .authenticated:
                break
            }
            return
        }
        guard currentBackendSession().ownerUserID == session.ownerUserID else {
            errorMessage = "The signed-in account changed before cloud account deletion could start."
            return
        }

        let requestedAt = now()
        let request = AccountDeletionRequest(
            session: session,
            confirmDeletion: true,
            confirmationText: confirmationText,
            requestedAt: requestedAt
        )
        let previousActiveAccountDeletionResult = activeAccountDeletionResult
        let previousAccountDeletionResult = state.accountDeletionResult
        let previousBetaEvents = state.betaEvents
        let unknownResult = AccountDeletionResult.unknownAfterRequestStarted(
            request: request,
            at: requestedAt
        )
        activeAccountDeletionResult = unknownResult
        state.accountDeletionResult = sanitizedAccountDeletionResult(unknownResult)
        recordBetaEvent(.accountDeletionRequested, occurredAt: requestedAt)
        guard save() else {
            activeAccountDeletionResult = previousActiveAccountDeletionResult
            state.accountDeletionResult = previousAccountDeletionResult
            state.betaEvents = previousBetaEvents
            errorMessage = "Cloud account deletion could not start because local support status could not be saved."
            return
        }

        do {
            let result = try await accountDeletionService.deleteAccount(request)
            guard currentBackendSession().ownerUserID == session.ownerUserID else {
                throw FirebaseBackendServiceError.contractMismatch(
                    "The signed-in account changed before cloud account deletion finished."
                )
            }
            activeAccountDeletionResult = result
            state.accountDeletionResult = sanitizedAccountDeletionResult(result)
            recordBetaEvent(
                result.status == .deleted ? .accountDeletionCompleted : .accountDeletionPartial,
                occurredAt: result.completedAt
            )

            if result.status == .deleted || result.firebaseAuthUser.status == .deleted || result.firebaseAuthUser.status == .alreadyMissing {
                let signOutResult = await authenticationService.signOut(for: state)
                if signOutResult.status == .signedOut {
                    applyAuthenticationResult(signOutResult, shouldSurfaceMessage: false)
                    await resetSubscriptionIdentityAfterSignOut()
                } else {
                    clearAuthenticatedAccount()
                    clearCareerGraphSyncPreview()
                    await resetSubscriptionIdentityAfterSignOut()
                }
                activeAccountDeletionResult = result
                state.accountDeletionResult = sanitizedAccountDeletionResult(result)
            }

            errorMessage = result.status == .deleted ? nil : partialAccountDeletionMessage(for: result)
            save()
        } catch {
            errorMessage = unknownAccountDeletionMessage()
            save()
        }
    }

    func restorePreviousAuthenticationSession() async {
        guard !isRestoringAuthenticationSession else { return }
        guard !isAccountDataOperationInFlight else { return }
        isRestoringAuthenticationSession = true
        defer { isRestoringAuthenticationSession = false }

        let result = await authenticationService.restorePreviousSession(for: state)
        applyAuthenticationResult(result, shouldSurfaceMessage: false)
        if result.status == .authenticated {
            await synchronizeSubscriptionIdentity(for: result.session)
        } else if result.status == .signedOut && shouldResetSubscriptionIdentityAfterSignedOutRestore {
            await resetSubscriptionIdentityAfterSignOut()
        }
    }

    func signInWithGoogle(presenting anchor: OpenLARPAuthenticationPresentationAnchor?) async {
        guard !isSigningInWithGoogle else { return }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before changing accounts."
            return
        }
        isSigningInWithGoogle = true
        defer { isSigningInWithGoogle = false }

        let result = await authenticationService.signInWithGoogle(presenting: anchor, for: state)
        applyAuthenticationResult(result, shouldSurfaceMessage: true)
        if result.status == .authenticated {
            await synchronizeSubscriptionIdentity(for: result.session)
            await syncBackendEvents()
        }
    }

    func signInWithApple(presenting anchor: OpenLARPAuthenticationPresentationAnchor?) async {
        guard !isSigningInWithApple else { return }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before changing accounts."
            return
        }
        isSigningInWithApple = true
        defer { isSigningInWithApple = false }

        let result = await authenticationService.signInWithApple(presenting: anchor, for: state)
        applyAuthenticationResult(result, shouldSurfaceMessage: true)
        if result.status == .authenticated {
            await synchronizeSubscriptionIdentity(for: result.session)
            await syncBackendEvents()
        }
    }

    func signOutOfAccount() async {
        guard !isSigningOutOfAccount else { return }
        guard !isAccountDataOperationInFlight else {
            errorMessage = "Wait for account data controls to finish before signing out."
            return
        }
        isSigningOutOfAccount = true
        defer { isSigningOutOfAccount = false }

        let result = await authenticationService.signOut(for: state)
        applyAuthenticationResult(result, shouldSurfaceMessage: true)
        if result.status == .signedOut {
            await resetSubscriptionIdentityAfterSignOut()
        }
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        authenticationService.handleOpenURL(url)
    }

    func logOutcome(
        kind: CareerOutcomeKind,
        title: String,
        organizationName: String = "",
        note: String = "",
        occurredAt: Date,
        isPrivate: Bool = true
    ) {
        guard !state.needsGoalSetup else {
            errorMessage = "Set a career goal before logging outcomes."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Add a short outcome title before saving."
            return
        }
        let timestamp = now()
        guard occurredAt <= timestamp else {
            errorMessage = "Choose today or a past date for the outcome."
            return
        }

        let relatedQuestID = state.currentQuest?.id ?? state.dailyCadence.lastCompletedQuestID
        let relatedProofID = relatedQuestID.flatMap { questID in
            state.progress.recentProof.first { $0.questID == questID }?.id
        } ?? state.progress.recentProof.first?.id
        let targetRole = state.targetRoles.first
        let targetRoleTitle = state.goal?.targetRole ?? targetRole?.title ?? "Career goal"
        let outcome = CareerOutcomeRecord(
            kind: kind,
            title: trimmedTitle,
            organizationName: organizationName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: occurredAt,
            createdAt: timestamp,
            updatedAt: timestamp,
            targetRoleID: targetRole?.id,
            targetRoleTitle: targetRoleTitle,
            relatedQuestID: relatedQuestID,
            relatedProofID: relatedProofID,
            isPrivate: isPrivate
        )

        state = OpenLARPEngine.logOutcome(outcome, in: state, now: timestamp)
        recordBackendEvent(
            .outcomeLogged,
            occurredAt: timestamp,
            entityID: outcome.id.uuidString,
            summary: BackendEventSummary(
                targetRoleTitle: targetRoleTitle,
                outcomeID: outcome.id,
                outcomeKind: outcome.kind,
                readinessOverall: state.progress.readiness.overall,
                xp: state.progress.xp,
                proofCount: state.progress.proofCount
            )
        )
        recordBetaEvent(.outcomeLogged, occurredAt: timestamp)
        clearCareerGraphSyncPreview()
        errorMessage = nil
        save()
    }

    func updateOutcome(
        id: UUID,
        kind: CareerOutcomeKind,
        title: String,
        organizationName: String = "",
        note: String = "",
        occurredAt: Date,
        isPrivate: Bool = true
    ) {
        guard let existingOutcome = state.outcomeLog.first(where: { $0.id == id }) else {
            errorMessage = "That outcome could not be found."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Add a short outcome title before saving."
            return
        }

        let timestamp = now()
        guard occurredAt <= timestamp else {
            errorMessage = "Choose today or a past date for the outcome."
            return
        }

        let updatedOutcome = CareerOutcomeRecord(
            id: existingOutcome.id,
            kind: kind,
            title: trimmedTitle,
            organizationName: organizationName.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            occurredAt: occurredAt,
            createdAt: existingOutcome.createdAt,
            updatedAt: timestamp,
            deletedAt: existingOutcome.deletedAt,
            targetRoleID: existingOutcome.targetRoleID,
            targetRoleTitle: existingOutcome.targetRoleTitle,
            relatedQuestID: existingOutcome.relatedQuestID,
            relatedProofID: existingOutcome.relatedProofID,
            isPrivate: isPrivate
        )

        state = OpenLARPEngine.updateOutcome(updatedOutcome, in: state, now: timestamp)
        recordBackendEvent(
            .outcomeUpdated,
            occurredAt: timestamp,
            summary: BackendEventSummary(
                targetRoleTitle: updatedOutcome.targetRoleTitle,
                outcomeID: updatedOutcome.id,
                outcomeKind: updatedOutcome.kind,
                readinessOverall: state.progress.readiness.overall,
                xp: state.progress.xp,
                proofCount: state.progress.proofCount
            )
        )
        clearCareerGraphSyncPreview()
        errorMessage = nil
        save()
    }

    func deleteOutcome(id: UUID) {
        guard let existingOutcome = state.outcomeLog.first(where: { $0.id == id }) else {
            errorMessage = "That outcome could not be found."
            return
        }

        let timestamp = now()
        state = OpenLARPEngine.deleteOutcome(id: id, in: state, now: timestamp)
        recordBackendEvent(
            .outcomeDeleted,
            occurredAt: timestamp,
            summary: BackendEventSummary(
                targetRoleTitle: existingOutcome.targetRoleTitle,
                outcomeID: existingOutcome.id,
                outcomeKind: existingOutcome.kind,
                readinessOverall: state.progress.readiness.overall,
                xp: state.progress.xp,
                proofCount: state.progress.proofCount
            )
        )
        clearCareerGraphSyncPreview()
        errorMessage = nil
        save()
    }

    func prepareCareerGraphSyncPreview(includePrivateEvidence explicitIncludePrivateEvidence: Bool? = nil) async {
        guard !isPreparingCareerGraphSyncPreview else { return }
        guard !state.needsGoalSetup else {
            errorMessage = "Set a career goal before previewing your career graph."
            return
        }
        guard requireSubscriptionAccess(for: .syncCareerGraph) else { return }

        let requestedAt = now()
        let session = currentBackendSession()
        let includePrivateEvidence = explicitIncludePrivateEvidence
            ?? (state.userProfile?.privacy.allowsPrivateEvidenceCloudSync ?? false)
        let previewGeneration = careerGraphSyncPreviewGeneration
        let request = CareerGraphSyncPreparationRequest(
            state: state,
            session: session,
            requestedAt: requestedAt,
            includePrivateEvidence: includePrivateEvidence
        )

        isPreparingCareerGraphSyncPreview = true
        defer { isPreparingCareerGraphSyncPreview = false }

        do {
            let result = try await careerGraphSyncService.prepareSync(request)
            guard previewGeneration == careerGraphSyncPreviewGeneration else { return }
            careerGraphSyncPreview = CareerGraphSyncPreview(request: request, result: result)
            recordBackendEvent(
                .syncPreviewPrepared,
                occurredAt: requestedAt,
                summary: BackendEventSummary(
                    targetRoleTitle: state.goal?.targetRole,
                    readinessOverall: state.progress.readiness.overall,
                    xp: state.progress.xp,
                    proofCount: state.progress.proofCount,
                    documentCount: result.firestoreDocumentPaths.count,
                    proofUploadCount: result.uploadIntents.count
                )
            )
            recordBetaEvent(.syncPreviewPrepared, occurredAt: requestedAt)
            errorMessage = nil
            save()
        } catch {
            guard previewGeneration == careerGraphSyncPreviewGeneration else { return }
            clearCareerGraphSyncPreview()
            errorMessage = "The local career graph preview could not be prepared."
        }
    }

    func syncBackendEvents(limit: Int = 25) async {
        guard !isSyncingBackendEvents else { return }
        let requestedAt = now()
        let events = Array(
            state.syncableBackendEvents(
                at: requestedAt,
                retryDelay: backendEventRetryDelay,
                staleInFlightAge: staleBackendEventInFlightAge
            )
            .prefix(max(0, limit))
        )
        guard !events.isEmpty else { return }

        let session = currentBackendSession()
        guard session.auth.status != .needsAuthentication else { return }
        guard !shouldHoldBackendEventsPendingForRemoteSetup(session) else { return }

        let eventIDs = Set(events.map(\.id))
        let previousBackendEvents = state.backendEvents
        if session.isAuthenticated {
            state.assignLocalBackendEvents(ids: eventIDs, toAuthenticatedOwner: session.ownerUserID)
        }
        state.markBackendEventsInFlight(ids: eventIDs, at: requestedAt)
        guard save() else {
            state.backendEvents = previousBackendEvents
            return
        }

        let eventsToSync = events.map { event in
            state.backendEvents.first { $0.id == event.id } ?? event
        }
        let request = BackendEventSyncRequest(
            session: session,
            events: eventsToSync,
            requestedAt: requestedAt
        )

        isSyncingBackendEvents = true
        defer { isSyncingBackendEvents = false }

        do {
            let result = try await backendEventSyncService.syncEvents(request)
            state.applyBackendEventSyncResult(result)
            errorMessage = nil
            save()
        } catch {
            state.markBackendEventsFailed(ids: eventIDs, at: requestedAt)
            errorMessage = "Backend event sync could not finish. OpenLARP will retry later."
            save()
        }
    }

    func recordCookedCardPrepared() {
        recordBetaEvent(.cookedCardPrepared)
        save()
    }

    func subscriptionAccess() -> OpenLARPSubscriptionAccess {
        state.subscriptionState.access(at: now(), calendar: calendar)
    }

    func subscriptionGateDecision(for action: OpenLARPAccessControlledAction) -> OpenLARPAccessGateDecision {
        OpenLARPAccessGate.decision(for: action, access: subscriptionAccess())
    }

    func recordSubscriptionPaywallViewed() {
        recordBetaEvent(.subscriptionPaywallViewed)
        save()
    }

    func loadSubscriptionOffering() async {
        guard !isLoadingSubscriptionOffering else { return }
        guard !isRefreshingSubscriptionStatus else { return }
        guard !isRestoringPurchases else { return }
        guard !isPurchasingSubscriptionPackage else { return }
        let requestedAt = now()

        isLoadingSubscriptionOffering = true
        defer { isLoadingSubscriptionOffering = false }

        do {
            state.subscriptionState.configuration = subscriptionService.subscriptionConfiguration
            let offering = try await subscriptionService.currentOffering()
            let hasPurchaseOption = offering?.preferredPurchasePackage(
                for: state.subscriptionState.configuration
            ) != nil
            currentSubscriptionOffering = hasPurchaseOption ? offering : nil
            recordBetaEvent(
                hasPurchaseOption
                    ? .subscriptionOfferingLoaded
                    : .subscriptionOfferingUnavailable,
                occurredAt: requestedAt
            )
            errorMessage = hasPurchaseOption
                ? nil
                : "Configured subscription options are not available yet."
            save()
        } catch {
            currentSubscriptionOffering = nil
            recordBetaEvent(.subscriptionOfferingUnavailable, occurredAt: requestedAt)
            errorMessage = "Subscription options could not be loaded."
            save()
        }
    }

    func refreshSubscriptionStatus() async {
        guard !isRefreshingSubscriptionStatus else { return }
        guard !isLoadingSubscriptionOffering else { return }
        guard !isRestoringPurchases else { return }
        guard !isPurchasingSubscriptionPackage else { return }
        let requestedAt = now()

        isRefreshingSubscriptionStatus = true
        defer { isRefreshingSubscriptionStatus = false }

        do {
            state.subscriptionState = try await subscriptionService.refreshSubscriptionState(
                currentState: state.subscriptionState,
                at: requestedAt
            )
            recordBetaEvent(.subscriptionStatusChecked, occurredAt: requestedAt)
            errorMessage = nil
            save()
        } catch {
            recordBetaEvent(.subscriptionStatusChecked, occurredAt: requestedAt)
            errorMessage = "Subscription status could not be refreshed."
            save()
        }
    }

    func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        guard !isLoadingSubscriptionOffering else { return }
        guard !isRefreshingSubscriptionStatus else { return }
        guard !isPurchasingSubscriptionPackage else { return }
        let requestedAt = now()
        state.subscriptionState = state.subscriptionState.restoreRequested(at: requestedAt)
        recordBetaEvent(.subscriptionRestoreRequested, occurredAt: requestedAt)
        save()

        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            state.subscriptionState = try await subscriptionService.restorePurchases(
                currentState: state.subscriptionState,
                at: requestedAt
            )
            let status = state.subscriptionState.restoreState.status
            recordBetaEvent(
                status == .restored ? .subscriptionRestoreCompleted : .subscriptionRestoreFailed,
                occurredAt: state.subscriptionState.restoreState.completedAt ?? now()
            )
            errorMessage = nil
            save()
        } catch {
            let failedAt = now()
            state.subscriptionState = state.subscriptionState.restoreFailed(at: failedAt)
            recordBetaEvent(.subscriptionRestoreFailed, occurredAt: failedAt)
            errorMessage = "Purchases could not be restored."
            save()
        }
    }

    func purchaseSubscriptionPackage(identifier: String, expectedProductID: String) async {
        guard !isPurchasingSubscriptionPackage else { return }
        guard !isLoadingSubscriptionOffering else { return }
        guard !isRefreshingSubscriptionStatus else { return }
        guard !isRestoringPurchases else { return }
        let requestedAt = now()

        isPurchasingSubscriptionPackage = true
        recordBetaEvent(.subscriptionPurchaseStarted, occurredAt: requestedAt)
        save()

        defer { isPurchasingSubscriptionPackage = false }

        do {
            let result = try await subscriptionService.purchasePackage(
                identifier: identifier,
                expectedProductID: expectedProductID,
                currentState: state.subscriptionState,
                at: requestedAt
            )
            state.subscriptionState = result.subscriptionState

            switch result.outcome {
            case .purchased:
                recordBetaEvent(.subscriptionPurchaseCompleted, occurredAt: now())
                errorMessage = nil
            case .cancelled:
                recordBetaEvent(.subscriptionPurchaseCancelled, occurredAt: now())
                errorMessage = nil
            case .failed(let failure):
                recordBetaEvent(.subscriptionPurchaseFailed, occurredAt: now())
                if failure == .noCurrentOffering || failure == .packageUnavailable {
                    currentSubscriptionOffering = nil
                }
                errorMessage = failure.message
            }
            save()
        } catch {
            recordBetaEvent(.subscriptionPurchaseFailed, occurredAt: now())
            errorMessage = "Subscription purchase could not be completed."
            save()
        }
    }

    func runAgentScan() async {
        guard !state.needsGoalSetup else { return }
        guard requireSubscriptionAccess(for: .runAgentScan) else { return }
        isAgentScanning = true
        defer { isAgentScanning = false }

        do {
            let brief = try await agentService.generateBrief(for: state)
            state.agentBrief = brief
            state.updatedAt = now()
            errorMessage = nil
            save()
        } catch {
            errorMessage = "The local agent scan could not finish. Try again from the Agent tab."
        }
    }

    func saveProofImage(
        data: Data,
        contentType: String,
        originalFileName: String = ""
    ) throws -> ProofAttachment {
        do {
            return try attachmentStore.saveImage(
                data: data,
                contentType: contentType,
                originalFileName: originalFileName
            )
        } catch {
            errorMessage = OpenLARPError.attachmentStorageFailed.localizedDescription
            throw OpenLARPError.attachmentStorageFailed
        }
    }

    func localURL(for attachment: ProofAttachment) -> URL {
        attachmentStore.url(for: attachment)
    }

    func refreshDailyAvailability() {
        let refreshedState = OpenLARPEngine.refreshDailyAvailability(
            in: state,
            now: now(),
            calendar: calendar
        )
        guard refreshedState != state else { return }
        let previousState = state
        state = refreshedState
        recordNextDayReturnIfNeeded(previousState: previousState, refreshedState: refreshedState, at: now())
        save()
    }

    func currentBackendSessionSnapshot() -> BackendUserSession {
        currentBackendSession()
    }

    func deleteProofImage(_ attachment: ProofAttachment) {
        do {
            try attachmentStore.delete(attachment)
        } catch {
            errorMessage = "That local proof image could not be removed."
        }
    }

    private func mutate(_ change: () throws -> OpenLARPState) {
        do {
            state = try change()
            errorMessage = nil
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordBetaEvent(
        _ kind: BetaEventKind,
        occurredAt: Date? = nil,
        day: Int? = nil
    ) {
        let event = BetaEventRecord(
            kind: kind,
            occurredAt: occurredAt ?? now(),
            day: day
        )
        state.betaEvents.append(event)
        if state.betaEvents.count > 500 {
            state.betaEvents.removeFirst(state.betaEvents.count - 500)
        }
    }

    @discardableResult
    private func requireSubscriptionAccess(for action: OpenLARPAccessControlledAction) -> Bool {
        let decision = subscriptionGateDecision(for: action)
        guard !decision.isAllowed else { return true }

        recordBetaEvent(.subscriptionPaywallViewed)
        errorMessage = "\(decision.title): \(decision.message)"
        save()
        return false
    }

    private func recordFreeSprintStartedIfNeeded(at timestamp: Date) {
        let access = state.subscriptionState.access(at: timestamp, calendar: calendar)
        guard access.status == .freeSprint else { return }
        guard !state.betaEvents.contains(where: { $0.kind == .freeSprintStarted }) else { return }

        recordBetaEvent(
            .freeSprintStarted,
            occurredAt: state.subscriptionState.freeSprint?.startedAt ?? timestamp
        )
    }

    private func shouldHoldBackendEventsPendingForRemoteSetup(_ session: BackendUserSession) -> Bool {
        if session.authProvider == .firebaseAuth && !session.isAuthenticated {
            return true
        }

        return session.auth.status == .notConnected &&
            session.firestore.status == .notConnected &&
            session.genkit.status == .configured
    }

    private func applyAuthenticationResult(
        _ result: OpenLARPAuthenticationResult,
        shouldSurfaceMessage: Bool
    ) {
        authenticationResult = result
        let previousAccountID = state.userProfile?.accountID

        switch result.status {
        case .authenticated:
            applyAuthenticatedAccount(result.session)
            let currentAccountID = result.session.accountID ?? result.session.ownerUserID
            if result.operation == .restorePreviousSession && previousAccountID != currentAccountID {
                recordBetaEvent(.accountSessionRestored, occurredAt: now())
            } else if isInteractiveSignIn(result.operation) {
                recordBetaEvent(.accountSignInCompleted, occurredAt: now())
            }
            clearCareerGraphSyncPreview()
            errorMessage = nil
            save()
        case .signedOut:
            if result.operation == .signOut || state.userProfile?.accountID != nil || state.userProfile?.email != nil {
                clearAuthenticatedAccount()
                if result.operation == .signOut {
                    recordBetaEvent(.accountSignedOut, occurredAt: now())
                }
                clearCareerGraphSyncPreview()
                errorMessage = nil
                save()
            }
        case .cancelled:
            if shouldSurfaceMessage {
                errorMessage = nil
            }
        case .configurationMissing, .sdkUnavailable, .providerSetupRequired, .presentationRequired, .failed:
            if isInteractiveSignIn(result.operation) {
                recordBetaEvent(.accountSignInFailed, occurredAt: now())
                save()
            }
            if shouldSurfaceMessage {
                errorMessage = result.message ?? "Account sign-in could not finish."
            }
        }
    }

    private func synchronizeSubscriptionIdentity(for session: BackendUserSession) async {
        guard session.isAuthenticated else { return }
        let requestedAt = now()
        do {
            let syncedState = try await subscriptionService.synchronizeSubscriberIdentity(
                session: session,
                currentState: state.subscriptionState,
                at: requestedAt
            )
            state.subscriptionState = syncedState
            recordBetaEvent(
                syncedState.connectionStatus == .failed
                    ? .subscriptionIdentityCheckFailed
                    : .subscriptionIdentityChecked,
                occurredAt: requestedAt
            )
            save()
        } catch {
            recordBetaEvent(.subscriptionIdentityCheckFailed, occurredAt: requestedAt)
            save()
        }
    }

    private func resetSubscriptionIdentityAfterSignOut() async {
        currentSubscriptionOffering = nil
        let requestedAt = now()
        let resetState = try? await subscriptionService.resetSubscriberIdentity(
            currentState: state.subscriptionState,
            at: requestedAt
        )
        guard let resetState else {
            state.subscriptionState.customerInfo = nil
            state.subscriptionState.connectionStatus = .notConfigured
            state.subscriptionState.lastUpdatedAt = requestedAt
            recordBetaEvent(.subscriptionIdentityReset, occurredAt: requestedAt)
            save()
            return
        }
        state.subscriptionState = resetState
        recordBetaEvent(.subscriptionIdentityReset, occurredAt: requestedAt)
        save()
    }

    private var shouldResetSubscriptionIdentityAfterSignedOutRestore: Bool {
        currentSubscriptionOffering != nil || state.subscriptionState.customerInfo != nil
    }

    private func applyAuthenticatedAccount(_ session: BackendUserSession) {
        guard var profile = state.userProfile else { return }
        let resolvedAccountID = session.accountID ?? session.ownerUserID
        if profile.accountID != resolvedAccountID {
            profile.privacy.allowsPrivateEvidenceCloudSync = false
            clearAccountDataControlResults(preservingPartialAccountDeletionSupport: true)
        }
        profile.accountID = resolvedAccountID
        profile.email = session.email
        profile.updatedAt = now()
        state.userProfile = profile
        state.updatedAt = profile.updatedAt
    }

    private func isInteractiveSignIn(_ operation: OpenLARPAuthenticationOperation) -> Bool {
        operation == .signInWithGoogle || operation == .signInWithApple
    }

    private func clearAuthenticatedAccount() {
        guard var profile = state.userProfile else { return }
        profile.accountID = nil
        profile.email = nil
        profile.privacy.allowsPrivateEvidenceCloudSync = false
        profile.updatedAt = now()
        state.userProfile = profile
        state.updatedAt = profile.updatedAt
        clearAccountDataControlResults(preservingPartialAccountDeletionSupport: true)
    }

    private func clearAccountDataControlResults(preservingPartialAccountDeletionSupport: Bool = false) {
        let preservedDeletionSupportResult: AccountDeletionResult?
        if preservingPartialAccountDeletionSupport,
           let result = state.accountDeletionResult,
           result.status == .partial || result.status == .unknown
        {
            preservedDeletionSupportResult = sanitizedAccountDeletionResult(result)
        } else {
            preservedDeletionSupportResult = nil
        }

        activePrivateEvidenceBackupCleanupResult = nil
        activeAccountDeletionResult = nil
        state.privateEvidenceBackupCleanupResult = nil
        state.accountDeletionResult = preservedDeletionSupportResult
    }

    private func partialAccountDeletionMessage(for result: AccountDeletionResult) -> String {
        if result.status == .unknown {
            return unknownAccountDeletionMessage()
        }

        switch result.firebaseAuthUser.status {
        case .deleted, .alreadyMissing:
            return "Cloud account deletion is partial after Firebase Auth was removed. Keep this result for support and contact support."
        case .skipped, .failed, .unknown:
            return "Cloud account deletion is partial. Keep this result for support and retry after reauthenticating."
        }
    }

    private func unknownAccountDeletionMessage() -> String {
        "Cloud account deletion started, but OpenLARP could not confirm the final backend result. Keep this status for support, sign in again, and retry before assuming cloud data still exists."
    }

    private func sanitizedPrivateEvidenceBackupCleanupResult(
        _ result: PrivateEvidenceBackupCleanupResult
    ) -> PrivateEvidenceBackupCleanupResult {
        var sanitized = result
        sanitized.candidates = result.candidates.enumerated().map { index, candidate in
            PrivateEvidenceBackupCleanupCandidate(
                attachmentID: "backup-\(index + 1)",
                proofID: nil,
                storagePath: "private proof backup",
                storageGeneration: nil,
                status: candidate.status,
                canDelete: false,
                deleted: candidate.deleted,
                reason: sanitizedBackupCleanupReason(for: candidate)
            )
        }
        return sanitized
    }

    private func sanitizedBackupCleanupReason(for candidate: PrivateEvidenceBackupCleanupCandidate) -> String {
        switch candidate.status {
        case .eligible:
            return "This synced private proof backup was eligible when checked. Run a fresh check before deleting."
        case .deleted:
            return "This synced private proof backup was deleted."
        case .storageDeleteFailed, .firestoreDeleteFailed:
            return "This synced private proof backup needs retry or support."
        case .missingFirestoreAttachment, .firestoreReceiptMismatch, .storageObjectMissing, .storageMetadataMismatch:
            return "This synced private proof backup was not eligible for deletion."
        }
    }

    private func sanitizedAccountDeletionResult(_ result: AccountDeletionResult) -> AccountDeletionResult {
        var sanitized = result
        sanitized.firestoreUserTree = sanitizedAccountDeletionScope(result.firestoreUserTree)
        sanitized.storageUserPrefix = sanitizedAccountDeletionScope(result.storageUserPrefix)
        sanitized.quotaUsageTree = sanitizedAccountDeletionScope(result.quotaUsageTree)
        sanitized.firebaseAuthUser.errorMessage = nil
        sanitized.deletionRequestMarker.errorMessage = nil
        return sanitized
    }

    private func sanitizedAccountDeletionScope(_ result: AccountDeletionScopeResult) -> AccountDeletionScopeResult {
        AccountDeletionScopeResult(
            status: result.status,
            deletedCount: result.deletedCount,
            attemptedCount: result.attemptedCount,
            failedCount: result.failedCount,
            failedPathSamples: nil,
            errorMessage: nil
        )
    }

    private func recordAIWorkflowRun(_ run: V0AIWorkflowRun) {
        state.recordAIWorkflowRun(run)
    }

    private func recordAIWorkflowRuns(_ runs: [V0AIWorkflowRun]) {
        for run in runs {
            recordAIWorkflowRun(run)
        }
    }

    private func recordBackendEvent(
        _ kind: BackendEventKind,
        occurredAt: Date? = nil,
        entityID: String? = nil,
        summary: BackendEventSummary = BackendEventSummary()
    ) {
        state.recordBackendEvent(
            BackendEventRecord(
                kind: kind,
                ownerUserID: currentBackendSession().ownerUserID,
                occurredAt: occurredAt ?? now(),
                entityID: entityID,
                summary: summary
            )
        )
    }

    private func currentBackendSession() -> BackendUserSession {
        backendSessionProvider.currentSession(for: state)
    }

    private func recordNextDayReturnIfNeeded(
        previousState: OpenLARPState,
        refreshedState: OpenLARPState,
        at timestamp: Date
    ) {
        let wasLockedForDay = previousState.dailyCadence.completedAt != nil || previousState.skippedToday.skippedAt != nil
        guard wasLockedForDay, previousState != refreshedState, refreshedState.currentQuest != nil else { return }
        let nextUnlockDate = previousState.dailyCadence.nextUnlockDate ?? previousState.skippedToday.nextUnlockDate
        guard let nextUnlockDate, calendar.isDate(nextUnlockDate, inSameDayAs: timestamp) else { return }
        let alreadyRecordedToday = refreshedState.betaEvents.contains { event in
            event.kind == .nextDayReturn && calendar.isDate(event.occurredAt, inSameDayAs: timestamp)
        }
        guard !alreadyRecordedToday else { return }
        recordBetaEvent(.nextDayReturn, occurredAt: timestamp, day: refreshedState.currentQuest?.day)
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try persistence.save(state)
            return true
        } catch {
            errorMessage = "Local progress could not be saved."
            return false
        }
    }

    private func deletePendingProofAttachments(excluding retainedAttachments: [ProofAttachment] = []) {
        guard let pendingProof else { return }
        let retainedAttachmentIDs = Set(retainedAttachments.map(\.id))

        for attachment in pendingProof.attachments where !retainedAttachmentIDs.contains(attachment.id) {
            do {
                try attachmentStore.delete(attachment)
            } catch {
                errorMessage = "Some local draft proof images could not be removed."
            }
        }
    }

    private func restorePersistedProofDraft() {
        guard state.currentQuest != nil else {
            let hadPersistedDraft = state.proofDraft != nil || state.proofDraftQualityResult != nil
            state.proofDraft = nil
            state.proofDraftQualityResult = nil
            pendingProof = nil
            pendingQualityResult = nil
            if hadPersistedDraft {
                save()
            }
            return
        }

        pendingProof = state.proofDraft
        pendingQualityResult = state.proofDraftQualityResult
    }

    private func persistProofDraft() {
        state.proofDraft = pendingProof
        state.proofDraftQualityResult = pendingQualityResult
        state.updatedAt = now()
        save()
    }

    private func clearPersistedProofDraft() {
        state.proofDraft = nil
        state.proofDraftQualityResult = nil
    }

    private func clearCareerGraphSyncPreview() {
        careerGraphSyncPreviewGeneration += 1
        careerGraphSyncPreview = nil
    }
}
