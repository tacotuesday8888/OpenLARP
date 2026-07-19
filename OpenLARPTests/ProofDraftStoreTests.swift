import UIKit
import XCTest
@testable import OpenLARP

@MainActor
final class ProofDraftStoreTests: XCTestCase {
    func testPreparingAndEditingDraftPersistsQuestOwnership() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())

        try fixture.store.updateProofDraftText(
            "A concrete description of the artifact I made today.",
            draftID: draftID
        )
        try fixture.store.updateProofDraftLink(
            "https://example.com/artifact",
            draftID: draftID
        )

        let questID = try XCTUnwrap(fixture.store.state.currentQuest?.id)
        XCTAssertEqual(fixture.store.pendingProof?.id, draftID)
        XCTAssertEqual(fixture.store.state.proofDraftQuestID, questID)
        XCTAssertEqual(fixture.store.state.proofDraft?.text, "A concrete description of the artifact I made today.")
        XCTAssertEqual(fixture.store.state.proofDraft?.link, "https://example.com/artifact")

        let reloaded = OpenLARPStore(
            persistence: fixture.persistence,
            attachmentStore: fixture.attachmentStore
        )
        XCTAssertEqual(reloaded.pendingProof?.id, draftID)
        XCTAssertEqual(reloaded.state.proofDraftQuestID, questID)
    }

    func testFourImagesCanBeStagedAcrossCallsAndFifthFailsWithoutWriting() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        let imageData = makePNG()

        for index in 1...ProofAttachmentPolicy.maximumCount {
            _ = try await fixture.store.stageProofImage(
                data: imageData,
                declaredContentType: "image/png",
                originalFileName: "proof-\(index).png",
                draftID: draftID
            )
        }

        do {
            _ = try await fixture.store.stageProofImage(
                data: imageData,
                declaredContentType: "image/png",
                originalFileName: "proof-5.png",
                draftID: draftID
            )
            XCTFail("A fifth draft image must fail closed.")
        } catch let error as OpenLARPProofDraftError {
            XCTAssertEqual(error, .attachmentLimitReached)
        }

        XCTAssertEqual(fixture.store.pendingProof?.attachments.count, 4)
        XCTAssertEqual(try draftFiles(in: fixture.directory, draftID: draftID).count, 4)
    }

    func testSwitchingToSelfReportClearsStagedAttachmentAndMetadata() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        let attachment = try await fixture.store.stageProofImage(
            data: makePNG(),
            declaredContentType: "image/png",
            originalFileName: "private.png",
            draftID: draftID
        )

        try fixture.store.changeProofDraftKind(to: .selfReport, draftID: draftID)

        XCTAssertEqual(fixture.store.pendingProof?.kind, .selfReport)
        XCTAssertEqual(fixture.store.pendingProof?.attachments, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.localURL(for: attachment).path))
        XCTAssertEqual(fixture.store.state.proofDraft?.attachments, [])
    }

    func testRemovingDraftAttachmentUpdatesPersistenceAndDeletesFile() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        let attachment = try await fixture.store.stageProofImage(
            data: makePNG(),
            declaredContentType: "image/png",
            draftID: draftID
        )

        try fixture.store.removeProofDraftAttachment(attachment.id, draftID: draftID)

        XCTAssertEqual(fixture.store.pendingProof?.attachments, [])
        XCTAssertEqual(fixture.store.state.proofDraft?.attachments, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.localURL(for: attachment).path))
    }

    func testDiscardPreventsDelayedStageFromRecreatingDraft() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())

        XCTAssertTrue(fixture.store.discardProofDraft(draftID: draftID))

        do {
            _ = try await fixture.store.stageProofImage(
                data: makePNG(),
                declaredContentType: "image/png",
                draftID: draftID
            )
            XCTFail("An abandoned draft ID must never be recreated by delayed work.")
        } catch let error as OpenLARPProofDraftError {
            XCTAssertEqual(error, .staleDraft)
        }

        XCTAssertNil(fixture.store.pendingProof)
        XCTAssertNil(fixture.store.state.proofDraft)
        XCTAssertNil(fixture.store.state.proofDraftQuestID)
        XCTAssertEqual(try draftFiles(in: fixture.directory, draftID: draftID), [])
    }

    func testSwapQuestDiscardsDraftAndStagedFiles() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        let attachment = try await fixture.store.stageProofImage(
            data: makePNG(),
            declaredContentType: "image/png",
            draftID: draftID
        )

        fixture.store.swapCurrentQuest()

        XCTAssertNil(fixture.store.pendingProof)
        XCTAssertNil(fixture.store.pendingQualityResult)
        XCTAssertNil(fixture.store.state.proofDraft)
        XCTAssertNil(fixture.store.state.proofDraftQuestID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.localURL(for: attachment).path))
    }

    func testResetGoalDiscardsDraftAndStagedFiles() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        let attachment = try await fixture.store.stageProofImage(
            data: makePNG(),
            declaredContentType: "image/png",
            draftID: draftID
        )

        fixture.store.resetGoal()

        XCTAssertTrue(fixture.store.state.needsGoalSetup)
        XCTAssertNil(fixture.store.pendingProof)
        XCTAssertNil(fixture.store.pendingQualityResult)
        XCTAssertNil(fixture.store.state.proofDraft)
        XCTAssertNil(fixture.store.state.proofDraftQuestID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.localURL(for: attachment).path))
    }

    func testClaimPromotesFilesAndStoresOnlyCommittedPaths() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        try fixture.store.updateProofDraftText(
            "I built a target-role artifact, documented the decisions, tested the result, and wrote the next improvement clearly.",
            draftID: draftID
        )
        let staged = try await fixture.store.stageProofImage(
            data: makePNG(),
            declaredContentType: "image/png",
            originalFileName: "artifact.png",
            draftID: draftID
        )

        await fixture.store.checkPendingProof(draftID: draftID)
        XCTAssertNotNil(fixture.store.pendingQualityResult)
        fixture.store.claimPendingQualityResult()

        let receipt = try XCTUnwrap(fixture.store.state.progress.recentProof.first)
        let committed = try XCTUnwrap(receipt.attachments.first)
        XCTAssertTrue(committed.localRelativePath.hasPrefix("ProofAttachments/"))
        XCTAssertFalse(committed.localRelativePath.hasPrefix("ProofAttachmentDrafts/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.store.localURL(for: committed).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.store.localURL(for: staged).path))
        XCTAssertNil(fixture.store.pendingProof)
        XCTAssertNil(fixture.store.state.proofDraftQuestID)
    }

    func testClaimPersistenceFailureRollsBackCommittedCopyAndKeepsDraft() async throws {
        let fixture = try await makeFixture()
        let draftID = try XCTUnwrap(fixture.store.prepareProofDraft())
        try fixture.store.updateProofDraftText(
            "I built a target-role artifact, documented the decisions, tested the result, and wrote the next improvement clearly.",
            draftID: draftID
        )
        let staged = try await fixture.store.stageProofImage(
            data: makePNG(),
            declaredContentType: "image/png",
            draftID: draftID
        )
        await fixture.store.checkPendingProof(draftID: draftID)
        XCTAssertNotNil(fixture.store.pendingQualityResult)

        try FileManager.default.removeItem(at: fixture.persistence.fileURL)
        try FileManager.default.createDirectory(at: fixture.persistence.fileURL, withIntermediateDirectories: true)

        fixture.store.claimPendingQualityResult()

        XCTAssertEqual(fixture.store.pendingProof?.id, draftID)
        XCTAssertNotNil(fixture.store.pendingQualityResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.store.localURL(for: staged).path))
        let committedURL = fixture.directory
            .appendingPathComponent("ProofAttachments", isDirectory: true)
            .appendingPathComponent(staged.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: committedURL.path))
        XCTAssertTrue(fixture.store.state.progress.recentProof.isEmpty)
    }

    func testStartupMigratesLegacyDraftAttachmentAndPreservesClaimedReceiptFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let legacyDraftAttachment = try attachmentStore.saveImage(
            data: makePNG(),
            contentType: "image/png",
            originalFileName: "legacy.png"
        )
        let claimedAttachment = try attachmentStore.saveImage(
            data: makePNG(),
            contentType: "image/png",
            originalFileName: "claimed.png"
        )
        let draft = ProofSubmission(
            kind: .proof,
            text: "A legacy persisted draft",
            attachments: [legacyDraftAttachment]
        )
        state.proofDraft = draft
        state.proofDraftQuestID = nil
        state.progress.recentProof = [
            ProofRecord(
                id: UUID(),
                questID: UUID(),
                questTitle: "Earlier quest",
                kind: .proof,
                text: "Claimed proof",
                link: "",
                attachments: [claimedAttachment],
                submittedAt: Date(),
                quality: nil
            )
        ]
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        let migrated = try XCTUnwrap(store.pendingProof?.attachments.first)
        XCTAssertEqual(migrated.id, legacyDraftAttachment.id)
        XCTAssertTrue(migrated.localRelativePath.hasPrefix("ProofAttachmentDrafts/\(draft.id.uuidString)/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.localURL(for: migrated).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentStore.url(for: legacyDraftAttachment).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentStore.url(for: claimedAttachment).path))
        XCTAssertEqual(store.state.proofDraftQuestID, store.state.currentQuest?.id)
    }

    func testStartupDropsCorruptLegacyAttachmentAndDeletesItsFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let corrupt = try attachmentStore.saveImage(
            data: Data("not-an-image".utf8),
            contentType: "image/png",
            originalFileName: "corrupt.png"
        )
        let draft = ProofSubmission(
            kind: .proof,
            text: "Recover this written note without the corrupt legacy image.",
            attachments: [corrupt]
        )
        state.proofDraft = draft
        state.proofDraftQuestID = state.currentQuest?.id
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertEqual(store.pendingProof?.attachments, [])
        XCTAssertEqual(store.state.proofDraft?.attachments, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentStore.url(for: corrupt).path))
        XCTAssertTrue(store.errorMessage?.contains("unavailable image") == true)
    }

    func testStartupDropsMissingStagedAttachmentMetadata() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let draftID = UUID()
        let missing = ProofAttachment(
            fileName: "missing.png",
            contentType: "image/png",
            byteCount: 512,
            localRelativePath: "ProofAttachmentDrafts/\(draftID.uuidString)/missing.png"
        )
        state.proofDraft = ProofSubmission(
            id: draftID,
            kind: .proof,
            text: "Keep the recovered written note but drop missing image metadata.",
            attachments: [missing]
        )
        state.proofDraftQuestID = state.currentQuest?.id
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        XCTAssertEqual(store.pendingProof?.attachments, [])
        XCTAssertEqual(store.state.proofDraft?.attachments, [])
        XCTAssertTrue(store.errorMessage?.contains("unavailable image") == true)
    }

    func testStartupDropsAttachmentOwnedByAnotherDraft() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let activeDraftID = UUID()
        let otherDraftID = UUID()
        let otherDraftAttachment = try attachmentStore.stageImage(
            ProcessedProofImage(
                data: makePNG(),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: otherDraftID
        )
        state.proofDraft = ProofSubmission(
            id: activeDraftID,
            kind: .proof,
            text: "This draft must not adopt another draft's private image.",
            attachments: [otherDraftAttachment]
        )
        state.proofDraftQuestID = state.currentQuest?.id
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertEqual(store.pendingProof?.attachments, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentStore.url(for: otherDraftAttachment).path))
    }

    func testStartupTrimsLegacyDraftToFourValidatedImages() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let legacyAttachments = try (1...5).map { index in
            try attachmentStore.saveImage(
                data: makePNG(),
                contentType: "image/png",
                originalFileName: "legacy-\(index).png"
            )
        }
        let draft = ProofSubmission(
            kind: .proof,
            text: "Recover only the supported maximum number of legacy proof images.",
            attachments: legacyAttachments
        )
        state.proofDraft = draft
        state.proofDraftQuestID = state.currentQuest?.id
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertEqual(store.pendingProof?.attachments.count, ProofAttachmentPolicy.maximumCount)
        XCTAssertTrue(
            store.pendingProof?.attachments.allSatisfy {
                $0.localRelativePath.hasPrefix("ProofAttachmentDrafts/\(draft.id.uuidString)/")
            } == true
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: attachmentStore.url(for: legacyAttachments[4]).path
            )
        )
    }

    func testStartupClearsLegacyImageInflatedPendingReviewBeforeClaim() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let legacyAttachment = try attachmentStore.saveImage(
            data: makePNG(),
            contentType: "image/png"
        )
        let draft = ProofSubmission(
            kind: .proof,
            text: "A short note.",
            attachments: [legacyAttachment]
        )
        state.proofDraft = draft
        state.proofDraftQuestID = state.currentQuest?.id
        state.proofDraftQualityResult = QualityCheckResult(
            isAccepted: true,
            qualityScore: 88,
            label: "Strong proof",
            reason: "The old review counted image metadata as inspected proof.",
            improvement: "Keep going.",
            xpEarned: 120,
            readinessDelta: 7
        )
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertNil(store.pendingQualityResult)
        XCTAssertNil(store.state.proofDraftQualityResult)
        store.claimPendingQualityResult()
        XCTAssertEqual(store.state.progress.xp, 0)
        XCTAssertEqual(store.state.progress.proofCount, 0)
        XCTAssertEqual(store.state.currentQuest?.status, .inProgress)
    }

    func testDiscardDoesNotDeleteClaimedFileSharedByLegacyDraftMetadata() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        var state = OpenLARPEngine.confirmGoal(testGoal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let claimed = try attachmentStore.saveImage(
            data: makePNG(),
            contentType: "image/png"
        )
        state.progress.recentProof = [
            ProofRecord(
                id: UUID(),
                questID: UUID(),
                questTitle: "Earlier quest",
                kind: .proof,
                text: "Claimed proof",
                link: "",
                attachments: [claimed],
                submittedAt: Date(),
                quality: nil
            )
        ]
        try persistence.save(state)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )
        var alias = claimed
        alias.id = UUID()
        let draft = ProofSubmission(
            kind: .proof,
            text: "Legacy draft metadata aliases an already claimed local file.",
            attachments: [alias]
        )
        store.pendingProof = draft
        store.state.proofDraft = draft
        store.state.proofDraftQuestID = store.state.currentQuest?.id

        XCTAssertTrue(store.discardProofDraft(draftID: draft.id))

        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentStore.url(for: claimed).path))
        XCTAssertEqual(store.state.progress.recentProof.first?.attachments.first?.id, claimed.id)
        XCTAssertEqual(
            store.state.progress.recentProof.first?.attachments.first?.localRelativePath,
            claimed.localRelativePath
        )
    }

    func testStartupDiscardsStaleDraftAndDeletesItsPrivateFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let draftID = UUID()
        let staged = try attachmentStore.stageImage(
            ProcessedProofImage(
                data: Data("stale-private-image".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: draftID
        )
        var state = OpenLARPState.empty
        state.proofDraft = ProofSubmission(
            id: draftID,
            kind: .proof,
            text: "Stale",
            attachments: [staged]
        )
        state.proofDraftQuestID = UUID()
        try persistence.save(state)

        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertNil(store.pendingProof)
        XCTAssertNil(store.state.proofDraft)
        XCTAssertNil(store.state.proofDraftQuestID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentStore.url(for: staged).path))
    }

    func testStartupReconciliationDeletesOnlyUnreferencedAttachmentFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let claimed = try attachmentStore.saveImage(
            data: Data("claimed".utf8),
            contentType: "image/png"
        )
        let orphanedCommitted = try attachmentStore.saveImage(
            data: Data("orphaned".utf8),
            contentType: "image/png"
        )
        let orphanedDraft = try attachmentStore.stageImage(
            ProcessedProofImage(
                data: Data("orphaned-draft".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: UUID()
        )
        var state = OpenLARPState.empty
        state.progress.recentProof = [
            ProofRecord(
                id: UUID(),
                questID: UUID(),
                questTitle: "Claimed quest",
                kind: .proof,
                text: "Claimed proof",
                link: "",
                attachments: [claimed],
                submittedAt: Date(),
                quality: nil
            )
        ]
        try persistence.save(state)

        _ = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentStore.url(for: claimed).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentStore.url(for: orphanedCommitted).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentStore.url(for: orphanedDraft).path))
    }

    private func makeFixture() async throws -> Fixture {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let attachmentStore = OpenLARPAttachmentStore(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: attachmentStore,
            releaseConfiguration: .appStoreMVP
        )
        await store.confirmGoal(testGoal)
        store.startCurrentQuest()
        XCTAssertEqual(store.state.currentQuest?.status, .inProgress)
        return Fixture(
            directory: directory,
            persistence: persistence,
            attachmentStore: attachmentStore,
            store: store
        )
    }

    private var testGoal: CareerGoal {
        CareerGoal(
            currentStatus: .student,
            targetRole: "iOS Engineer",
            timeline: "30 days",
            background: "Coursework and one small app",
            existingProof: "A class project",
            confidence: 3,
            biggestBlocker: "Not enough public work"
        )
    }

    private func makePNG() -> Data {
        let size = CGSize(width: 16, height: 16)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func draftFiles(in directory: URL, draftID: UUID) throws -> [URL] {
        let draftDirectory = directory
            .appendingPathComponent("ProofAttachmentDrafts", isDirectory: true)
            .appendingPathComponent(draftID.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: draftDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: draftDirectory,
            includingPropertiesForKeys: nil
        )
    }

    private struct Fixture {
        let directory: URL
        let persistence: OpenLARPPersistence
        let attachmentStore: OpenLARPAttachmentStore
        let store: OpenLARPStore
    }
}
