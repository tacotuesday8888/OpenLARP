import CryptoKit
import Foundation

enum OpenLARPLocalOwner: Equatable, Hashable, Sendable {
    case guest
    case firebaseAccount(userID: String)

    var storageKey: String {
        switch self {
        case .guest:
            return "guest"
        case .firebaseAccount(let userID):
            let digest = SHA256.hash(data: Data(userID.utf8))
            let encodedDigest = digest.map { String(format: "%02x", $0) }.joined()
            return "account-\(encodedDigest)"
        }
    }

    var kind: OpenLARPLocalOwnerKind {
        switch self {
        case .guest: .guest
        case .firebaseAccount: .account
        }
    }

    var accountUserID: String? {
        guard case .firebaseAccount(let userID) = self else { return nil }
        return userID
    }
}

enum OpenLARPLocalOwnerKind: String, Codable, Equatable, Sendable {
    case guest
    case account
}

struct OpenLARPLocalOwnerMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let storageKey: String
    let kind: OpenLARPLocalOwnerKind
    let accountUserID: String?
    let guestID: UUID?

    init(owner: OpenLARPLocalOwner, guestID: UUID = UUID()) {
        schemaVersion = Self.currentSchemaVersion
        storageKey = owner.storageKey
        kind = owner.kind
        accountUserID = owner.accountUserID
        self.guestID = owner == .guest ? guestID : nil
    }

    var backendOwnerUserID: String {
        switch kind {
        case .guest:
            guestID.map { "local_\($0.uuidString)" } ?? "local_invalid_guest"
        case .account:
            accountUserID ?? ""
        }
    }

    var persistenceKey: String {
        switch kind {
        case .guest:
            guestID.map { "guest:\($0.uuidString)" } ?? "guest:invalid"
        case .account:
            "account:\(storageKey)"
        }
    }

    func matches(_ owner: OpenLARPLocalOwner) -> Bool {
        guard schemaVersion == Self.currentSchemaVersion,
              storageKey == owner.storageKey,
              kind == owner.kind else {
            return false
        }
        switch owner {
        case .guest:
            return guestID != nil && accountUserID == nil
        case .firebaseAccount(let userID):
            return accountUserID == userID && guestID == nil
        }
    }
}

enum OpenLARPLocalDataError: Error, Equatable {
    case invalidOwnerIdentifier
    case unsafeOwnerPath
    case managedSymlink
    case ownerMetadataMismatch
    case invalidUploadOwner
    case legacyMigrationFailed
    case eraseIncomplete
    case protectedDataUnavailable
}

enum OpenLARPLegacyMigrationResult: Equatable {
    case noLegacyData
    case migrated
    case alreadyCompleted
    case preservedExistingGuest
}

struct OpenLARPLocalOwnerContext: Sendable {
    let owner: OpenLARPLocalOwner
    let metadata: OpenLARPLocalOwnerMetadata
    let directory: URL
    let metadataURL: URL
    let persistence: OpenLARPPersistence
    let attachmentStore: OpenLARPAttachmentStore
}

struct OpenLARPLocalDataStore: CareerGraphProofAttachmentDataProviding, Sendable {
    let applicationSupportDirectory: URL
    let cachesDirectory: URL
    let legacyDocumentsDirectory: URL
    private let filePolicy = OpenLARPFilePolicy()

    var rootDirectory: URL {
        productDirectory
            .appendingPathComponent("v1", isDirectory: true)
    }

    var productDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("OpenLARP", isDirectory: true)
    }

    var ownersDirectory: URL {
        rootDirectory.appendingPathComponent("Owners", isDirectory: true)
    }

    var migrationMarkerURL: URL {
        rootDirectory.appendingPathComponent("legacy-migration.json")
    }

    private var legacyPersistence: OpenLARPPersistence {
        OpenLARPPersistence(directory: legacyDocumentsDirectory)
    }

    init(
        applicationSupportDirectory: URL,
        cachesDirectory: URL,
        legacyDocumentsDirectory: URL
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.cachesDirectory = cachesDirectory
        self.legacyDocumentsDirectory = legacyDocumentsDirectory
    }

    static var live: OpenLARPLocalDataStore {
        let fileManager = FileManager.default
        return OpenLARPLocalDataStore(
            applicationSupportDirectory: fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0],
            cachesDirectory: fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0],
            legacyDocumentsDirectory: fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        )
    }

    func context(for owner: OpenLARPLocalOwner) throws -> OpenLARPLocalOwnerContext {
        if case .firebaseAccount(let userID) = owner,
           userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OpenLARPLocalDataError.invalidOwnerIdentifier
        }
        try rejectSymlinkIfPresent(at: productDirectory)
        try rejectSymlinkIfPresent(at: rootDirectory)
        try rejectSymlinkIfPresent(at: ownersDirectory)
        try filePolicy.createDirectory(at: ownersDirectory, role: .ownerMetadata)

        let directory = ownersDirectory
            .appendingPathComponent(owner.storageKey, isDirectory: true)
            .standardizedFileURL
        guard directory.deletingLastPathComponent().standardizedFileURL == ownersDirectory.standardizedFileURL else {
            throw OpenLARPLocalDataError.unsafeOwnerPath
        }
        try rejectSymlinkIfPresent(at: directory)
        try filePolicy.createDirectory(at: directory, role: .ownerMetadata)

        let metadataURL = directory.appendingPathComponent("owner.json")
        let metadata: OpenLARPLocalOwnerMetadata
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            do {
                metadata = try JSONDecoder().decode(
                    OpenLARPLocalOwnerMetadata.self,
                    from: Data(contentsOf: metadataURL)
                )
            } catch {
                throw OpenLARPLocalDataError.ownerMetadataMismatch
            }
            guard metadata.matches(owner) else {
                throw OpenLARPLocalDataError.ownerMetadataMismatch
            }
        } else {
            metadata = OpenLARPLocalOwnerMetadata(owner: owner)
            try filePolicy.write(
                JSONEncoder().encode(metadata),
                to: metadataURL,
                role: .ownerMetadata
            )
        }
        return OpenLARPLocalOwnerContext(
            owner: owner,
            metadata: metadata,
            directory: directory,
            metadataURL: metadataURL,
            persistence: OpenLARPPersistence(
                directory: directory,
                ownerKey: metadata.persistenceKey
            ),
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )
    }

    func migrateLegacyDataIfNeeded() throws -> OpenLARPLegacyMigrationResult {
        try rejectSymlinkIfPresent(at: productDirectory)
        try rejectSymlinkIfPresent(at: rootDirectory)
        try rejectSymlinkIfPresent(at: ownersDirectory)
        try cleanupEraseTombstones()
        if FileManager.default.fileExists(atPath: migrationMarkerURL.path) {
            return .alreadyCompleted
        }
        let legacyStateURL = legacyPersistence.fileURL
        guard FileManager.default.fileExists(atPath: legacyStateURL.path) ||
                FileManager.default.fileExists(atPath: legacyPersistence.previousFileURL.path) else {
            return .noLegacyData
        }

        let guestURL = ownersDirectory.appendingPathComponent("guest", isDirectory: true)
        if FileManager.default.fileExists(atPath: guestURL.path) {
            let guest = try context(for: .guest)
            let importMarker = guest.directory.appendingPathComponent("legacy-import.json")
            if FileManager.default.fileExists(atPath: importMarker.path) {
                _ = try guest.persistence.load()
                try removeKnownLegacyData()
                try writeMigrationMarker(status: "migrated")
                try FileManager.default.removeItem(at: importMarker)
                return .migrated
            }
            if try guest.persistence.loadWithRecovery().source != .empty {
                return .preservedExistingGuest
            }
            try FileManager.default.removeItem(at: guestURL)
        }

        var state: OpenLARPState
        do {
            state = try legacyPersistence.load()
        } catch {
            throw OpenLARPLocalDataError.legacyMigrationFailed
        }
        let staging = rootDirectory.appendingPathComponent(".migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let metadata = OpenLARPLocalOwnerMetadata(owner: .guest)
        let stagingPersistence = OpenLARPPersistence(directory: staging, ownerKey: metadata.persistenceKey)
        let stagingAttachments = OpenLARPAttachmentStore(directory: staging)
        do {
            try filePolicy.createDirectory(at: staging, role: .migrationMetadata)
            try filePolicy.write(JSONEncoder().encode(metadata), to: staging.appendingPathComponent("owner.json"), role: .ownerMetadata)
            try filePolicy.write(
                Data("{\"schemaVersion\":1}".utf8),
                to: staging.appendingPathComponent("legacy-import.json"),
                role: .migrationMetadata
            )
            state = sanitizedLegacyState(state, guestOwnerUserID: metadata.backendOwnerUserID)
            let legacyAttachments = OpenLARPAttachmentStore(directory: legacyDocumentsDirectory)
            for attachment in referencedAttachments(in: state) {
                let bytes = try legacyAttachments.data(for: attachment)
                try stagingAttachments.importAttachment(attachment, data: bytes)
            }
            try stagingPersistence.save(state)
            _ = try stagingPersistence.load()
            try filePolicy.createDirectory(at: ownersDirectory, role: .ownerMetadata)
            try FileManager.default.moveItem(at: staging, to: guestURL)
            try removeKnownLegacyData()
            try writeMigrationMarker(status: "migrated")
            try FileManager.default.removeItem(at: guestURL.appendingPathComponent("legacy-import.json"))
            return .migrated
        } catch let error as OpenLARPLocalDataError {
            throw error
        } catch {
            throw OpenLARPLocalDataError.legacyMigrationFailed
        }
    }

    func eraseAllOnDeviceData() throws -> OpenLARPLocalOwnerContext {
        try rejectSymlinkIfPresent(at: productDirectory)
        try rejectSymlinkIfPresent(at: rootDirectory)
        try rejectSymlinkIfPresent(at: ownersDirectory)
        try cleanupEraseTombstones()
        try filePolicy.createDirectory(at: rootDirectory, role: .ownerMetadata)
        let tombstone = rootDirectory.appendingPathComponent(".erase-pending-\(UUID().uuidString)", isDirectory: true)
        if FileManager.default.fileExists(atPath: ownersDirectory.path) {
            try FileManager.default.moveItem(at: ownersDirectory, to: tombstone)
        }
        do {
            if FileManager.default.fileExists(atPath: migrationMarkerURL.path) {
                try FileManager.default.removeItem(at: migrationMarkerURL)
            }
            try removeKnownLegacyData()
            let cacheRoot = cachesDirectory.appendingPathComponent("OpenLARP", isDirectory: true)
            if FileManager.default.fileExists(atPath: cacheRoot.path) {
                try FileManager.default.removeItem(at: cacheRoot)
            }
            let context = try context(for: .guest)
            try context.persistence.save(.empty)
            if FileManager.default.fileExists(atPath: tombstone.path) {
                try FileManager.default.removeItem(at: tombstone)
            }
            return context
        } catch {
            throw OpenLARPLocalDataError.eraseIncomplete
        }
    }

    func cleanupEraseTombstones() throws {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
        for url in contents where url.lastPathComponent.hasPrefix(".erase-pending-") {
            try FileManager.default.removeItem(at: url)
        }
    }

    func data(for uploadIntent: CareerGraphSyncUploadIntent) async throws -> Data {
        let ownerIDs = [
            ownerID(in: uploadIntent.proofDocumentPath),
            ownerID(in: uploadIntent.attachmentDocumentPath),
            ownerID(in: uploadIntent.storagePath)
        ]
        guard let ownerID = ownerIDs[0], ownerIDs.allSatisfy({ $0 == ownerID }) else {
            throw OpenLARPLocalDataError.invalidUploadOwner
        }
        let context = try context(for: .firebaseAccount(userID: ownerID))
        return try await context.attachmentStore.data(for: uploadIntent)
    }

    private func ownerID(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 3,
              components[0] == "users",
              !components[1].isEmpty else { return nil }
        return String(components[1])
    }

    private func sanitizedLegacyState(
        _ legacy: OpenLARPState,
        guestOwnerUserID: String
    ) -> OpenLARPState {
        var state = legacy
        if var profile = state.userProfile {
            profile.accountID = nil
            profile.email = nil
            profile.privacy.allowsPrivateEvidenceCloudSync = false
            state.userProfile = profile
        }
        state.subscriptionState.customerInfo = nil
        state.subscriptionState.connectionStatus = .notConfigured
        state.subscriptionState.restoreState = .empty
        state.privateEvidenceBackupCleanupResult = nil
        state.accountDeletionResult = nil
        state.backendEvents = state.backendEvents.compactMap { event in
            guard event.ownerUserID.hasPrefix("local_") else { return nil }
            var copy = event
            copy.assignAuthenticatedOwnerIfLocal(guestOwnerUserID)
            copy.summary.allowsPrivateEvidenceCloudSync = nil
            return copy
        }
        return state
    }

    private func referencedAttachments(in state: OpenLARPState) -> [ProofAttachment] {
        var result: [ProofAttachment] = state.progress.recentProof.flatMap(\.attachments)
        result.append(contentsOf: state.proofDraft?.attachments ?? [])
        var seen = Set<UUID>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private func writeMigrationMarker(status: String) throws {
        let object: [String: Any] = ["schemaVersion": 1, "status": status]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try filePolicy.write(data, to: migrationMarkerURL, role: .migrationMetadata)
    }

    private func removeKnownLegacyData() throws {
        for url in [legacyPersistence.fileURL, legacyPersistence.previousFileURL,
                    legacyDocumentsDirectory.appendingPathComponent("ProofAttachments", isDirectory: true),
                    legacyDocumentsDirectory.appendingPathComponent("ProofAttachmentDrafts", isDirectory: true)]
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func rejectSymlinkIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw OpenLARPLocalDataError.managedSymlink
        }
    }
}
