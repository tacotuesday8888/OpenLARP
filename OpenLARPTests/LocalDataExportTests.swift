import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import OpenLARP

final class LocalDataExportTests: XCTestCase {
    func testExportIncludesSanitizedStateAndReferencedCommittedAndDraftBytes() throws {
        let committedBytes = Data([0x00, 0x01, 0xFF])
        let draftBytes = Data("active-draft".utf8)
        let committed = attachment(
            id: "11111111-1111-1111-1111-111111111111",
            fileName: "committed.png",
            originalFileName: "/Users/alice/Desktop/resume proof.png",
            byteCount: committedBytes.count,
            localRelativePath: "ProofAttachments/committed.png"
        )
        let draft = attachment(
            id: "22222222-2222-2222-2222-222222222222",
            fileName: "draft.png",
            originalFileName: #"C:\Users\alice\Desktop\draft.png"#,
            byteCount: draftBytes.count,
            localRelativePath: "ProofAttachmentDrafts/33333333-3333-3333-3333-333333333333/draft.png"
        )
        let state = state(committedAttachments: [committed], draftAttachments: [draft])
        let exportedAt = Date(timeIntervalSince1970: 1_735_689_600)
        let bytesByID = [committed.id: committedBytes, draft.id: draftBytes]
        let exporter = OpenLARPLocalDataExporter { attachment in
            guard let data = bytesByID[attachment.id] else { throw ReaderError.missing }
            return data
        }

        let archive = try exporter.makeArchive(from: state, exportedAt: exportedAt)

        XCTAssertEqual(archive.archiveVersion, OpenLARPLocalDataExportArchive.currentArchiveVersion)
        XCTAssertEqual(archive.exportedAt, exportedAt)
        XCTAssertEqual(archive.attachments.count, 2)
        XCTAssertEqual(
            archive.attachments.map(\.attachmentID),
            [committed.id, draft.id]
        )

        let committedExport = try XCTUnwrap(
            archive.attachments.first(where: { $0.attachmentID == committed.id })
        )
        XCTAssertEqual(committedExport.fileName, "committed.png")
        XCTAssertEqual(committedExport.originalFileName, "resume proof.png")
        XCTAssertEqual(committedExport.dataBase64, committedBytes.base64EncodedString())
        XCTAssertEqual(committedExport.relationships.count, 1)
        XCTAssertEqual(committedExport.relationships[0].ownerKind, .committedProof)

        let draftExport = try XCTUnwrap(
            archive.attachments.first(where: { $0.attachmentID == draft.id })
        )
        XCTAssertEqual(draftExport.originalFileName, "draft.png")
        XCTAssertEqual(draftExport.dataBase64, draftBytes.base64EncodedString())
        XCTAssertEqual(draftExport.relationships.count, 1)
        XCTAssertEqual(draftExport.relationships[0].ownerKind, .activeDraft)

        let document = try OpenLARPLocalDataExportDocument(archive: archive)
        XCTAssertEqual(OpenLARPLocalDataExportDocument.readableContentTypes, [.json])
        XCTAssertEqual(
            try OpenLARPLocalDataExportArchive.decode(from: document.archiveData),
            archive
        )

        let json = String(decoding: document.archiveData, as: UTF8.self)
        XCTAssertTrue(json.contains("Export Test Role"))
        XCTAssertFalse(json.contains("localRelativePath"))
        XCTAssertFalse(json.contains("ProofAttachments/committed.png"))
        XCTAssertFalse(json.contains("ProofAttachmentDrafts/"))
        XCTAssertFalse(json.contains("/Users/alice"))
        XCTAssertFalse(json.contains(#"C:\Users\alice"#))
    }

    func testExactDuplicateReferenceReadsAndEmbedsAttachmentOnlyOnce() throws {
        let bytes = Data("one-copy".utf8)
        let duplicate = attachment(
            id: "44444444-4444-4444-4444-444444444444",
            fileName: "same.jpg",
            byteCount: bytes.count,
            localRelativePath: "ProofAttachments/same.jpg"
        )
        var state = state(committedAttachments: [duplicate], draftAttachments: [])
        state.progress.recentProof.append(
            proofRecord(
                id: "55555555-5555-5555-5555-555555555555",
                attachments: [duplicate]
            )
        )
        let reads = ReadCounter()
        let exporter = OpenLARPLocalDataExporter { _ in
            reads.count += 1
            return bytes
        }

        let archive = try exporter.makeArchive(from: state, exportedAt: .distantPast)

        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(archive.attachments.count, 1)
        XCTAssertEqual(archive.attachments[0].relationships.count, 2)
        XCTAssertEqual(
            Set(archive.attachments[0].relationships.map(\.id)).count,
            2
        )
    }

    func testConflictingMetadataForSameAttachmentIDFailsBeforeReading() throws {
        let original = attachment(
            id: "66666666-6666-6666-6666-666666666666",
            fileName: "original.png",
            byteCount: 4,
            localRelativePath: "ProofAttachments/original.png"
        )
        var conflict = original
        conflict.localRelativePath = "ProofAttachments/different.png"
        let state = state(
            committedAttachments: [original],
            draftAttachments: [conflict]
        )
        let reads = ReadCounter()
        let exporter = OpenLARPLocalDataExporter { _ in
            reads.count += 1
            return Data(count: 4)
        }

        XCTAssertThrowsError(
            try exporter.makeArchive(from: state, exportedAt: .distantPast)
        ) { error in
            XCTAssertEqual(
                error as? OpenLARPLocalDataExportError,
                .conflictingAttachmentMetadata(attachmentID: original.id)
            )
        }
        XCTAssertEqual(reads.count, 0)
    }

    func testAttachmentReaderFailuresPropagateWithoutProducingPartialExport() {
        let referenced = attachment(
            id: "77777777-7777-7777-7777-777777777777",
            fileName: "missing.png",
            byteCount: 10,
            localRelativePath: "ProofAttachments/missing.png"
        )
        let state = state(committedAttachments: [referenced], draftAttachments: [])

        for expectedError in [ReaderError.missing, .unsafe] {
            let exporter = OpenLARPLocalDataExporter { _ in throw expectedError }

            XCTAssertThrowsError(
                try exporter.makeArchive(from: state, exportedAt: .distantPast)
            ) { error in
                XCTAssertEqual(error as? ReaderError, expectedError)
            }
        }
    }

    func testChangedAttachmentBytesFailEvenWhenReaderDoesNotValidateCount() {
        let referenced = attachment(
            id: "88888888-8888-8888-8888-888888888888",
            fileName: "changed.png",
            byteCount: 10,
            localRelativePath: "ProofAttachments/changed.png"
        )
        let state = state(committedAttachments: [referenced], draftAttachments: [])
        let exporter = OpenLARPLocalDataExporter { _ in Data(count: 9) }

        XCTAssertThrowsError(
            try exporter.makeArchive(from: state, exportedAt: .distantPast)
        ) { error in
            XCTAssertEqual(
                error as? OpenLARPLocalDataExportError,
                .attachmentByteCountMismatch(
                    attachmentID: referenced.id,
                    expected: 10,
                    actual: 9
                )
            )
        }
    }

    func testDecoderRejectsUnsupportedArchiveVersion() throws {
        let archive = try OpenLARPLocalDataExporter { _ in
            XCTFail("An empty state must not request attachment data.")
            return Data()
        }.makeArchive(from: .empty, exportedAt: .distantPast)
        let document = try OpenLARPLocalDataExportDocument(archive: archive)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: document.archiveData) as? [String: Any]
        )
        object["archiveVersion"] = OpenLARPLocalDataExportArchive.currentArchiveVersion + 1
        let futureData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try OpenLARPLocalDataExportArchive.decode(from: futureData)
        ) { error in
            XCTAssertEqual(
                error as? OpenLARPLocalDataExportError,
                .unsupportedArchiveVersion(
                    OpenLARPLocalDataExportArchive.currentArchiveVersion + 1
                )
            )
        }
    }

    private func state(
        committedAttachments: [ProofAttachment],
        draftAttachments: [ProofAttachment]
    ) -> OpenLARPState {
        var state = OpenLARPState.empty
        var goal = CareerGoal.empty
        goal.targetRole = "Export Test Role"
        state.goal = goal
        state.progress.recentProof = [
            proofRecord(
                id: "99999999-9999-9999-9999-999999999999",
                attachments: committedAttachments
            )
        ]
        if !draftAttachments.isEmpty {
            state.proofDraft = ProofSubmission(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                kind: .proof,
                text: "A draft that belongs in this export",
                attachments: draftAttachments,
                submittedAt: Date(timeIntervalSince1970: 200)
            )
        }
        return state
    }

    private func proofRecord(
        id: String,
        attachments: [ProofAttachment]
    ) -> ProofRecord {
        ProofRecord(
            id: UUID(uuidString: id)!,
            questID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            questTitle: "Export proof",
            kind: .proof,
            text: "A committed proof that belongs in this export",
            link: "",
            attachments: attachments,
            submittedAt: Date(timeIntervalSince1970: 100),
            quality: nil
        )
    }

    private func attachment(
        id: String,
        fileName: String,
        originalFileName: String = "",
        byteCount: Int,
        localRelativePath: String
    ) -> ProofAttachment {
        ProofAttachment(
            id: UUID(uuidString: id)!,
            fileName: fileName,
            originalFileName: originalFileName,
            contentType: "image/png",
            byteCount: byteCount,
            createdAt: Date(timeIntervalSince1970: 50),
            localRelativePath: localRelativePath
        )
    }
}

private enum ReaderError: Error, Equatable {
    case missing
    case unsafe
}

private final class ReadCounter {
    var count = 0
}
