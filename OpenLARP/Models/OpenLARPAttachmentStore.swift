import Foundation

struct OpenLARPAttachmentStore: CareerGraphProofAttachmentDataProviding, Sendable {
    let directory: URL

    private var attachmentsDirectory: URL {
        directory.appendingPathComponent("ProofAttachments", isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
    }

    static var live: OpenLARPAttachmentStore {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return OpenLARPAttachmentStore(directory: directory)
    }

    func saveImage(
        data: Data,
        contentType: String,
        originalFileName: String = "",
        now: Date = Date()
    ) throws -> ProofAttachment {
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)

        let fileExtension = preferredFileExtension(contentType: contentType, originalFileName: originalFileName)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let attachment = ProofAttachment(
            fileName: fileName,
            originalFileName: originalFileName,
            contentType: contentType,
            byteCount: data.count,
            createdAt: now
        )
        try data.write(to: url(for: attachment), options: [.atomic])
        return attachment
    }

    func data(for attachment: ProofAttachment) throws -> Data {
        try Data(contentsOf: url(for: attachment))
    }

    func data(for uploadIntent: CareerGraphSyncUploadIntent) async throws -> Data {
        let fileURL = directory
            .appendingPathComponent(uploadIntent.localRelativePath)
            .standardizedFileURL
        let safeDirectory = attachmentsDirectory.standardizedFileURL
        guard fileURL.path.hasPrefix(safeDirectory.path + "/") else {
            throw CareerGraphProofAttachmentDataError.unsafeLocalPath
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CareerGraphProofAttachmentDataError.missingLocalAttachment
        }

        let data = try Data(contentsOf: fileURL)
        guard data.count == uploadIntent.byteCount else {
            throw CareerGraphProofAttachmentDataError.byteCountMismatch
        }
        return data
    }

    func url(for attachment: ProofAttachment) -> URL {
        directory.appendingPathComponent(attachment.localRelativePath)
    }

    func delete(_ attachment: ProofAttachment) throws {
        let fileURL = url(for: attachment)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func preferredFileExtension(contentType: String, originalFileName: String) -> String {
        let existingExtension = URL(fileURLWithPath: originalFileName).pathExtension
        if !existingExtension.isEmpty {
            return existingExtension.lowercased()
        }

        switch contentType.lowercased() {
        case "image/png":
            return "png"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        default:
            return "jpg"
        }
    }
}
