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

enum FirebaseBackendServiceError: Error, LocalizedError, Equatable {
    case sdkUnavailable
    case configurationMissing
    case authenticationRequired
    case payloadEncodingFailed

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable:
            "Firebase SDK products are not linked in this build."
        case .configurationMissing:
            "Firebase is linked but not configured for this build."
        case .authenticationRequired:
            "Sign in before syncing OpenLARP backend events."
        case .payloadEncodingFailed:
            "The backend event payload could not be encoded for Firestore."
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
