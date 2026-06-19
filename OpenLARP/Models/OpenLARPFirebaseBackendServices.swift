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

#if canImport(FirebaseFunctions)
@preconcurrency
import FirebaseFunctions
#endif

#if canImport(FirebaseSharedSwift)
import FirebaseSharedSwift
#endif

enum FirebaseBackendServiceError: Error, LocalizedError, Equatable {
    case sdkUnavailable
    case configurationMissing
    case authenticationRequired
    case unsupportedDocumentType
    case payloadEncodingFailed
    case responseDecodingFailed
    case contractMismatch(String)
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
        case .responseDecodingFailed:
            "The backend response did not match the OpenLARP Firebase contract."
        case .contractMismatch(let detail):
            detail
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

struct FirebaseCallableBackendEventSyncService: BackendEventSyncServicing {
    private let configuration: OpenLARPFirebaseCallableBackendConfiguration

    init(configuration: OpenLARPFirebaseCallableBackendConfiguration = .production) {
        self.configuration = configuration
    }

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }

        #if canImport(FirebaseFunctions) && canImport(FirebaseCore) && canImport(FirebaseSharedSwift)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let functions = Functions.functions()
        if configuration.usesEmulator {
            functions.useEmulator(withHost: configuration.emulatorHost, port: configuration.emulatorPort)
        }

        let callable: Callable<
            BackendEventSyncRequest,
            FirebaseBackendEventSyncResponse
        > = functions.httpsCallable(
            configuration.backendEventSyncFunctionName,
            requestAs: BackendEventSyncRequest.self,
            responseAs: FirebaseBackendEventSyncResponse.self,
            encoder: FirebaseCallableAIWorkflowJSON.firebaseDataEncoder(),
            decoder: FirebaseCallableAIWorkflowJSON.firebaseDataDecoder()
        )
        let response = try await callable.call(request)
        return try response.validatedResult(for: request)
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseBackendEventSyncResponse: Codable, Equatable {
    var ok: Bool
    var schemaVersion: Int
    var userID: String
    var requestedAt: Date
    var completedAt: Date
    var didContactNetwork: Bool
    var receipts: [BackendEventSyncReceipt]
    var externalActionTaken: Bool

    func validatedResult(for request: BackendEventSyncRequest) throws -> BackendEventSyncResult {
        guard ok,
              schemaVersion == 1,
              userID == request.session.ownerUserID,
              requestedAt == request.requestedAt,
              didContactNetwork,
              externalActionTaken == false
        else {
            throw FirebaseBackendServiceError.contractMismatch("Backend event acknowledgement response did not match the signed-in user or sync contract.")
        }

        let expectedReceipts = Dictionary(uniqueKeysWithValues: request.events.map {
            ($0.id, $0.idempotencyKey)
        })
        guard receipts.count == expectedReceipts.count else {
            throw FirebaseBackendServiceError.contractMismatch("Backend event acknowledgement receipt count did not match the request.")
        }
        for receipt in receipts {
            guard receipt.schemaVersion == 1,
                  receipt.status == .acknowledged,
                  expectedReceipts[receipt.eventID] == receipt.idempotencyKey,
                  receipt.acceptedAt <= completedAt
            else {
                throw FirebaseBackendServiceError.contractMismatch("Backend event acknowledgement receipt did not match a requested event.")
            }
        }

        return BackendEventSyncResult(
            request: request,
            completedAt: completedAt,
            didContactNetwork: didContactNetwork,
            receipts: receipts
        )
    }
}

struct FirebaseReadyBackendEventSyncService: BackendEventSyncServicing {
    private let firebaseService: any BackendEventSyncServicing
    private let localFallbackService: LocalMockBackendEventSyncService

    init(
        firebaseService: any BackendEventSyncServicing = FirebaseCallableBackendEventSyncService(),
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

        let reference = Storage
            .storage()
            .reference()
            .child(request.uploadIntent.storagePath)
        let uploadedMetadata = try await uploadOrReuseExistingObject(request, reference: reference)

        guard let receipt = CareerGraphSyncUploadReceipt(
            existingObject: storageObjectMetadata(from: uploadedMetadata, reference: reference),
            intent: request.uploadIntent,
            session: request.session,
            uploadedAtFallback: request.requestedAt
        ) else {
            throw FirebaseBackendServiceError.invalidUploadReceipt
        }
        return receipt
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }

    private func expectedStoragePath(for request: CareerGraphProofAttachmentUploadRequest) -> String {
        "users/\(request.session.ownerUserID)/proofAttachments/\(request.uploadIntent.attachmentID)"
    }

    #if canImport(FirebaseStorage) && canImport(FirebaseCore)
    private func uploadOrReuseExistingObject(
        _ request: CareerGraphProofAttachmentUploadRequest,
        reference: StorageReference
    ) async throws -> StorageMetadata {
        do {
            return try await reference.putDataAsync(
                request.data,
                metadata: uploadMetadata(for: request)
            )
        } catch let uploadError {
            do {
                return try await reference.getMetadata()
            } catch {
                throw uploadError
            }
        }
    }

    private func uploadMetadata(for request: CareerGraphProofAttachmentUploadRequest) -> StorageMetadata {
        let metadata = StorageMetadata()
        metadata.contentType = request.uploadIntent.contentType
        metadata.customMetadata = CareerGraphStorageObjectMetadata.expectedCustomMetadata(
            ownerUserID: request.session.ownerUserID,
            intent: request.uploadIntent
        )
        return metadata
    }

    private func storageObjectMetadata(
        from metadata: StorageMetadata,
        reference: StorageReference
    ) -> CareerGraphStorageObjectMetadata {
        CareerGraphStorageObjectMetadata(
            storagePath: metadata.path ?? reference.fullPath,
            contentType: metadata.contentType,
            byteCount: Int(exactly: metadata.size) ?? -1,
            customMetadata: metadata.customMetadata ?? [:],
            updatedAt: metadata.updated,
            storageBucket: metadata.bucket.isEmpty ? nil : metadata.bucket,
            storageGeneration: metadata.generation == 0 ? nil : metadata.generation,
            metadataGeneration: metadata.metageneration == 0 ? nil : metadata.metageneration,
            md5Hash: metadata.md5Hash
        )
    }
    #endif
}

struct LocalProofAttachmentReceiptPromoter: CareerGraphProofAttachmentReceiptPromoting {
    var writesProofAttachmentDocuments: Bool { false }

    init() {}

    func promote(_ request: CareerGraphProofAttachmentPromotionRequest) async throws -> CareerGraphSyncUploadReceipt {
        request.uploadReceipt
    }
}

struct OpenLARPFirebaseCallableBackendConfiguration: Equatable {
    var backendEventSyncFunctionName: String
    var proofUploadPromotionFunctionName: String
    var privateEvidenceConsentFunctionName: String
    var privateEvidenceBackupCleanupFunctionName: String
    var accountDeletionFunctionName: String
    var usesEmulator: Bool
    var emulatorHost: String
    var emulatorPort: Int

    static let production = OpenLARPFirebaseCallableBackendConfiguration()
    static let localEmulator = OpenLARPFirebaseCallableBackendConfiguration(usesEmulator: true)

    init(
        backendEventSyncFunctionName: String = "acknowledgeBackendEvents",
        proofUploadPromotionFunctionName: String = "promoteProofUploadReceipt",
        privateEvidenceConsentFunctionName: String = "setPrivateEvidenceCloudSyncConsent",
        privateEvidenceBackupCleanupFunctionName: String = "cleanupRevokedPrivateEvidenceUploads",
        accountDeletionFunctionName: String = "deleteOpenLARPAccount",
        usesEmulator: Bool = false,
        emulatorHost: String = "localhost",
        emulatorPort: Int = 5001
    ) {
        self.backendEventSyncFunctionName = backendEventSyncFunctionName
        self.proofUploadPromotionFunctionName = proofUploadPromotionFunctionName
        self.privateEvidenceConsentFunctionName = privateEvidenceConsentFunctionName
        self.privateEvidenceBackupCleanupFunctionName = privateEvidenceBackupCleanupFunctionName
        self.accountDeletionFunctionName = accountDeletionFunctionName
        self.usesEmulator = usesEmulator
        self.emulatorHost = emulatorHost
        self.emulatorPort = emulatorPort
    }
}

private struct FirebasePrivateEvidenceCloudSyncConsentPayload: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var enabled: Bool
    var consentTextVersion: String

    init(request: PrivateEvidenceCloudSyncConsentRequest) {
        schemaVersion = request.schemaVersion
        enabled = request.enabled
        consentTextVersion = request.consentTextVersion
    }
}

private struct FirebasePrivateEvidenceCloudSyncConsentResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var schemaVersion: Int
    var userID: String
    var status: PrivateEvidenceCloudSyncConsentStatus
    var allowsPrivateEvidenceCloudSync: Bool
    var consentTextVersion: String
    var firestoreDocumentPath: String
    var updatedAt: Date
    var externalActionTaken: Bool

    func validatedResult(for request: PrivateEvidenceCloudSyncConsentRequest) throws -> PrivateEvidenceCloudSyncConsentResult {
        guard ok,
              schemaVersion == 1,
              userID == request.session.ownerUserID,
              status == (request.enabled ? .accepted : .revoked),
              allowsPrivateEvidenceCloudSync == request.enabled,
              consentTextVersion == request.consentTextVersion,
              firestoreDocumentPath == "users/\(request.session.ownerUserID)/consents/privateEvidenceCloudSync",
              externalActionTaken == false
        else {
            throw FirebaseBackendServiceError.contractMismatch("Private evidence consent response did not match the signed-in user or requested consent state.")
        }

        return PrivateEvidenceCloudSyncConsentResult(
            request: request,
            completedAt: updatedAt,
            didContactNetwork: true,
            status: status,
            firestoreDocumentPath: firestoreDocumentPath,
            externalActionTaken: externalActionTaken
        )
    }
}

struct FirebaseCallablePrivateEvidenceCloudSyncConsentService: PrivateEvidenceCloudSyncConsentServicing {
    private let configuration: OpenLARPFirebaseCallableBackendConfiguration

    init(configuration: OpenLARPFirebaseCallableBackendConfiguration = .production) {
        self.configuration = configuration
    }

    func setConsent(_ request: PrivateEvidenceCloudSyncConsentRequest) async throws -> PrivateEvidenceCloudSyncConsentResult {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }

        #if canImport(FirebaseFunctions) && canImport(FirebaseCore) && canImport(FirebaseSharedSwift)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let functions = Functions.functions()
        if configuration.usesEmulator {
            functions.useEmulator(withHost: configuration.emulatorHost, port: configuration.emulatorPort)
        }

        let callable: Callable<
            FirebasePrivateEvidenceCloudSyncConsentPayload,
            FirebasePrivateEvidenceCloudSyncConsentResponse
        > = functions.httpsCallable(
            configuration.privateEvidenceConsentFunctionName,
            requestAs: FirebasePrivateEvidenceCloudSyncConsentPayload.self,
            responseAs: FirebasePrivateEvidenceCloudSyncConsentResponse.self,
            encoder: FirebaseCallableAIWorkflowJSON.firebaseDataEncoder(),
            decoder: FirebaseCallableAIWorkflowJSON.firebaseDataDecoder()
        )
        let response = try await callable.call(FirebasePrivateEvidenceCloudSyncConsentPayload(request: request))
        return try response.validatedResult(for: request)
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

private struct FirebasePrivateEvidenceBackupCleanupPayload: Encodable, Equatable, Sendable {
    var schemaVersion: Int
    var mode: PrivateEvidenceBackupCleanupMode
    var attachmentIDs: [String]?
    var maxAttachments: Int
    var confirmDeletion: Bool

    init(request: PrivateEvidenceBackupCleanupRequest) {
        schemaVersion = request.schemaVersion
        mode = request.mode
        attachmentIDs = request.attachmentIDs
        maxAttachments = request.maxAttachments
        confirmDeletion = request.confirmDeletion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(attachmentIDs, forKey: .attachmentIDs)
        try container.encode(maxAttachments, forKey: .maxAttachments)
        try container.encode(confirmDeletion, forKey: .confirmDeletion)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case attachmentIDs
        case maxAttachments
        case confirmDeletion
    }
}

private struct FirebasePrivateEvidenceBackupCleanupResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var schemaVersion: Int
    var userID: String
    var mode: PrivateEvidenceBackupCleanupMode
    var evaluatedAt: Date
    var scannedCount: Int
    var eligibleCount: Int
    var deletedCount: Int
    var partialFailureCount: Int
    var candidates: [PrivateEvidenceBackupCleanupCandidate]
    var externalActionTaken: Bool

    func validatedResult(for request: PrivateEvidenceBackupCleanupRequest) throws -> PrivateEvidenceBackupCleanupResult {
        guard ok,
              schemaVersion == 1,
              userID == request.session.ownerUserID,
              mode == request.mode,
              scannedCount == candidates.count,
              scannedCount >= 0,
              eligibleCount >= 0,
              deletedCount >= 0,
              partialFailureCount >= 0,
              eligibleCount == responseEligibleCount,
              deletedCount == responseDeletedCount,
              partialFailureCount == responsePartialFailureCount,
              externalActionTaken == responseTookExternalAction,
              candidateIDsMatchDeletionRequest(request),
              candidates.allSatisfy({ isValidCandidate($0, for: request) })
        else {
            throw FirebaseBackendServiceError.contractMismatch("Private evidence backup cleanup response did not match the signed-in user or request.")
        }

        return PrivateEvidenceBackupCleanupResult(
            request: request,
            completedAt: evaluatedAt,
            didContactNetwork: true,
            scannedCount: scannedCount,
            eligibleCount: eligibleCount,
            deletedCount: deletedCount,
            partialFailureCount: partialFailureCount,
            candidates: candidates,
            externalActionTaken: externalActionTaken
        )
    }

    private func isValidCandidate(
        _ candidate: PrivateEvidenceBackupCleanupCandidate,
        for request: PrivateEvidenceBackupCleanupRequest
    ) -> Bool {
        guard !candidate.attachmentID.isEmpty,
              !candidate.attachmentID.contains("/"),
              candidate.storagePath == "users/\(request.session.ownerUserID)/proofAttachments/\(candidate.attachmentID)",
              !candidate.reason.isEmpty
        else {
            return false
        }

        if request.mode == .deleteSyncedEvidence {
            return request.attachmentIDs?.contains(candidate.attachmentID) == true
        }

        return true
    }

    private func candidateIDsMatchDeletionRequest(_ request: PrivateEvidenceBackupCleanupRequest) -> Bool {
        guard request.mode == .deleteSyncedEvidence else {
            return true
        }

        guard let attachmentIDs = request.attachmentIDs else {
            return false
        }

        let requestedAttachmentIDs = Set(attachmentIDs)
        let responseAttachmentIDs = Set(candidates.map(\.attachmentID))
        return requestedAttachmentIDs.count == attachmentIDs.count &&
            responseAttachmentIDs.count == candidates.count &&
            responseAttachmentIDs == requestedAttachmentIDs
    }

    private var responseTookExternalAction: Bool {
        candidates.contains { candidate in
            candidate.deleted ||
                candidate.status == .storageDeleteFailed
        }
    }

    private var responseEligibleCount: Int {
        candidates.filter { candidate in
            candidate.canDelete ||
                candidate.deleted ||
                candidate.status == .storageDeleteFailed ||
                candidate.status == .firestoreDeleteFailed
        }.count
    }

    private var responseDeletedCount: Int {
        candidates.filter(\.deleted).count
    }

    private var responsePartialFailureCount: Int {
        candidates.filter { candidate in
            candidate.status == .storageDeleteFailed || candidate.status == .firestoreDeleteFailed
        }.count
    }
}

struct FirebaseCallablePrivateEvidenceBackupCleanupService: PrivateEvidenceBackupCleanupServicing {
    private let configuration: OpenLARPFirebaseCallableBackendConfiguration

    init(configuration: OpenLARPFirebaseCallableBackendConfiguration = .production) {
        self.configuration = configuration
    }

    func cleanUpBackups(_ request: PrivateEvidenceBackupCleanupRequest) async throws -> PrivateEvidenceBackupCleanupResult {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }

        #if canImport(FirebaseFunctions) && canImport(FirebaseCore) && canImport(FirebaseSharedSwift)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let functions = Functions.functions()
        if configuration.usesEmulator {
            functions.useEmulator(withHost: configuration.emulatorHost, port: configuration.emulatorPort)
        }

        let callable: Callable<
            FirebasePrivateEvidenceBackupCleanupPayload,
            FirebasePrivateEvidenceBackupCleanupResponse
        > = functions.httpsCallable(
            configuration.privateEvidenceBackupCleanupFunctionName,
            requestAs: FirebasePrivateEvidenceBackupCleanupPayload.self,
            responseAs: FirebasePrivateEvidenceBackupCleanupResponse.self,
            encoder: FirebaseCallableAIWorkflowJSON.firebaseDataEncoder(),
            decoder: FirebaseCallableAIWorkflowJSON.firebaseDataDecoder()
        )
        let response = try await callable.call(FirebasePrivateEvidenceBackupCleanupPayload(request: request))
        return try response.validatedResult(for: request)
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

private struct FirebaseAccountDeletionPayload: Encodable, Equatable, Sendable {
    var schemaVersion: Int
    var confirmDeletion: Bool
    var confirmationText: String

    init(request: AccountDeletionRequest) {
        schemaVersion = request.schemaVersion
        confirmDeletion = request.confirmDeletion
        confirmationText = request.confirmationText
    }
}

struct FirebaseAccountDeletionResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var schemaVersion: Int
    var userID: String
    var status: AccountDeletionStatus
    var requestedAt: Date
    var completedAt: Date
    var firestoreUserTree: AccountDeletionScopeResult
    var storageUserPrefix: AccountDeletionScopeResult
    var quotaUsageTree: AccountDeletionScopeResult
    var firebaseAuthUser: AccountDeletionAuthResult
    var deletionRequestMarker: AccountDeletionMarkerResult
    var externalActionTaken: Bool

    func validatedResult(for request: AccountDeletionRequest) throws -> AccountDeletionResult {
        guard ok,
              schemaVersion == 1,
              userID == request.session.ownerUserID,
              requestedAt <= completedAt,
              allCountsAreNonNegative,
              statusMatchesScopeResults,
              externalActionTaken == responseTookExternalAction,
              !responseContainsUnknownStatuses
        else {
            throw FirebaseBackendServiceError.contractMismatch("Account deletion response did not match the signed-in user or deletion contract.")
        }

        return AccountDeletionResult(
            request: request,
            completedAt: completedAt,
            didContactNetwork: true,
            status: status,
            firestoreUserTree: firestoreUserTree,
            storageUserPrefix: storageUserPrefix,
            quotaUsageTree: quotaUsageTree,
            firebaseAuthUser: firebaseAuthUser,
            deletionRequestMarker: deletionRequestMarker,
            externalActionTaken: externalActionTaken
        )
    }

    private var allCountsAreNonNegative: Bool {
        [firestoreUserTree, storageUserPrefix, quotaUsageTree].allSatisfy { scope in
            scope.deletedCount >= 0 &&
                (scope.attemptedCount ?? 0) >= 0 &&
                (scope.failedCount ?? 0) >= 0
        }
    }

    private var statusMatchesScopeResults: Bool {
        let dataScopesCompleted = [
            firestoreUserTree.status,
            storageUserPrefix.status,
            quotaUsageTree.status
        ].allSatisfy { $0 == .completed }
        let authDeleted = firebaseAuthUser.status == .deleted || firebaseAuthUser.status == .alreadyMissing
        let markerFinalized = deletionRequestMarker.status == .completed

        switch status {
        case .deleted:
            return dataScopesCompleted && authDeleted && markerFinalized
        case .partial:
            return !(dataScopesCompleted && authDeleted && markerFinalized)
        case .unknown:
            return false
        }
    }

    private var responseContainsUnknownStatuses: Bool {
        status == .unknown ||
            [firestoreUserTree, storageUserPrefix, quotaUsageTree].contains { $0.status == .unknown } ||
            firebaseAuthUser.status == .unknown ||
            deletionRequestMarker.status == .unknown
    }

    private var responseTookExternalAction: Bool {
        [firestoreUserTree, storageUserPrefix, quotaUsageTree].contains { scope in
            scope.deletedCount > 0 || (scope.attemptedCount ?? 0) > 0
        } || firebaseAuthUser.status == .deleted
    }
}

struct FirebaseCallableAccountDeletionService: AccountDeletionServicing {
    private let configuration: OpenLARPFirebaseCallableBackendConfiguration

    init(configuration: OpenLARPFirebaseCallableBackendConfiguration = .production) {
        self.configuration = configuration
    }

    func deleteAccount(_ request: AccountDeletionRequest) async throws -> AccountDeletionResult {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }
        guard request.confirmDeletion,
              request.confirmationText == AccountDeletionRequest.confirmationText
        else {
            throw FirebaseBackendServiceError.contractMismatch("Account deletion requires the exact confirmation phrase before contacting the backend.")
        }

        #if canImport(FirebaseFunctions) && canImport(FirebaseCore) && canImport(FirebaseSharedSwift)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let functions = Functions.functions()
        if configuration.usesEmulator {
            functions.useEmulator(withHost: configuration.emulatorHost, port: configuration.emulatorPort)
        }

        let callable: Callable<
            FirebaseAccountDeletionPayload,
            FirebaseAccountDeletionResponse
        > = functions.httpsCallable(
            configuration.accountDeletionFunctionName,
            requestAs: FirebaseAccountDeletionPayload.self,
            responseAs: FirebaseAccountDeletionResponse.self,
            encoder: FirebaseCallableAIWorkflowJSON.firebaseDataEncoder(),
            decoder: FirebaseCallableAIWorkflowJSON.firebaseDataDecoder()
        )
        let response = try await callable.call(FirebaseAccountDeletionPayload(request: request))
        return try response.validatedResult(for: request)
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

struct FirebaseCallableProofAttachmentReceiptPromoter: CareerGraphProofAttachmentReceiptPromoting {
    var writesProofAttachmentDocuments: Bool { true }

    private let configuration: OpenLARPFirebaseCallableBackendConfiguration

    init(configuration: OpenLARPFirebaseCallableBackendConfiguration = .production) {
        self.configuration = configuration
    }

    func promote(_ request: CareerGraphProofAttachmentPromotionRequest) async throws -> CareerGraphSyncUploadReceipt {
        guard request.session.isAuthenticated else {
            throw FirebaseBackendServiceError.authenticationRequired
        }

        #if canImport(FirebaseFunctions) && canImport(FirebaseCore) && canImport(FirebaseSharedSwift)
        guard FirebaseApp.app() != nil else {
            throw FirebaseBackendServiceError.configurationMissing
        }

        let functions = Functions.functions()
        if configuration.usesEmulator {
            functions.useEmulator(withHost: configuration.emulatorHost, port: configuration.emulatorPort)
        }

        let payload = FirebaseProofUploadPromotionPayload(intent: request.uploadIntent)
        let callable: Callable<
            FirebaseProofUploadPromotionPayload,
            FirebaseProofUploadPromotionResponse
        > = functions.httpsCallable(
            configuration.proofUploadPromotionFunctionName,
            requestAs: FirebaseProofUploadPromotionPayload.self,
            responseAs: FirebaseProofUploadPromotionResponse.self,
            encoder: FirebaseCallableAIWorkflowJSON.firebaseDataEncoder(),
            decoder: FirebaseCallableAIWorkflowJSON.firebaseDataDecoder()
        )
        let response = try await callable.call(payload)
        guard response.ok,
              response.schemaVersion == 1,
              response.userID == request.session.ownerUserID,
              response.firestoreDocumentPath == request.uploadIntent.attachmentDocumentPath,
              response.externalActionTaken == false
        else {
            throw FirebaseBackendServiceError.contractMismatch("Proof upload promotion response did not match the signed-in user or upload intent.")
        }
        return response.uploadReceipt
        #else
        throw FirebaseBackendServiceError.sdkUnavailable
        #endif
    }
}

private struct FirebaseProofUploadPromotionPayload: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var proofID: String
    var attachmentID: String
    var fileName: String
    var contentType: String
    var byteCount: Int
    var storagePath: String
    var proofDocumentPath: String
    var attachmentDocumentPath: String
    var idempotencyKey: String

    init(intent: CareerGraphSyncUploadIntent) {
        schemaVersion = 1
        proofID = intent.proofID
        attachmentID = intent.attachmentID
        fileName = intent.fileName
        contentType = intent.contentType
        byteCount = intent.byteCount
        storagePath = intent.storagePath
        proofDocumentPath = intent.proofDocumentPath
        attachmentDocumentPath = intent.attachmentDocumentPath
        idempotencyKey = intent.idempotencyKey
    }
}

private struct FirebaseProofUploadPromotionResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var schemaVersion: Int
    var userID: String
    var promotedAt: Date
    var firestoreDocumentPath: String
    var uploadReceipt: CareerGraphSyncUploadReceipt
    var externalActionTaken: Bool
}

struct FirebaseFirestoreCareerGraphSyncService: CareerGraphSyncServicing {
    private let planner: CareerGraphSyncPlanner
    private let writer: any FirebaseCareerGraphDocumentWriting
    private let attachmentDataProvider: any CareerGraphProofAttachmentDataProviding
    private let proofAttachmentUploader: any CareerGraphProofAttachmentUploading
    private let proofAttachmentReceiptPromoter: any CareerGraphProofAttachmentReceiptPromoting

    init(
        planner: CareerGraphSyncPlanner = CareerGraphSyncPlanner(),
        writer: any FirebaseCareerGraphDocumentWriting = FirebaseFirestoreCareerGraphDocumentWriter(),
        attachmentDataProvider: any CareerGraphProofAttachmentDataProviding = OpenLARPAttachmentStore.live,
        proofAttachmentUploader: any CareerGraphProofAttachmentUploading = FirebaseStorageProofAttachmentUploader(),
        proofAttachmentReceiptPromoter: any CareerGraphProofAttachmentReceiptPromoting = LocalProofAttachmentReceiptPromoter()
    ) {
        self.planner = planner
        self.writer = writer
        self.attachmentDataProvider = attachmentDataProvider
        self.proofAttachmentUploader = proofAttachmentUploader
        self.proofAttachmentReceiptPromoter = proofAttachmentReceiptPromoter
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
        let writes = try makeDocumentWrites(
            from: uploadedSnapshot,
            manifest: manifest,
            skipProofAttachmentDocuments: proofAttachmentReceiptPromoter.writesProofAttachmentDocuments
        )
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
            let promotionRequest = CareerGraphProofAttachmentPromotionRequest(
                requestedAt: request.requestedAt,
                session: request.session,
                uploadIntent: uploadIntent,
                uploadReceipt: receipt
            )
            let promotedReceipt = try await proofAttachmentReceiptPromoter.promote(promotionRequest)
            guard isValidUploadedReceipt(promotedReceipt, for: uploadIntent) else {
                throw FirebaseBackendServiceError.invalidUploadReceipt
            }
            receipts.append(promotedReceipt)
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
        manifest: CareerGraphSyncManifest,
        skipProofAttachmentDocuments: Bool
    ) throws -> [FirebaseCareerGraphDocumentWrite] {
        let documentWrites = skipProofAttachmentDocuments
            ? manifest.documentWrites.filter { $0.documentType != .proofAttachment }
            : manifest.documentWrites

        return try documentWrites.map { write in
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
        firebaseService: FirebaseFirestoreCareerGraphSyncService = FirebaseFirestoreCareerGraphSyncService(
            proofAttachmentReceiptPromoter: FirebaseCallableProofAttachmentReceiptPromoter()
        ),
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

enum FirebaseFirestorePayload {
    private static let dateMarkerKey = "__openlarpFirestoreDate"

    static func dictionary<T: Encodable>(from value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode([dateMarkerKey: iso8601String(from: date)])
        }
        let data = try encoder.encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseBackendServiceError.payloadEncodingFailed
        }
        guard let converted = firestoreValue(from: object) as? [String: Any] else {
            throw FirebaseBackendServiceError.payloadEncodingFailed
        }
        return converted
    }

    private static func firestoreValue(from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            if dictionary.count == 1,
               let dateString = dictionary[dateMarkerKey] as? String,
               let date = date(from: dateString) {
                #if canImport(FirebaseFirestore)
                return Timestamp(date: date)
                #else
                return dateString
                #endif
            }

            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = firestoreValue(from: item.value)
            }
        }

        if let array = value as? [Any] {
            return array.map(firestoreValue(from:))
        }

        return value
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: value)
    }
}
