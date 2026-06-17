import Foundation

enum BackendAuthProvider: String, Codable, CaseIterable {
    case localMock
    case firebaseAuth
}

struct BackendIntegrationRoute: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case firebaseAuth
        case firestore
        case firebaseStorage
        case cloudFunctions
        case cloudRun
        case genkit

        var label: String {
            switch self {
            case .firebaseAuth: "Firebase Auth"
            case .firestore: "Firestore"
            case .firebaseStorage: "Firebase Storage"
            case .cloudFunctions: "Cloud Functions"
            case .cloudRun: "Cloud Run"
            case .genkit: "Genkit"
            }
        }
    }

    enum Status: String, Codable, CaseIterable {
        case notConnected
        case localMock
        case configured
        case connected
        case needsAuthentication
        case disabled
        case failed

        var label: String {
            switch self {
            case .notConnected: "Not connected"
            case .localMock: "Local mock"
            case .configured: "Configured"
            case .connected: "Connected"
            case .needsAuthentication: "Needs sign-in"
            case .disabled: "Disabled"
            case .failed: "Failed"
            }
        }
    }

    var kind: Kind
    var status: Status
    var displayName: String
    var detail: String?

    var id: String { kind.rawValue }

    init(
        kind: Kind,
        status: Status,
        displayName: String? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.status = status
        self.displayName = displayName ?? kind.label
        self.detail = detail
    }
}

typealias BackendIntegrationRouteKind = BackendIntegrationRoute.Kind
typealias BackendIntegrationRouteStatus = BackendIntegrationRoute.Status
typealias BackendIntegrationKind = BackendIntegrationRoute.Kind
typealias BackendIntegrationStatus = BackendIntegrationRoute.Status

struct BackendUserSession: Codable, Equatable {
    var ownerUserID: String
    var isAuthenticated: Bool
    var authProvider: BackendAuthProvider
    var accountID: String?
    var email: String?
    var auth: BackendIntegrationRoute
    var firestore: BackendIntegrationRoute
    var storage: BackendIntegrationRoute
    var functions: BackendIntegrationRoute
    var cloudRun: BackendIntegrationRoute
    var genkit: BackendIntegrationRoute
    var requiresUserApprovalForExternalActions: Bool

    var integrationRoutes: [BackendIntegrationRoute] {
        [
            auth,
            firestore,
            storage,
            functions,
            cloudRun,
            genkit
        ]
    }

    init(
        ownerUserID: String,
        isAuthenticated: Bool,
        authProvider: BackendAuthProvider,
        accountID: String? = nil,
        email: String? = nil,
        auth: BackendIntegrationRoute,
        firestore: BackendIntegrationRoute,
        storage: BackendIntegrationRoute,
        functions: BackendIntegrationRoute,
        cloudRun: BackendIntegrationRoute,
        genkit: BackendIntegrationRoute,
        requiresUserApprovalForExternalActions: Bool = true
    ) {
        self.ownerUserID = ownerUserID
        self.isAuthenticated = isAuthenticated
        self.authProvider = authProvider
        self.accountID = accountID
        self.email = email
        self.auth = auth
        self.firestore = firestore
        self.storage = storage
        self.functions = functions
        self.cloudRun = cloudRun
        self.genkit = genkit
        self.requiresUserApprovalForExternalActions = requiresUserApprovalForExternalActions
    }

    static func localOnly(for state: OpenLARPState) -> BackendUserSession {
        let localID = state.userProfile?.id.uuidString ?? "device"
        let privacy = state.userProfile?.privacy ?? .localDefault

        return BackendUserSession(
            ownerUserID: "local_\(localID)",
            isAuthenticated: false,
            authProvider: .localMock,
            accountID: nil,
            email: nil,
            auth: BackendIntegrationRoute(kind: .firebaseAuth, status: .notConnected),
            firestore: BackendIntegrationRoute(kind: .firestore, status: .notConnected),
            storage: BackendIntegrationRoute(kind: .firebaseStorage, status: .notConnected),
            functions: BackendIntegrationRoute(kind: .cloudFunctions, status: .notConnected),
            cloudRun: BackendIntegrationRoute(kind: .cloudRun, status: .notConnected),
            genkit: BackendIntegrationRoute(kind: .genkit, status: .localMock),
            requiresUserApprovalForExternalActions: privacy.requireApprovalForExternalActions
        )
    }

    func redactedForCareerGraphSync() -> BackendUserSession {
        var session = self
        session.accountID = nil
        session.email = nil
        return session
    }
}

struct CareerGraphSyncPreparationRequest: Codable, Equatable {
    var schemaVersion: Int
    var requestedAt: Date
    var session: BackendUserSession
    var snapshot: CloudCareerGraphSnapshot
    var includePrivateEvidence: Bool
    var integrationRoutes: [BackendIntegrationRoute]

    var firestoreRootPath: String { "users/\(session.ownerUserID)" }

    init(
        state: OpenLARPState,
        session: BackendUserSession,
        requestedAt: Date = Date(),
        includePrivateEvidence: Bool? = nil,
        includeReadinessHistory: Bool = true,
        schemaVersion: Int = 1
    ) {
        let privacy = state.userProfile?.privacy ?? .localDefault
        let resolvedIncludePrivateEvidence = includePrivateEvidence ?? privacy.shareWins
        let policy = CloudExportPolicy(
            ownerUserID: session.ownerUserID,
            includePrivateEvidence: resolvedIncludePrivateEvidence,
            includeReadinessHistory: includeReadinessHistory,
            allowsLongTermMemoryWrite: privacy.memoryMode == .cloudReady && session.isAuthenticated,
            requiresApprovalForExternalActions: session.requiresUserApprovalForExternalActions
        )

        self.schemaVersion = schemaVersion
        self.requestedAt = requestedAt
        let syncSession = session.redactedForCareerGraphSync()

        self.session = syncSession
        self.snapshot = LocalCareerGraphCloudMapper().makeSnapshot(
            from: state,
            policy: policy,
            generatedAt: requestedAt
        )
        self.includePrivateEvidence = resolvedIncludePrivateEvidence
        self.integrationRoutes = syncSession.integrationRoutes
    }
}

enum CareerGraphSyncStatus: String, Codable, CaseIterable {
    case preparedLocally
    case needsAuthentication
    case synced
    case failed

    var label: String {
        switch self {
        case .preparedLocally: "Prepared locally"
        case .needsAuthentication: "Needs sign-in"
        case .synced: "Synced"
        case .failed: "Failed"
        }
    }
}

struct CareerGraphSyncUploadIntent: Codable, Equatable, Identifiable {
    var id: String { attachmentID }

    var proofID: String
    var attachmentID: String
    var fileName: String
    var contentType: String
    var byteCount: Int
    var storagePath: String
    var proofDocumentPath: String
    var attachmentDocumentPath: String
    var idempotencyKey: String

    init(
        proofID: String,
        attachment: CloudProofAttachmentDocument
    ) {
        self.proofID = proofID
        attachmentID = attachment.metadata.localID
        fileName = attachment.fileName
        contentType = attachment.contentType
        byteCount = attachment.byteCount
        storagePath = attachment.storagePath
        proofDocumentPath = "users/\(attachment.metadata.ownerUserID)/proofRecords/\(proofID)"
        attachmentDocumentPath = attachment.documentPath
        idempotencyKey = "\(attachment.metadata.ownerUserID)-\(attachment.metadata.localID)"
    }
}

typealias CareerGraphUploadIntent = CareerGraphSyncUploadIntent

enum CareerGraphSyncDocumentType: String, Codable, CaseIterable {
    case profile
    case goal
    case targetRole
    case proofRecord
    case proofAttachment
    case outcome
    case readinessSnapshot
}

enum CareerGraphSyncOperation: String, Codable, CaseIterable {
    case upsert
}

struct CareerGraphSyncDocumentWrite: Codable, Equatable, Identifiable {
    var id: String { documentPath }

    var documentType: CareerGraphSyncDocumentType
    var operation: CareerGraphSyncOperation
    var collectionPath: String
    var documentPath: String

    init(
        documentType: CareerGraphSyncDocumentType,
        operation: CareerGraphSyncOperation = .upsert,
        collectionPath: String,
        documentPath: String
    ) {
        self.documentType = documentType
        self.operation = operation
        self.collectionPath = collectionPath
        self.documentPath = documentPath
    }
}

struct CareerGraphSyncManifest: Codable, Equatable {
    var schemaVersion: Int
    var ownerUserID: String
    var firestoreRootPath: String
    var generatedAt: Date
    var documentWrites: [CareerGraphSyncDocumentWrite]
    var storageUploads: [CareerGraphSyncUploadIntent]
    var requiredRoutes: [BackendIntegrationRoute]

    init(
        ownerUserID: String,
        firestoreRootPath: String,
        generatedAt: Date,
        documentWrites: [CareerGraphSyncDocumentWrite],
        storageUploads: [CareerGraphSyncUploadIntent],
        requiredRoutes: [BackendIntegrationRoute],
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.ownerUserID = ownerUserID
        self.firestoreRootPath = firestoreRootPath
        self.generatedAt = generatedAt
        self.documentWrites = documentWrites
        self.storageUploads = storageUploads
        self.requiredRoutes = requiredRoutes
    }
}

struct CareerGraphSyncResult: Codable, Equatable {
    var schemaVersion: Int
    var status: CareerGraphSyncStatus
    var requestedAt: Date
    var preparedAt: Date
    var didContactNetwork: Bool
    var requiresAuthenticationToSync: Bool
    var firestoreRootPath: String
    var firestoreDocumentPaths: [String]
    var uploadIntents: [CareerGraphSyncUploadIntent]
    var syncManifest: CareerGraphSyncManifest
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        status: CareerGraphSyncStatus,
        request: CareerGraphSyncPreparationRequest,
        preparedAt: Date? = nil,
        didContactNetwork: Bool = false,
        requiresAuthenticationToSync: Bool? = nil,
        firestoreDocumentPaths: [String],
        uploadIntents: [CareerGraphSyncUploadIntent],
        syncManifest: CareerGraphSyncManifest,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        requestedAt = request.requestedAt
        self.preparedAt = preparedAt ?? request.requestedAt
        self.didContactNetwork = didContactNetwork
        self.requiresAuthenticationToSync = requiresAuthenticationToSync ?? !request.session.isAuthenticated
        firestoreRootPath = request.firestoreRootPath
        self.firestoreDocumentPaths = firestoreDocumentPaths
        self.uploadIntents = uploadIntents
        self.syncManifest = syncManifest
        integrationRoutes = syncManifest.requiredRoutes
    }
}

struct CareerGraphSyncPreview: Codable, Equatable {
    var schemaVersion: Int
    var status: CareerGraphSyncStatus
    var requestedAt: Date
    var preparedAt: Date
    var documentCount: Int
    var proofUploadCount: Int
    var proofUploadByteCount: Int
    var includedPrivateEvidence: Bool
    var allowsLongTermMemoryWrite: Bool
    var didContactNetwork: Bool
    var requiresAuthenticationToSync: Bool
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        status: CareerGraphSyncStatus,
        requestedAt: Date,
        preparedAt: Date,
        documentCount: Int,
        proofUploadCount: Int,
        proofUploadByteCount: Int,
        includedPrivateEvidence: Bool,
        allowsLongTermMemoryWrite: Bool,
        didContactNetwork: Bool,
        requiresAuthenticationToSync: Bool,
        integrationRoutes: [BackendIntegrationRoute] = [],
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.requestedAt = requestedAt
        self.preparedAt = preparedAt
        self.documentCount = documentCount
        self.proofUploadCount = proofUploadCount
        self.proofUploadByteCount = proofUploadByteCount
        self.includedPrivateEvidence = includedPrivateEvidence
        self.allowsLongTermMemoryWrite = allowsLongTermMemoryWrite
        self.didContactNetwork = didContactNetwork
        self.requiresAuthenticationToSync = requiresAuthenticationToSync
        self.integrationRoutes = integrationRoutes
    }

    init(request: CareerGraphSyncPreparationRequest, result: CareerGraphSyncResult) {
        self.init(
            status: result.status,
            requestedAt: result.requestedAt,
            preparedAt: result.preparedAt,
            documentCount: result.firestoreDocumentPaths.count,
            proofUploadCount: result.uploadIntents.count,
            proofUploadByteCount: result.uploadIntents.reduce(0) { $0 + $1.byteCount },
            includedPrivateEvidence: request.includePrivateEvidence,
            allowsLongTermMemoryWrite: request.snapshot.policy.allowsLongTermMemoryWrite,
            didContactNetwork: result.didContactNetwork,
            requiresAuthenticationToSync: result.requiresAuthenticationToSync,
            integrationRoutes: result.syncManifest.requiredRoutes
        )
    }
}

@MainActor
protocol CareerGraphSyncServicing {
    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult
}

struct LocalMockCareerGraphSyncService: CareerGraphSyncServicing {
    init() {}

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        let uploadIntents = uploadIntents(in: request.snapshot)
        let manifest = syncManifest(for: request, uploadIntents: uploadIntents)

        return CareerGraphSyncResult(
            status: .preparedLocally,
            request: request,
            didContactNetwork: false,
            firestoreDocumentPaths: manifest.documentWrites.map(\.documentPath),
            uploadIntents: uploadIntents,
            syncManifest: manifest
        )
    }

    private func syncManifest(
        for request: CareerGraphSyncPreparationRequest,
        uploadIntents: [CareerGraphSyncUploadIntent]
    ) -> CareerGraphSyncManifest {
        CareerGraphSyncManifest(
            ownerUserID: request.session.ownerUserID,
            firestoreRootPath: request.firestoreRootPath,
            generatedAt: request.requestedAt,
            documentWrites: documentWrites(in: request.snapshot),
            storageUploads: uploadIntents,
            requiredRoutes: requiredRoutes(
                from: request.integrationRoutes,
                needsStorage: !uploadIntents.isEmpty
            )
        )
    }

    private func requiredRoutes(
        from routes: [BackendIntegrationRoute],
        needsStorage: Bool
    ) -> [BackendIntegrationRoute] {
        let requiredKinds: [BackendIntegrationRoute.Kind] = needsStorage
            ? [.firebaseAuth, .firestore, .firebaseStorage]
            : [.firebaseAuth, .firestore]
        return requiredKinds.compactMap { kind in
            routes.first { $0.kind == kind }
        }
    }

    private func documentWrites(in snapshot: CloudCareerGraphSnapshot) -> [CareerGraphSyncDocumentWrite] {
        var writes: [CareerGraphSyncDocumentWrite] = []

        if let userProfile = snapshot.userProfile {
            writes.append(write(.profile, collectionPath: userProfile.collectionPath, documentPath: userProfile.documentPath))
        }
        if let goal = snapshot.goal {
            writes.append(write(.goal, collectionPath: goal.collectionPath, documentPath: goal.documentPath))
        }
        writes.append(contentsOf: snapshot.targetRoles.map {
            write(.targetRole, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
        })
        for proof in snapshot.proofRecords {
            writes.append(write(.proofRecord, collectionPath: proof.collectionPath, documentPath: proof.documentPath))
            writes.append(contentsOf: proof.attachments.map {
                write(.proofAttachment, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
            })
        }
        writes.append(contentsOf: snapshot.outcomes.map {
            write(.outcome, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
        })
        writes.append(contentsOf: snapshot.readinessSnapshots.map {
            write(.readinessSnapshot, collectionPath: $0.collectionPath, documentPath: $0.documentPath)
        })

        var seen: Set<String> = []
        return writes.filter { seen.insert($0.documentPath).inserted }
    }

    private func write(
        _ documentType: CareerGraphSyncDocumentType,
        collectionPath: String,
        documentPath: String
    ) -> CareerGraphSyncDocumentWrite {
        CareerGraphSyncDocumentWrite(
            documentType: documentType,
            collectionPath: collectionPath,
            documentPath: documentPath
        )
    }

    private func uploadIntents(in snapshot: CloudCareerGraphSnapshot) -> [CareerGraphSyncUploadIntent] {
        snapshot.proofRecords.flatMap { proof in
            proof.attachments.map { attachment in
                CareerGraphSyncUploadIntent(
                    proofID: proof.metadata.localID,
                    attachment: attachment
                )
            }
        }
    }
}
