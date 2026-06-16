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
            accountID: state.userProfile?.accountID,
            email: state.userProfile?.email,
            auth: BackendIntegrationRoute(kind: .firebaseAuth, status: .notConnected),
            firestore: BackendIntegrationRoute(kind: .firestore, status: .notConnected),
            storage: BackendIntegrationRoute(kind: .firebaseStorage, status: .notConnected),
            functions: BackendIntegrationRoute(kind: .cloudFunctions, status: .notConnected),
            cloudRun: BackendIntegrationRoute(kind: .cloudRun, status: .notConnected),
            genkit: BackendIntegrationRoute(kind: .genkit, status: .localMock),
            requiresUserApprovalForExternalActions: privacy.requireApprovalForExternalActions
        )
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
        includePrivateEvidence: Bool = false,
        includeReadinessHistory: Bool = true,
        schemaVersion: Int = 1
    ) {
        let privacy = state.userProfile?.privacy ?? .localDefault
        let policy = CloudExportPolicy(
            ownerUserID: session.ownerUserID,
            includePrivateEvidence: includePrivateEvidence,
            includeReadinessHistory: includeReadinessHistory,
            allowsLongTermMemoryWrite: privacy.memoryMode == .cloudReady && session.isAuthenticated,
            requiresApprovalForExternalActions: session.requiresUserApprovalForExternalActions
        )

        self.schemaVersion = schemaVersion
        self.requestedAt = requestedAt
        self.session = session
        self.snapshot = LocalCareerGraphCloudMapper().makeSnapshot(
            from: state,
            policy: policy,
            generatedAt: requestedAt
        )
        self.includePrivateEvidence = includePrivateEvidence
        self.integrationRoutes = session.integrationRoutes
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
    }
}

typealias CareerGraphUploadIntent = CareerGraphSyncUploadIntent

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
    var integrationRoutes: [BackendIntegrationRoute]

    init(
        status: CareerGraphSyncStatus,
        request: CareerGraphSyncPreparationRequest,
        preparedAt: Date? = nil,
        didContactNetwork: Bool = false,
        requiresAuthenticationToSync: Bool? = nil,
        firestoreDocumentPaths: [String],
        uploadIntents: [CareerGraphSyncUploadIntent],
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
        integrationRoutes = request.integrationRoutes
    }
}

protocol CareerGraphSyncServicing {
    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult
}

struct LocalMockCareerGraphSyncService: CareerGraphSyncServicing {
    init() {}

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        CareerGraphSyncResult(
            status: .preparedLocally,
            request: request,
            didContactNetwork: false,
            firestoreDocumentPaths: firestoreDocumentPaths(in: request.snapshot),
            uploadIntents: uploadIntents(in: request.snapshot)
        )
    }

    private func firestoreDocumentPaths(in snapshot: CloudCareerGraphSnapshot) -> [String] {
        var paths: [String] = []

        if let userProfile = snapshot.userProfile {
            paths.append(userProfile.documentPath)
        }
        paths.append(contentsOf: snapshot.targetRoles.map(\.documentPath))
        for proof in snapshot.proofRecords {
            paths.append(proof.documentPath)
            paths.append(contentsOf: proof.attachments.map(\.documentPath))
        }
        paths.append(contentsOf: snapshot.outcomes.map(\.documentPath))
        paths.append(contentsOf: snapshot.readinessSnapshots.map(\.documentPath))

        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
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
