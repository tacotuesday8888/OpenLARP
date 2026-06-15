import Foundation
import Observation

@MainActor
@Observable
final class OpenLARPStore {
    private let persistence: OpenLARPPersistence
    private let attachmentStore: OpenLARPAttachmentStore
    private let aiWorkflowService: any V0AIWorkflowServicing
    private let agentService: CareerAgentBriefServicing
    private let now: () -> Date
    private let calendar: Calendar

    var state: OpenLARPState
    var pendingProof: ProofSubmission?
    var pendingQualityResult: QualityCheckResult?
    var errorMessage: String?
    var isAgentScanning = false
    var isGoalSetupRunning = false
    var isProofChecking = false

    init(
        persistence: OpenLARPPersistence = .live,
        attachmentStore: OpenLARPAttachmentStore = .live,
        aiWorkflowService: any V0AIWorkflowServicing = LocalMockV0AIWorkflowService(),
        agentService: CareerAgentBriefServicing = MockCareerAgentService(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.persistence = persistence
        self.attachmentStore = attachmentStore
        self.aiWorkflowService = aiWorkflowService
        self.agentService = agentService
        self.now = now
        self.calendar = calendar
        do {
            let loadedState = try persistence.load()
            state = OpenLARPEngine.refreshDailyAvailability(
                in: loadedState,
                now: now(),
                calendar: calendar
            )
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
        let requestedAt = now()
        isGoalSetupRunning = true
        defer { isGoalSetupRunning = false }
        deletePendingProofAttachments()
        do {
            let diagnosticResponse = try await aiWorkflowService.generateDiagnostic(
                V0DiagnosticRequest(goal: goal, requestedAt: requestedAt)
            )
            let planResponse = try await aiWorkflowService.generateQuestPlan(
                V0QuestPlanRequest(
                    goal: goal,
                    diagnostic: diagnosticResponse.diagnostic,
                    requestedAt: requestedAt
                )
            )
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
        pendingProof = nil
        pendingQualityResult = nil
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
        deletePendingProofAttachments()
        state = OpenLARPEngine.resetGoal(now: now())
        state.userProfile = existingProfile
        pendingProof = nil
        pendingQualityResult = nil
        clearPersistedProofDraft()
        save()
    }

    func startCurrentQuest() {
        refreshDailyAvailability()
        mutate {
            try OpenLARPEngine.startCurrentQuest(in: state, now: now())
        }
    }

    func skipCurrentQuest() {
        guard !isProofChecking else {
            errorMessage = "Wait for the proof check to finish before skipping today."
            return
        }
        refreshDailyAvailability()
        do {
            state = try OpenLARPEngine.skipCurrentQuest(
                in: state,
                now: now(),
                calendar: calendar
            )
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
        isProofChecking = true
        defer { isProofChecking = false }
        do {
            let proof = ProofSubmission(kind: kind, text: text, link: link, attachments: attachments)
            let response = try await aiWorkflowService.reviewProof(
                V0ProofReviewRequest(
                    state: state,
                    proof: proof,
                    requestedAt: now()
                )
            )
            guard state.currentQuest?.id == questID else { return }
            let result = response.result
            deletePendingProofAttachments(excluding: proof.attachments)
            pendingProof = proof
            pendingQualityResult = result
            errorMessage = nil
            persistProofDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func claimPendingQualityResult() {
        guard let pendingProof, let pendingQualityResult else { return }
        do {
            state = try OpenLARPEngine.claim(
                pendingQualityResult,
                proof: pendingProof,
                in: state,
                now: now(),
                calendar: calendar
            )
            self.pendingProof = nil
            self.pendingQualityResult = nil
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
        state.updatedAt = now()
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
        state = refreshedState
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
}
