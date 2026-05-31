import Foundation
import Observation

@MainActor
@Observable
final class OpenLARPStore {
    private let persistence: OpenLARPPersistence
    private let attachmentStore: OpenLARPAttachmentStore

    var state: OpenLARPState
    var pendingProof: ProofSubmission?
    var pendingQualityResult: QualityCheckResult?
    var errorMessage: String?

    init(
        persistence: OpenLARPPersistence = .live,
        attachmentStore: OpenLARPAttachmentStore = .live
    ) {
        self.persistence = persistence
        self.attachmentStore = attachmentStore
        do {
            state = try persistence.load()
        } catch {
            state = .empty
            errorMessage = "Local progress could not be loaded. A fresh state was started."
        }
    }

    func confirmGoal(_ goal: CareerGoal) {
        state = OpenLARPEngine.confirmGoal(goal)
        pendingProof = nil
        pendingQualityResult = nil
        save()
    }

    func resetGoal() {
        state = OpenLARPEngine.resetGoal()
        pendingProof = nil
        pendingQualityResult = nil
        save()
    }

    func startCurrentQuest() {
        mutate {
            try OpenLARPEngine.startCurrentQuest(in: state)
        }
    }

    func swapCurrentQuest() {
        mutate {
            try OpenLARPEngine.swappedCurrentQuest(in: state)
        }
    }

    func checkProof(
        kind: ProofKind,
        text: String,
        link: String,
        attachments: [ProofAttachment] = []
    ) {
        do {
            let proof = ProofSubmission(kind: kind, text: text, link: link, attachments: attachments)
            let result = try OpenLARPEngine.checkProof(proof, in: state)
            pendingProof = proof
            pendingQualityResult = result
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func claimPendingQualityResult() {
        guard let pendingProof, let pendingQualityResult else { return }
        do {
            state = try OpenLARPEngine.claim(pendingQualityResult, proof: pendingProof, in: state)
            self.pendingProof = nil
            self.pendingQualityResult = nil
            errorMessage = nil
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardPendingQualityResult() {
        pendingProof = nil
        pendingQualityResult = nil
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
}
