import Foundation
import XCTest
@testable import OpenLARP

final class ProofAttachmentStoreLifecycleTests: XCTestCase {
    func testStageImageWritesOnlyInsideDraftDirectory() throws {
        let directory = temporaryDirectory()
        let store = OpenLARPAttachmentStore(directory: directory)
        let draftID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let createdAt = Date(timeIntervalSince1970: 100)
        let image = ProcessedProofImage(
            data: Data("private-image".utf8),
            contentType: "image/png",
            fileExtension: "png"
        )

        let attachment = try store.stageImage(
            image,
            draftID: draftID,
            originalFileName: "../screenshot.png",
            now: createdAt
        )

        XCTAssertTrue(attachment.localRelativePath.hasPrefix("ProofAttachmentDrafts/\(draftID.uuidString)/"))
        XCTAssertFalse(attachment.localRelativePath.hasPrefix("ProofAttachments/"))
        XCTAssertEqual(attachment.originalFileName, "screenshot.png")
        XCTAssertEqual(attachment.contentType, "image/png")
        XCTAssertEqual(attachment.byteCount, image.data.count)
        XCTAssertEqual(attachment.createdAt, createdAt)
        XCTAssertEqual(try store.data(for: attachment), image.data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: attachment).path))
    }

    func testPrepareAndFinalizePromotionCopiesThenCommitsDraftAttachment() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let draftID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let staged = try store.stageImage(
            ProcessedProofImage(
                data: Data("claim-me".utf8),
                contentType: "image/jpeg",
                fileExtension: "jpg"
            ),
            draftID: draftID,
            originalFileName: "claim.jpg"
        )

        let promotion = try store.preparePromotion([staged], draftID: draftID)
        let committed = try XCTUnwrap(promotion.committedAttachments.first)

        XCTAssertEqual(promotion.stagedAttachments, [staged])
        XCTAssertEqual(committed.id, staged.id)
        XCTAssertEqual(committed.fileName, staged.fileName)
        XCTAssertEqual(committed.localRelativePath, "ProofAttachments/\(staged.fileName)")
        XCTAssertEqual(try store.data(for: committed), Data("claim-me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: staged).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: committed).path))

        try store.finalizePromotion(promotion)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: staged).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: committed).path))
    }

    func testDraftAndCommittedFilesReceiveDifferentBackupPolicies() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let draftID = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
        let staged = try store.stageImage(
            ProcessedProofImage(
                data: Data("backup-policy".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: draftID
        )

        XCTAssertTrue(try isExcludedFromBackup(store.url(for: staged)))

        let promotion = try store.preparePromotion([staged], draftID: draftID)
        let committed = try XCTUnwrap(promotion.committedAttachments.first)

        XCTAssertFalse(try isExcludedFromBackup(store.url(for: committed)))
    }

    func testRollbackPromotionDeletesCommittedCopyAndKeepsDraft() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let draftID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let staged = try store.stageImage(
            ProcessedProofImage(
                data: Data("keep-editable".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: draftID
        )
        let promotion = try store.preparePromotion([staged], draftID: draftID)
        let committed = try XCTUnwrap(promotion.committedAttachments.first)

        try store.rollbackPromotion(promotion)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: staged).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: committed).path))
    }

    func testPreparePromotionRollsBackEarlierCopiesWhenLaterAttachmentIsUnsafe() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let draftID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let staged = try store.stageImage(
            ProcessedProofImage(
                data: Data("first".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: draftID
        )
        let unsafe = ProofAttachment(
            fileName: "outside.png",
            contentType: "image/png",
            byteCount: 1,
            localRelativePath: "../outside.png"
        )

        XCTAssertThrowsError(try store.preparePromotion([staged, unsafe], draftID: draftID)) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .notStagedAttachment)
        }

        let committedURL = store.directory
            .appendingPathComponent("ProofAttachments", isDirectory: true)
            .appendingPathComponent(staged.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: committedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: staged).path))
    }

    func testPreparePromotionRejectsAttachmentOwnedByAnotherDraft() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let firstDraftID = UUID(uuidString: "45454545-4545-4545-4545-454545454545")!
        let secondDraftID = UUID(uuidString: "46464646-4646-4646-4646-464646464646")!
        let staged = try store.stageImage(
            ProcessedProofImage(
                data: Data("belongs-to-first-draft".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: firstDraftID
        )

        XCTAssertThrowsError(
            try store.preparePromotion([staged], draftID: secondDraftID)
        ) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .notStagedAttachment)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: staged).path))
    }

    func testPreparePromotionRejectsMoreThanFourAttachments() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let draftID = UUID()
        let staged = try (1...5).map { index in
            try store.stageImage(
                ProcessedProofImage(
                    data: Data("image-\(index)".utf8),
                    contentType: "image/png",
                    fileExtension: "png"
                ),
                draftID: draftID
            )
        }

        XCTAssertThrowsError(
            try store.preparePromotion(staged, draftID: draftID)
        ) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .attachmentLimitExceeded)
        }
    }

    func testDeleteRejectsTraversalAndPreservesOutsideFile() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outsideURL = directory.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        try Data("keep".utf8).write(to: outsideURL)
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        let store = OpenLARPAttachmentStore(directory: directory)
        let unsafe = ProofAttachment(
            fileName: outsideURL.lastPathComponent,
            contentType: "image/png",
            byteCount: 4,
            localRelativePath: "../\(outsideURL.lastPathComponent)"
        )

        XCTAssertThrowsError(try store.delete(unsafe)) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .unsafeLocalPath)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path))
    }

    func testDeleteDraftRemovesOnlyThatDraftDirectory() throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let firstDraftID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let secondDraftID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let image = ProcessedProofImage(
            data: Data("draft".utf8),
            contentType: "image/png",
            fileExtension: "png"
        )
        let first = try store.stageImage(image, draftID: firstDraftID)
        let second = try store.stageImage(image, draftID: secondDraftID)

        try store.deleteDraft(firstDraftID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: second).path))
    }

    func testStageRejectsSymlinkedDraftRootWithoutWritingOutsideStore() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outsideDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: true
        )
        let draftRoot = directory.appendingPathComponent("ProofAttachmentDrafts", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: draftRoot,
            withDestinationURL: outsideDirectory
        )
        let draftID = UUID()
        let store = OpenLARPAttachmentStore(directory: directory)

        XCTAssertThrowsError(
            try store.stageImage(
                ProcessedProofImage(
                    data: Data("must-stay-contained".utf8),
                    contentType: "image/png",
                    fileExtension: "png"
                ),
                draftID: draftID
            )
        ) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .unsafeLocalPath)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: outsideDirectory.appendingPathComponent(draftID.uuidString).path
            )
        )
    }

    func testDeleteDraftRejectsSymlinkedDraftDirectoryAndPreservesTarget() throws {
        let directory = temporaryDirectory()
        let draftRoot = directory.appendingPathComponent("ProofAttachmentDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: draftRoot, withIntermediateDirectories: true)
        let outsideDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: true
        )
        let outsideFile = outsideDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: outsideFile)
        let draftID = UUID()
        try FileManager.default.createSymbolicLink(
            at: draftRoot.appendingPathComponent(draftID.uuidString),
            withDestinationURL: outsideDirectory
        )
        let store = OpenLARPAttachmentStore(directory: directory)

        XCTAssertThrowsError(try store.deleteDraft(draftID)) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .unsafeLocalPath)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    func testReconcileRejectsSymlinkedCommittedRootAndPreservesTarget() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outsideDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: true
        )
        let outsideFile = outsideDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("ProofAttachments", isDirectory: true),
            withDestinationURL: outsideDirectory
        )
        let store = OpenLARPAttachmentStore(directory: directory)

        XCTAssertThrowsError(try store.reconcile(referencedAttachments: [])) { error in
            XCTAssertEqual(error as? OpenLARPAttachmentStoreError, .unsafeLocalPath)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    func testCloudUploadCannotReadStagedAttachment() async throws {
        let store = OpenLARPAttachmentStore(directory: temporaryDirectory())
        let draftID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let staged = try store.stageImage(
            ProcessedProofImage(
                data: Data("never-upload-a-draft".utf8),
                contentType: "image/png",
                fileExtension: "png"
            ),
            draftID: draftID
        )
        let proofID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let cloudAttachment = CloudProofAttachmentDocument(
            attachment: staged,
            ownerUserID: "firebase_uid_draft_boundary",
            proofID: proofID
        )
        let uploadIntent = CareerGraphSyncUploadIntent(
            proofID: proofID.uuidString,
            attachment: cloudAttachment
        )

        do {
            _ = try await store.data(for: uploadIntent)
            XCTFail("Draft attachments must never be eligible for cloud upload.")
        } catch let error as CareerGraphProofAttachmentDataError {
            XCTAssertEqual(error, .unsafeLocalPath)
        }
    }

    func testCloudUploadRejectsSymlinkThatEscapesCommittedAttachmentRoot() async throws {
        let directory = temporaryDirectory()
        let committedDirectory = directory.appendingPathComponent("ProofAttachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: committedDirectory,
            withIntermediateDirectories: true
        )
        let privateFile = directory.appendingPathComponent("PrivateState.json")
        let privateData = Data("private-state-must-not-upload".utf8)
        try privateData.write(to: privateFile)
        let symlink = committedDirectory.appendingPathComponent("proof.png")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: privateFile)

        let attachment = ProofAttachment(
            fileName: "proof.png",
            contentType: "image/png",
            byteCount: privateData.count,
            localRelativePath: "ProofAttachments/proof.png"
        )
        let uploadIntent = CareerGraphSyncUploadIntent(
            proofID: UUID().uuidString,
            attachment: CloudProofAttachmentDocument(
                attachment: attachment,
                ownerUserID: "firebase_uid_symlink_boundary",
                proofID: UUID()
            )
        )
        let store = OpenLARPAttachmentStore(directory: directory)

        do {
            _ = try await store.data(for: uploadIntent)
            XCTFail("Attachment upload must not follow a symlink outside its dedicated root.")
        } catch let error as CareerGraphProofAttachmentDataError {
            XCTAssertEqual(error, .unsafeLocalPath)
        }
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }
}
