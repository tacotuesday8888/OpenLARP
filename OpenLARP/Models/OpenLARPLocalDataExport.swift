import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum OpenLARPLocalDataExportError: Error, Equatable {
    case conflictingAttachmentMetadata(attachmentID: UUID)
    case attachmentByteCountMismatch(attachmentID: UUID, expected: Int, actual: Int)
    case unsupportedArchiveVersion(Int)
    case invalidDocument
}

enum OpenLARPLocalDataExportOwnerKind: String, Codable, Equatable, Sendable {
    case committedProof
    case activeDraft
}

struct OpenLARPLocalDataExportRelationship: Codable, Equatable, Hashable, Sendable {
    let ownerKind: OpenLARPLocalDataExportOwnerKind
    let ownerID: UUID

    var id: String { "\(ownerKind.rawValue):\(ownerID.uuidString)" }
}

struct OpenLARPLocalDataExportAttachment: Codable, Equatable, Sendable {
    let attachmentID: UUID
    let fileName: String
    let originalFileName: String
    let contentType: String
    let byteCount: Int
    let createdAt: Date
    let dataBase64: String
    var relationships: [OpenLARPLocalDataExportRelationship]
}

struct OpenLARPLocalDataExportArchive: Codable, Equatable, Sendable {
    static let currentArchiveVersion = 1

    let archiveVersion: Int
    let exportedAt: Date
    let state: OpenLARPState
    let attachments: [OpenLARPLocalDataExportAttachment]

    static func decode(from data: Data) throws -> OpenLARPLocalDataExportArchive {
        let decoder = JSONDecoder.openLARPPersistence
        decoder.userInfo[.openLARPExportArchive] = true
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.archiveVersion == currentArchiveVersion else {
            throw OpenLARPLocalDataExportError.unsupportedArchiveVersion(archive.archiveVersion)
        }
        return archive
    }
}

struct OpenLARPLocalDataExporter {
    typealias AttachmentReader = (ProofAttachment) throws -> Data

    private let readAttachment: AttachmentReader

    init(readAttachment: @escaping AttachmentReader) {
        self.readAttachment = readAttachment
    }

    func makeArchive(
        from state: OpenLARPState,
        exportedAt: Date = Date()
    ) throws -> OpenLARPLocalDataExportArchive {
        var sanitizedState = state
        var orderedIDs: [UUID] = []
        var attachmentsByID: [UUID: ProofAttachment] = [:]
        var relationshipsByID: [UUID: [OpenLARPLocalDataExportRelationship]] = [:]

        sanitizedState.progress.recentProof = try state.progress.recentProof.map { proof in
            var sanitizedProof = proof
            sanitizedProof.attachments = try proof.attachments.map { attachment in
                try register(
                    attachment,
                    relationship: OpenLARPLocalDataExportRelationship(
                        ownerKind: .committedProof,
                        ownerID: proof.id
                    ),
                    orderedIDs: &orderedIDs,
                    attachmentsByID: &attachmentsByID,
                    relationshipsByID: &relationshipsByID
                )
                return sanitized(attachment)
            }
            return sanitizedProof
        }

        if let draft = state.proofDraft {
            var sanitizedDraft = draft
            sanitizedDraft.attachments = try draft.attachments.map { attachment in
                try register(
                    attachment,
                    relationship: OpenLARPLocalDataExportRelationship(
                        ownerKind: .activeDraft,
                        ownerID: draft.id
                    ),
                    orderedIDs: &orderedIDs,
                    attachmentsByID: &attachmentsByID,
                    relationshipsByID: &relationshipsByID
                )
                return sanitized(attachment)
            }
            sanitizedState.proofDraft = sanitizedDraft
        }

        let exportedAttachments = try orderedIDs.map { attachmentID in
            let attachment = attachmentsByID[attachmentID]!
            let data = try readAttachment(attachment)
            guard data.count == attachment.byteCount else {
                throw OpenLARPLocalDataExportError.attachmentByteCountMismatch(
                    attachmentID: attachment.id,
                    expected: attachment.byteCount,
                    actual: data.count
                )
            }
            return OpenLARPLocalDataExportAttachment(
                attachmentID: attachment.id,
                fileName: safeFileName(attachment.fileName),
                originalFileName: safeFileName(attachment.originalFileName),
                contentType: attachment.contentType,
                byteCount: attachment.byteCount,
                createdAt: attachment.createdAt,
                dataBase64: data.base64EncodedString(),
                relationships: relationshipsByID[attachmentID] ?? []
            )
        }

        return OpenLARPLocalDataExportArchive(
            archiveVersion: OpenLARPLocalDataExportArchive.currentArchiveVersion,
            exportedAt: exportedAt,
            state: sanitizedState,
            attachments: exportedAttachments
        )
    }

    private func register(
        _ attachment: ProofAttachment,
        relationship: OpenLARPLocalDataExportRelationship,
        orderedIDs: inout [UUID],
        attachmentsByID: inout [UUID: ProofAttachment],
        relationshipsByID: inout [UUID: [OpenLARPLocalDataExportRelationship]]
    ) throws {
        if let existing = attachmentsByID[attachment.id] {
            guard existing == attachment else {
                throw OpenLARPLocalDataExportError.conflictingAttachmentMetadata(
                    attachmentID: attachment.id
                )
            }
        } else {
            orderedIDs.append(attachment.id)
            attachmentsByID[attachment.id] = attachment
        }
        var relationships = relationshipsByID[attachment.id] ?? []
        if !relationships.contains(relationship) {
            relationships.append(relationship)
        }
        relationshipsByID[attachment.id] = relationships
    }

    private func sanitized(_ attachment: ProofAttachment) -> ProofAttachment {
        var copy = attachment
        copy.fileName = safeFileName(copy.fileName)
        copy.originalFileName = safeFileName(copy.originalFileName)
        copy.localRelativePath = ""
        return copy
    }

    private func safeFileName(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        return URL(fileURLWithPath: normalized).lastPathComponent
    }
}

struct OpenLARPLocalDataExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let archiveData: Data

    init(archive: OpenLARPLocalDataExportArchive) throws {
        archiveData = try JSONEncoder.openLARPPersistence.encode(archive)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw OpenLARPLocalDataExportError.invalidDocument
        }
        _ = try OpenLARPLocalDataExportArchive.decode(from: data)
        archiveData = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: archiveData)
    }
}
