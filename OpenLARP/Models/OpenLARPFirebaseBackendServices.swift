import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

enum FirebaseBackendServiceError: Error, LocalizedError, Equatable {
    case sdkUnavailable
    case configurationMissing
    case authenticationRequired
    case unsupportedDocumentType
    case payloadEncodingFailed
    case attachmentBytesUnavailable
    case attachmentByteCountMismatch
    case attachmentPathRejected
    case storagePathMismatch
    case invalidUploadReceipt

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            "Firebase SDK products are not linked in this build."
        case .configurationMissing:
            "Firebase is linked but not configured for this build."
        case .authenticationRequired:
            "Sign in before syncing OpenLARP backend events."
        case .unsupportedDocumentType:
            "The career graph document type is not supported by this Firebase adapter."
        case .payloadEncodingFailed:
            "The backend event payload could not be encoded for Firestore."
        case .attachmentBytesUnavailable:
            "The local proof attachment bytes are unavailable for upload."
        case .attachmentByteCountMismatch:
            "The local proof attachment byte count does not match the sync manifest."
        case .attachmentPathRejected:
            "The local proof attachment path is outside the private proof attachments directory."
        case .storagePathMismatch:
            "The proof attachment storage path does not match the signed-in Firebase user."
        case .invalidUploadReceipt:
            "The proof attachment upload receipt does not match the sync manifest."
        }
    }
}

struct FirebaseBackendSessionProvider: BackendSessionProviding {
    init() {}

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        #if canImport(FirebaseAuth) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else {
            var session = BackendUserSession.localOnly(for: state)
            session.authProvider = .firebaseAuth
            session.auth = BackendIntegrationRoute(
                kind: .firebaseAuth,
                status: .notConnected,
                detail: "FirebaseAuth is linked, but FirebaseApp is not configured."
            )
            session.firestore = BackendIntegrationRoute(
                kind: .firestore,
                status: .notConnected,
                detail: "Firestore waits for FirebaseApp configuration."
            )
            session.storage = BackendIntegrationRoute(
                kind: .firebaseStorage,
                status: .notConnected,
                detail: "Storage waits for FirebaseApp configuration."
            )
            session.functions = BackendIntegrationRoute(kind: .cloudFunctions, status: .notConnected)
            session.cloudRun = BackendIntegrationRoute(kind: .cloudRun, status: .notConnected)
            session.genkit = BackendIntegrationRoute(kind: .genkit, status: .configured)
            return session
        }

        guard let user = Auth.auth().currentUser else {
            var session = BackendUserSession.localOnly(for: state)
            session.authProvider = .firebaseAuth
            session.auth = BackendIntegrationRoute(kind: .firebaseAuth, status: .needsAuthentication)
            session.firestore = BackendIntegrationRoute(kind: .firestore, status: .configured)
            session.storage = BackendIntegrationRoute(kind: .firebaseStorage, status: .configured)
            session.functions = BackendIntegrationRoute(kind: .cloudFunctions, status: .configured)
            session.cloudRun = BackendIntegrationRoute(kind: .cloudRun, status: .configured)
            session.genkit = BackendIntegrationRoute(kind: .genkit, status: .configured)
            return session
        }

        let privacy = state.userProfile?.privacy ?? .localDefault
        return BackendUserSession.firebaseAuthenticated(
            ownerUserID: user.uid,
            accountID: user.uid,
            email: user.email,
            requiresUserApprovalForExternalActions: privacy.requireApprovalForExternalActions
        )
        #else
        var session = BackendUserSession.localOnly(for: state)
        session.auth = BackendIntegrationRoute(
            kind: .firebaseAuth,
            status: .notConnected,
            detail: "Link FirebaseAuth to enable account-backed sessions."
        )
        session.firestore = BackendIntegrationRoute(
            kind: .firestore,
            status: .notConnected,
            detail: "Link FirebaseFirestore to enable backend event writes."
        )
        session.storage = BackendIntegrationRoute(kind: .firebaseStorage, status: .notConnected)
        session.functions = BackendIntegrationRoute(kind: .cloudFunctions, status: .notConnected)
        session.cloudRun = BackendIntegrationRoute(kind: .cloudRun, status: .notConnected)
        session.genkit = BackendIntegrationRoute(kind: .genkit, status: .configured)
        return session
        #endif
    }
}

struct FirebaseBackendEventDocument: Codable, Equatable {
    var schemaVersion: Int
    var eventID: String
    var ownerUserID: String
    var kind: BackendEventKind
    var syncStatus: BackendEventSyncStatus
    var idempotencyKey: String
    var occurredAt: Date
    var retryCount: Int
    var lastAttemptAt: Date?
    var summary: BackendEventSummary
    var acceptedAt: Date

    init(event: BackendEventRecord, acceptedAt: Date) {
        schemaVersion = event.schemaVersion
        eventID = event.id.uuidString
        ownerUserID = event.ownerUserID
        kind = event.kind
        syncStatus = .acknowledged
        idempotencyKey = event.idempotencyKey
        occurredAt = event.occurredAt
        retryCount = event.retryCount
        lastAttemptAt = event.lastAttemptAt
        summary = event.summary
        self.acceptedAt = acceptedAt
    }
}

struct FirebaseFirestoreBackendEventSyncService: BackendEventSyncServicing {
    init() {}

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }

        #if canImport(FirebaseFirestore) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let db = Firestore.firestore()
        for event in request.events {
            let document = FirebaseBackendEventDocument(event: event, acceptedAt: request.requestedAt)
            let data = try FirebaseFirestorePayload.dictionary(from: document)
            try await db
                .collection("users")
                .document(request.session.ownerUserID)
                .collection("backendEvents")
                .document(event.id.uuidString)
                .setData(data, merge: true)
        }

        return BackendEventSyncResult(
            request: request,
            didContactNetwork: true,
            receipts: request.events.map {
                BackendEventSyncReceipt(
                    eventID: $0.id,
                    idempotencyKey: $0.idempotencyKey,
                    status: .acknowledged,
                    acceptedAt: request.requestedAt
                )
            }
        )
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseReadyBackendEventSyncService: BackendEventSyncServicing {
    private let firebaseService: FirebaseFirestoreBackendEventSyncService
    private let localFallbackService: LocalMockBackendEventSyncService

    init(
        firebaseService: FirebaseFirestoreBackendEventSyncService = FirebaseFirestoreBackendEventSyncService(),
        localFallbackService: LocalMockBackendEventSyncService = LocalMockBackendEventSyncService()
    ) {
        self.firebaseService = firebaseService
        self.localFallbackService = localFallbackService
    }

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        guard request.session.isAuthenticated else {
            return try await localFallbackService.syncEvents(request)
        }

        return try await firebaseService.syncEvents(request)
    }
}

protocol FirebaseCareerGraphDocumentWriting: Sendable {
    func writeDocuments(_ documents: [FirebaseCareerGraphDocumentWrite]) async throws
}

struct FirebaseCareerGraphDocumentWrite: Identifiable, @unchecked Sendable {
    var id: String { documentPath }

    var documentType: CareerGraphSyncDocumentType
    var documentPath: String
    var merge: Bool
    var data: [String: Any]

    init<T: Encodable>(
        documentType: CareerGraphSyncDocumentType,
        documentPath: String,
        document: T,
        merge: Bool = true
    ) throws {
        self.documentType = documentType
        self.documentPath = documentPath
        self.merge = merge
        data = try FirebaseFirestorePayload.dictionary(from: document)
    }
}

struct FirebaseFirestoreCareerGraphDocumentWriter: FirebaseCareerGraphDocumentWriting {
    init() {}

    func writeDocuments(_ documents: [FirebaseCareerGraphDocumentWrite]) async throws {
        #if canImport(FirebaseFirestore) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let db = Firestore.firestore()
        let batch = db.batch()
        for document in documents {
            batch.setData(
                document.data,
                forDocument: db.document(document.documentPath),
                merge: document.merge
            )
        }
        try await batch.commit()
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseStorageProofAttachmentUploader: CareerGraphProofAttachmentUploading {
    init() {}

    func upload(_ request: CareerGraphProofAttachmentUploadRequest) async throws -> CareerGraphSyncUploadReceipt {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }
        guard request.data.count == request.uploadIntent.byteCount else {
            throw FirebaseBackendServiceError.attachmentByteCountMismatch
        }
        guard request.uploadIntent.storagePath == expectedStoragePath(for: request) else {
            throw FirebaseBackendServiceError.storagePathMismatch
        }

        #if canImport(FirebaseStorage) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let metadata = StorageMetadata()
        metadata.contentType = request.uploadIntent.contentType
        metadata.customMetadata = [
            "ownerUserID": request.session.ownerUserID,
            "proofID": request.uploadIntent.proofID,
            "attachmentID": request.uploadIntent.attachmentID,
            "idempotencyKey": request.uploadIntent.idempotencyKey
        ]

        let uploadedMetadata = try await Storage
            .storage()
            .reference()
            .child(request.uploadIntent.storagePath)
            .putDataAsync(request.data, metadata: metadata)

        return CareerGraphSyncUploadReceipt(
            intent: request.uploadIntent,
            status: .uploaded,
            uploadedAt: uploadedMetadata.updated ?? request.requestedAt,
            storageBucket: uploadedMetadata.bucket,
            storageGeneration: uploadedMetadata.generation == 0 ? nil : uploadedMetadata.generation,
            metadataGeneration: uploadedMetadata.metageneration == 0 ? nil : uploadedMetadata.metageneration,
            md5Hash: uploadedMetadata.md5Hash
        )
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }

    private func expectedStoragePath(for request: CareerGraphProofAttachmentUploadRequest) -> String {
        "users/\(request.session.ownerUserID)/proofAttachments/\(request.uploadIntent.attachmentID)"
    }
}

struct FirebaseFirestoreCareerGraphSyncService: CareerGraphSyncServicing {
    private let planner: CareerGraphSyncPlanner
    private let writer: any FirebaseCareerGraphDocumentWriting
    private let attachmentDataProvider: any CareerGraphProofAttachmentDataProviding
    private let proofAttachmentUploader: any CareerGraphProofAttachmentUploading

    init(
        planner: CareerGraphSyncPlanner = CareerGraphSyncPlanner(),
        writer: any FirebaseCareerGraphDocumentWriting = FirebaseFirestoreCareerGraphDocumentWriter(),
        attachmentDataProvider: any CareerGraphProofAttachmentDataProviding = OpenLARPAttachmentStore.live,
        proofAttachmentUploader: any CareerGraphProofAttachmentUploading = FirebaseStorageProofAttachmentUploader()
    ) {
        self.planner = planner
        self.writer = writer
        self.attachmentDataProvider = attachmentDataProvider
        self.proofAttachmentUploader = proofAttachmentUploader
    }

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }

        let manifest = planner.plan(request)
        let uploadReceipts = try await uploadProofAttachments(
            manifest.storageUploads,
            request: request
        )
        let uploadedSnapshot = request.snapshot.applyingUploadReceipts(uploadReceipts)
        let writes = try makeDocumentWrites(from: uploadedSnapshot, manifest: manifest)
        try await writer.writeDocuments(writes)

        return CareerGraphSyncResult(
            status: .synced,
            request: request,
            didContactNetwork: true,
            requiresAuthenticationToSync: false,
            firestoreDocumentPaths: manifest.documentWrites.map(\.documentPath),
            uploadIntents: manifest.storageUploads,
            uploadReceipts: uploadReceipts,
            syncManifest: manifest
        )
    }

    private func uploadProofAttachments(
        _ uploadIntents: [CareerGraphSyncUploadIntent],
        request: CareerGraphSyncPreparationRequest
    ) async throws -> [CareerGraphSyncUploadReceipt] {
        var receipts: [CareerGraphSyncUploadReceipt] = []
        for uploadIntent in uploadIntents {
            let data: Data
            do {
                data = try await attachmentDataProvider.data(for: uploadIntent)
            } catch CareerGraphProofAttachmentDataError.missingLocalAttachment {
                throw FirebaseBackendServiceError.attachmentBytesUnavailable
            } catch CareerGraphProofAttachmentDataError.byteCountMismatch {
                throw FirebaseBackendServiceError.attachmentByteCountMismatch
            } catch CareerGraphProofAttachmentDataError.unsafeLocalPath {
                throw FirebaseBackendServiceError.attachmentPathRejected
            }

            let uploadRequest = CareerGraphProofAttachmentUploadRequest(
                requestedAt: request.requestedAt,
                session: request.session,
                uploadIntent: uploadIntent,
                data: data
            )
            let receipt = try await proofAttachmentUploader.upload(uploadRequest)
            guard isValidUploadedReceipt(receipt, for: uploadIntent) else {
                throw FirebaseBackendServiceError.invalidUploadReceipt
            }
            receipts.append(receipt)
        }
        return receipts
    }

    private func isValidUploadedReceipt(
        _ receipt: CareerGraphSyncUploadReceipt,
        for uploadIntent: CareerGraphSyncUploadIntent
    ) -> Bool {
        receipt.status == .uploaded &&
            receipt.proofID == uploadIntent.proofID &&
            receipt.attachmentID == uploadIntent.attachmentID &&
            receipt.storagePath == uploadIntent.storagePath &&
            receipt.contentType == uploadIntent.contentType &&
            receipt.byteCount == uploadIntent.byteCount &&
            receipt.idempotencyKey == uploadIntent.idempotencyKey
    }

    private func makeDocumentWrites(
        from snapshot: CloudCareerGraphSnapshot,
        manifest: CareerGraphSyncManifest
    ) throws -> [FirebaseCareerGraphDocumentWrite] {
        try manifest.documentWrites.map { write in
            try FirebaseCareerGraphDocumentWrite(
                documentType: write.documentType,
                documentPath: write.documentPath,
                document: document(for: write, in: snapshot),
                merge: shouldMergeDocument(write)
            )
        }
    }

    private func shouldMergeDocument(_ write: CareerGraphSyncDocumentWrite) -> Bool {
        // Replacing proof records removes legacy embedded attachment arrays that
        // are now stored in the dedicated proofAttachments collection.
        write.documentType != .proofRecord
    }

    private func document(
        for write: CareerGraphSyncDocumentWrite,
        in snapshot: CloudCareerGraphSnapshot
    ) throws -> any Encodable {
        switch write.documentType {
        case .profile:
            guard let document = snapshot.userProfile, document.documentPath == write.documentPath else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        case .goal:
            guard let document = snapshot.goal, document.documentPath == write.documentPath else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        case .targetRole:
            guard let document = snapshot.targetRoles.first(where: { $0.documentPath == write.documentPath }) else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        case .proofRecord:
            guard let document = snapshot.proofRecords.first(where: { $0.documentPath == write.documentPath }) else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        case .proofAttachment:
            guard let document = snapshot.proofRecords
                .flatMap(\.attachments)
                .first(where: { $0.documentPath == write.documentPath })
            else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        case .outcome:
            guard let document = snapshot.outcomes.first(where: { $0.documentPath == write.documentPath }) else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        case .readinessSnapshot:
            guard let document = snapshot.readinessSnapshots.first(where: { $0.documentPath == write.documentPath }) else {
                throw FirebaseBackendServiceError.unsupportedDocumentType
            }
            return document
        }
    }
}

struct FirebaseReadyCareerGraphSyncService: CareerGraphSyncServicing {
    private let firebaseService: FirebaseFirestoreCareerGraphSyncService
    private let localFallbackService: LocalMockCareerGraphSyncService

    init(
        firebaseService: FirebaseFirestoreCareerGraphSyncService = FirebaseFirestoreCareerGraphSyncService(),
        localFallbackService: LocalMockCareerGraphSyncService = LocalMockCareerGraphSyncService()
    ) {
        self.firebaseService = firebaseService
        self.localFallbackService = localFallbackService
    }

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        guard request.session.isAuthenticated else {
            return try await localFallbackService.prepareSync(request)
        }

        return try await firebaseService.prepareSync(request)
    }
}

private enum FirebaseFirestorePayload {
    static func dictionary<T: Encodable>(from value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseBackendServiceError.payloadEncodingFailed
        }
        return object
    }
}
