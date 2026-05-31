import Foundation
import Observation

@MainActor
@Observable
final class OpenLARPStore {
    private let persistence: OpenLARPPersistence
    private let attachmentStore: OpenLARPAttachmentStore
    private let now: () -> Date
    private let calendar: Calendar

    var state: OpenLARPState
    var pendingProof: ProofSubmission?
    var pendingQualityResult: QualityCheckResult?
    var errorMessage: String?

    init(
        persistence: OpenLARPPersistence = .live,
        attachmentStore: OpenLARPAttachmentStore = .live,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.persistence = persistence
        self.attachmentStore = attachmentStore
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
    }

    func confirmGoal(_ goal: CareerGoal) {
        state = OpenLARPEngine.confirmGoal(goal, now: now())
        pendingProof = nil
        pendingQualityResult = nil
        save()
    }

    func resetGoal() {
        state = OpenLARPEngine.resetGoal(now: now())
        pendingProof = nil
        pendingQualityResult = nil
        save()
    }

    func startCurrentQuest() {
        refreshDailyAvailability()
        mutate {
            try OpenLARPEngine.startCurrentQuest(in: state, now: now())
        }
    }

    func skipCurrentQuest() {
        refreshDailyAvailability()
        do {
            state = try OpenLARPEngine.skipCurrentQuest(
                in: state,
                now: now(),
                calendar: calendar
            )
            pendingProof = nil
            pendingQualityResult = nil
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
            state = try OpenLARPEngine.claim(
                pendingQualityResult,
                proof: pendingProof,
                in: state,
                now: now(),
                calendar: calendar
            )
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
}
