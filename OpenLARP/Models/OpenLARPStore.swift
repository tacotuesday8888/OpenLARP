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
    private let now: () -> Date
    private let calendar: Calendar

    var state: OpenLARPState
    var pendingProof: ProofSubmission?
    var pendingQualityResult: QualityCheckResult?
    var errorMessage: String?
    var isAgentScanning = false
    var isGoalSetupRunning = false
    var isProofChecking = false
    var isPreparingCareerGraphSyncPreview = false
    var careerGraphSyncPreview: CareerGraphSyncPreview?
    private var careerGraphSyncPreviewGeneration = 0

    init(
        persistence: OpenLARPPersistence = .live,
        attachmentStore: OpenLARPAttachmentStore = .live,
        aiWorkflowService: any V0AIWorkflowServicing = LocalMockV0AIWorkflowService(),
        agentService: CareerAgentBriefServicing = MockCareerAgentService(),
        careerGraphSyncService: any CareerGraphSyncServicing = LocalMockCareerGraphSyncService(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.persistence = persistence
        self.attachmentStore = attachmentStore
        self.aiWorkflowService = aiWorkflowService
        self.agentService = agentService
        self.careerGraphSyncService = careerGraphSyncService
        self.now = now
        self.calendar = calendar
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

    func confirmGoal(_ goal: CareerGoal) async {
        guard !isGoalSetupRunning else { return }
        let previousPrivacy = state.userProfile?.privacy
        let previousOutcomeLog = state.outcomeLog
        let previousBetaEvents = state.betaEvents
        let previousAIWorkflowRuns = state.aiWorkflowRuns
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
        if let previousPrivacy {
            state.userProfile?.privacy = previousPrivacy
        }
        state.outcomeLog = previousOutcomeLog
        state.betaEvents = previousBetaEvents
        state.aiWorkflowRuns = previousAIWorkflowRuns
        recordAIWorkflowRuns(completedAIWorkflowRuns)
        recordBetaEvent(.goalConfirmed, occurredAt: requestedAt)
        recordBetaEvent(.diagnosticShown, occurredAt: requestedAt)
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
        deletePendingProofAttachments()
        state = OpenLARPEngine.resetGoal(now: now())
        state.userProfile = existingProfile
        state.outcomeLog = existingOutcomeLog
        state.betaEvents = existingBetaEvents
        state.aiWorkflowRuns = existingAIWorkflowRuns
        pendingProof = nil
        pendingQualityResult = nil
        clearCareerGraphSyncPreview()
        clearPersistedProofDraft()
        save()
    }

    func startCurrentQuest() {
        refreshDailyAvailability()
        let currentQuest = state.currentQuest
        let shouldRecordStart = currentQuest?.status == .available
        let isFirstQuestStart = state.progress.completedQuestCount == 0
            && !state.betaEvents.contains { $0.kind == .firstQuestStarted }
        do {
            state = try OpenLARPEngine.startCurrentQuest(in: state, now: now())
            if shouldRecordStart {
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
        let quest = state.currentQuest
        do {
            state = try OpenLARPEngine.claim(
                pendingQualityResult,
                proof: pendingProof,
                in: state,
                now: now(),
                calendar: calendar
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

    func updateProfilePrivacy(memoryMode: CareerMemoryMode? = nil, shareWins: Bool? = nil) {
        guard var profile = state.userProfile else { return }
        if let memoryMode {
            profile.privacy.memoryMode = memoryMode
        }
        if let shareWins {
            profile.privacy.shareWins = shareWins
        }
        profile.privacy.requireApprovalForExternalActions = true
        profile.updatedAt = now()
        state.userProfile = profile
        clearCareerGraphSyncPreview()
        state.updatedAt = now()
        save()
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
        clearCareerGraphSyncPreview()
        errorMessage = nil
        save()
    }

    func deleteOutcome(id: UUID) {
        guard state.outcomeLog.contains(where: { $0.id == id }) else {
            errorMessage = "That outcome could not be found."
            return
        }

        state = OpenLARPEngine.deleteOutcome(id: id, in: state, now: now())
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

        let requestedAt = now()
        let session = BackendUserSession.localOnly(for: state)
        let includePrivateEvidence = explicitIncludePrivateEvidence ?? (state.userProfile?.privacy.shareWins ?? false)
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
            recordBetaEvent(.syncPreviewPrepared, occurredAt: requestedAt)
            errorMessage = nil
            save()
        } catch {
            guard previewGeneration == careerGraphSyncPreviewGeneration else { return }
            clearCareerGraphSyncPreview()
            errorMessage = "The local career graph preview could not be prepared."
        }
    }

    func recordCookedCardPrepared() {
        recordBetaEvent(.cookedCardPrepared)
        save()
    }

    func runAgentScan() async {
        guard !state.needsGoalSetup else { return }
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

    private func recordAIWorkflowRun(_ run: V0AIWorkflowRun) {
        state.recordAIWorkflowRun(run)
    }

    private func recordAIWorkflowRuns(_ runs: [V0AIWorkflowRun]) {
        for run in runs {
            recordAIWorkflowRun(run)
        }
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

    private func save() {
        do {
            try persistence.save(state)
        } catch {
            errorMessage = "Local progress could not be saved."
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
