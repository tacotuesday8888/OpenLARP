import Foundation

enum OpenLARPAttachmentStoreError: Error, Equatable, LocalizedError {
    case unsafeLocalPath
    case notStagedAttachment
    case missingAttachment
    case byteCountMismatch
    case destinationAlreadyExists
    case attachmentLimitExceeded

    var errorDescription: String? {
        switch self {
        case .unsafeLocalPath:
            "The local proof image path was not safe."
        case .notStagedAttachment:
            "A proof image did not belong to this draft."
        case .missingAttachment:
            "A local proof image is missing."
        case .byteCountMismatch:
            "A local proof image changed after it was saved."
        case .destinationAlreadyExists:
            "A committed proof image already exists at that location."
        case .attachmentLimitExceeded:
            "A proof draft can include up to four images."
        }
    }
}

struct OpenLARPAttachmentPromotion: Equatable {
    let stagedAttachments: [ProofAttachment]
    let committedAttachments: [ProofAttachment]
}

struct OpenLARPAttachmentStore: CareerGraphProofAttachmentDataProviding, Sendable {
    let directory: URL

    private var attachmentsDirectory: URL {
        directory.appendingPathComponent("ProofAttachments", isDirectory: true)
    }

    private var draftAttachmentsDirectory: URL {
        directory.appendingPathComponent("ProofAttachmentDrafts", isDirectory: true)
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
        let fileExtension = preferredFileExtension(contentType: contentType)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let attachment = ProofAttachment(
            fileName: fileName,
            originalFileName: safeOriginalFileName(originalFileName),
            contentType: contentType,
            byteCount: data.count,
            createdAt: now
        )
        let fileURL = try validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.committed]
        )
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
        return attachment
    }

    func stageImage(
        _ image: ProcessedProofImage,
        draftID: UUID,
        originalFileName: String = "",
        now: Date = Date()
    ) throws -> ProofAttachment {
        let fileExtension = preferredFileExtension(contentType: image.contentType)
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let relativePath = "ProofAttachmentDrafts/\(draftID.uuidString)/\(fileName)"
        let attachment = ProofAttachment(
            fileName: fileName,
            originalFileName: safeOriginalFileName(originalFileName),
            contentType: image.contentType,
            byteCount: image.byteCount,
            createdAt: now,
            localRelativePath: relativePath
        )
        let fileURL = try validatedURL(
            relativePath: relativePath,
            allowedRoots: [.draft]
        )
        let draftDirectory = draftAttachmentsDirectory
            .appendingPathComponent(draftID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
        try image.data.write(to: fileURL, options: [.atomic])
        return attachment
    }

    func data(for attachment: ProofAttachment) throws -> Data {
        let fileURL = try validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.committed, .draft]
        )
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OpenLARPAttachmentStoreError.missingAttachment
        }
        let data = try Data(contentsOf: fileURL)
        guard data.count == attachment.byteCount else {
            throw OpenLARPAttachmentStoreError.byteCountMismatch
        }
        return data
    }

    func data(for uploadIntent: CareerGraphSyncUploadIntent) async throws -> Data {
        let fileURL: URL
        do {
            fileURL = try validatedURL(
                relativePath: uploadIntent.localRelativePath,
                allowedRoots: [.committed]
            )
        } catch {
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
        (try? validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.committed, .draft]
        )) ?? directory.appendingPathComponent("InvalidProofAttachment")
    }

    func delete(_ attachment: ProofAttachment) throws {
        let fileURL = try validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.committed, .draft]
        )
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
        try removeEmptyDraftDirectory(containing: fileURL)
    }

    func deleteDraft(_ draftID: UUID) throws {
        _ = try validatedURL(
            relativePath: "ProofAttachmentDrafts/\(draftID.uuidString)/.openlarp-validation",
            allowedRoots: [.draft]
        )
        let draftDirectory = draftAttachmentsDirectory
            .appendingPathComponent(draftID.uuidString, isDirectory: true)
            .standardizedFileURL
        guard isDescendant(draftDirectory, of: draftAttachmentsDirectory) else {
            throw OpenLARPAttachmentStoreError.unsafeLocalPath
        }
        guard FileManager.default.fileExists(atPath: draftDirectory.path) else { return }
        try FileManager.default.removeItem(at: draftDirectory)
        try removeDirectoryIfEmpty(draftAttachmentsDirectory)
    }

    func preparePromotion(
        _ stagedAttachments: [ProofAttachment],
        draftID: UUID
    ) throws -> OpenLARPAttachmentPromotion {
        guard stagedAttachments.count <= ProofAttachmentPolicy.maximumCount else {
            throw OpenLARPAttachmentStoreError.attachmentLimitExceeded
        }
        guard !stagedAttachments.isEmpty else {
            return OpenLARPAttachmentPromotion(
                stagedAttachments: [],
                committedAttachments: []
            )
        }

        var committedAttachments: [ProofAttachment] = []

        do {
            for staged in stagedAttachments {
                guard isDraftAttachment(staged, draftID: draftID) else {
                    throw OpenLARPAttachmentStoreError.notStagedAttachment
                }
                let sourceURL = try validatedURL(
                    relativePath: staged.localRelativePath,
                    allowedRoots: [.draft]
                )
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    throw OpenLARPAttachmentStoreError.missingAttachment
                }
                let sourceData = try Data(contentsOf: sourceURL)
                guard sourceData.count == staged.byteCount else {
                    throw OpenLARPAttachmentStoreError.byteCountMismatch
                }

                var committed = staged
                committed.localRelativePath = "ProofAttachments/\(staged.fileName)"
                let destinationURL = try validatedURL(
                    relativePath: committed.localRelativePath,
                    allowedRoots: [.committed]
                )
                guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
                    throw OpenLARPAttachmentStoreError.destinationAlreadyExists
                }
                try FileManager.default.createDirectory(
                    at: attachmentsDirectory,
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                committedAttachments.append(committed)
            }
        } catch {
            let partialPromotion = OpenLARPAttachmentPromotion(
                stagedAttachments: Array(stagedAttachments.prefix(committedAttachments.count)),
                committedAttachments: committedAttachments
            )
            try? rollbackPromotion(partialPromotion)
            throw error
        }

        return OpenLARPAttachmentPromotion(
            stagedAttachments: stagedAttachments,
            committedAttachments: committedAttachments
        )
    }

    func rollbackPromotion(_ promotion: OpenLARPAttachmentPromotion) throws {
        guard !promotion.committedAttachments.isEmpty else { return }
        for attachment in promotion.committedAttachments {
            let fileURL = try validatedURL(
                relativePath: attachment.localRelativePath,
                allowedRoots: [.committed]
            )
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            try FileManager.default.removeItem(at: fileURL)
        }
        try removeDirectoryIfEmpty(attachmentsDirectory)
    }

    func finalizePromotion(_ promotion: OpenLARPAttachmentPromotion) throws {
        for attachment in promotion.stagedAttachments {
            let fileURL = try validatedURL(
                relativePath: attachment.localRelativePath,
                allowedRoots: [.draft]
            )
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            try FileManager.default.removeItem(at: fileURL)
            try removeEmptyDraftDirectory(containing: fileURL)
        }
    }

    func isDraftAttachment(_ attachment: ProofAttachment, draftID: UUID) -> Bool {
        guard let candidate = try? validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.draft]
        ) else {
            return false
        }
        let expectedDirectory = draftAttachmentsDirectory
            .appendingPathComponent(draftID.uuidString, isDirectory: true)
            .standardizedFileURL
        return candidate.deletingLastPathComponent().standardizedFileURL == expectedDirectory
    }

    func isCommittedAttachment(_ attachment: ProofAttachment) -> Bool {
        guard let candidate = try? validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.committed]
        ) else {
            return false
        }
        return candidate.deletingLastPathComponent().standardizedFileURL == attachmentsDirectory.standardizedFileURL
    }

    func committedCanonicalPath(for attachment: ProofAttachment) -> String? {
        guard isCommittedAttachment(attachment) else { return nil }
        return try? validatedURL(
            relativePath: attachment.localRelativePath,
            allowedRoots: [.committed]
        ).standardizedFileURL.path
    }

    func reconcile(referencedAttachments: [ProofAttachment]) throws {
        let referencedPaths = Set(
            referencedAttachments.compactMap { attachment in
                try? validatedURL(
                    relativePath: attachment.localRelativePath,
                    allowedRoots: [.committed, .draft]
                ).standardizedFileURL.path
            }
        )
        let fileManager = FileManager.default

        for root in [attachmentsDirectory, draftAttachmentsDirectory] {
            let validationRelativePath = root == attachmentsDirectory
                ? "ProofAttachments/.openlarp-validation"
                : "ProofAttachmentDrafts/.openlarp-validation"
            let validationRoot: AttachmentRoot = root == attachmentsDirectory ? .committed : .draft
            _ = try validatedURL(
                relativePath: validationRelativePath,
                allowedRoots: [validationRoot]
            )
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) else {
                continue
            }

            var filesToDelete: [URL] = []
            var directories: [URL] = []
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    filesToDelete.append(fileURL)
                    continue
                }
                if values.isDirectory == true {
                    directories.append(fileURL)
                } else if !referencedPaths.contains(fileURL.standardizedFileURL.path) {
                    filesToDelete.append(fileURL)
                }
            }

            for fileURL in filesToDelete {
                try fileManager.removeItem(at: fileURL)
            }
            for directoryURL in directories.sorted(by: { $0.path.count > $1.path.count }) {
                try removeDirectoryIfEmpty(directoryURL)
            }
            try removeDirectoryIfEmpty(root)
        }
    }

    private enum AttachmentRoot: Hashable {
        case committed
        case draft
    }

    private func validatedURL(
        relativePath: String,
        allowedRoots: Set<AttachmentRoot>
    ) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw OpenLARPAttachmentStoreError.unsafeLocalPath
        }
        let candidate = directory
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        let isLexicallyAllowed = allowedRoots.contains { root in
            switch root {
            case .committed:
                isDescendant(candidate, of: attachmentsDirectory)
            case .draft:
                isDescendant(candidate, of: draftAttachmentsDirectory)
            }
        }
        guard isLexicallyAllowed else {
            throw OpenLARPAttachmentStoreError.unsafeLocalPath
        }
        try validateNoManagedSymlink(relativePath: relativePath)

        let resolvedBase = directory.resolvingSymlinksInPath().standardizedFileURL
        let expectedResolvedCandidate = resolvedBase
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let actualResolvedCandidate = candidate
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard actualResolvedCandidate == expectedResolvedCandidate else {
            throw OpenLARPAttachmentStoreError.unsafeLocalPath
        }

        let isCanonicallyAllowed = allowedRoots.contains { root in
            let resolvedRoot: URL
            switch root {
            case .committed:
                resolvedRoot = resolvedBase.appendingPathComponent("ProofAttachments", isDirectory: true)
            case .draft:
                resolvedRoot = resolvedBase.appendingPathComponent("ProofAttachmentDrafts", isDirectory: true)
            }
            return isDescendant(actualResolvedCandidate, of: resolvedRoot)
        }
        guard isCanonicallyAllowed else {
            throw OpenLARPAttachmentStoreError.unsafeLocalPath
        }
        return candidate
    }

    private func validateNoManagedSymlink(relativePath: String) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw OpenLARPAttachmentStoreError.unsafeLocalPath
        }

        var candidate = directory.standardizedFileURL
        for component in components {
            candidate.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
                throw OpenLARPAttachmentStoreError.unsafeLocalPath
            }
        }
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath.hasPrefix(rootPath + "/")
    }

    private func removeEmptyDraftDirectory(containing fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent().standardizedFileURL
        guard isDescendant(parent, of: draftAttachmentsDirectory) else { return }
        try removeDirectoryIfEmpty(parent)
        try removeDirectoryIfEmpty(draftAttachmentsDirectory)
    }

    private func removeDirectoryIfEmpty(_ directoryURL: URL) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        guard contents.isEmpty else { return }
        try FileManager.default.removeItem(at: directoryURL)
    }

    private func safeOriginalFileName(_ originalFileName: String) -> String {
        guard !originalFileName.isEmpty else { return "" }
        return URL(fileURLWithPath: originalFileName).lastPathComponent
    }

    private func preferredFileExtension(contentType: String) -> String {
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
