import XCTest
@testable import OpenLARP

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
final class BackendSessionReadinessTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .newGrad,
        targetRole: "AI product engineer",
        timeline: "30 days",
        background: "Recent graduate with one AI prototype.",
        existingProof: "Prototype demo and project notes.",
        confidence: 3,
        biggestBlocker: "Needs stronger product proof."
    )

    func testStoreUsesInjectedAuthenticatedBackendSessionForEventsPreviewsAndSyncRequests() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let syncService = CapturingBackendEventSyncService()
        let session = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_123",
            accountID: "account-should-not-sync",
            email: "private@example.com"
        )
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            careerGraphSyncService: LocalMockCareerGraphSyncService(),
            backendEventSyncService: syncService,
            backendSessionProvider: StaticBackendSessionProvider(session: session),
            now: { Date(timeIntervalSince1970: 20_000) }
        )

        await store.confirmGoal(goal)

        XCTAssertEqual(store.state.backendEvents.first?.ownerUserID, "firebase_uid_123")

        await store.prepareCareerGraphSyncPreview()

        let preview = try XCTUnwrap(store.careerGraphSyncPreview)
        XCTAssertFalse(preview.requiresAuthenticationToSync)
        XCTAssertEqual(preview.integrationRoutes.first { $0.kind == .firebaseAuth }?.status, .connected)
        XCTAssertEqual(preview.integrationRoutes.first { $0.kind == .firestore }?.status, .configured)

        await store.syncBackendEvents()

        let request = try XCTUnwrap(syncService.requests.first)
        XCTAssertEqual(request.session.ownerUserID, "firebase_uid_123")
        XCTAssertTrue(request.session.isAuthenticated)
        XCTAssertNil(request.session.accountID)
        XCTAssertNil(request.session.email)
        XCTAssertTrue(request.events.allSatisfy { $0.ownerUserID == "firebase_uid_123" })
        XCTAssertFalse(String(describing: request).contains("private@example.com"))
        XCTAssertFalse(String(describing: request).contains("account-should-not-sync"))

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    func testDefaultBackendSessionProviderStaysLocalOnlyAndUnauthenticated() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory)
        )

        await store.confirmGoal(goal)
        await store.prepareCareerGraphSyncPreview()

        XCTAssertEqual(store.state.backendEvents.first?.ownerUserID.hasPrefix("local_"), true)
        XCTAssertEqual(store.careerGraphSyncPreview?.requiresAuthenticationToSync, true)
        XCTAssertEqual(store.careerGraphSyncPreview?.didContactNetwork, false)
    }

    func testLocalBackendEventsAreReownedWhenUserAuthenticatesBeforeSync() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let syncService = CapturingBackendEventSyncService()
        let sessionProvider = SwitchingBackendSessionProvider()
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            backendSessionProvider: sessionProvider,
            now: { Date(timeIntervalSince1970: 20_500) }
        )

        await store.confirmGoal(goal)
        let localEvent = try XCTUnwrap(store.state.backendEvents.first)
        XCTAssertTrue(localEvent.ownerUserID.hasPrefix("local_"))

        sessionProvider.authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_456",
            accountID: "account-private",
            email: "private@example.com"
        )

        await store.syncBackendEvents()

        let request = try XCTUnwrap(syncService.requests.first)
        let syncedRequestEvent = try XCTUnwrap(request.events.first)
        let storedEvent = try XCTUnwrap(store.state.backendEvents.first)

        XCTAssertEqual(request.session.ownerUserID, "firebase_uid_456")
        XCTAssertEqual(syncedRequestEvent.id, localEvent.id)
        XCTAssertEqual(syncedRequestEvent.ownerUserID, "firebase_uid_456")
        XCTAssertEqual(syncedRequestEvent.syncStatus, .inFlight)
        XCTAssertFalse(syncedRequestEvent.idempotencyKey.contains(localEvent.ownerUserID))
        XCTAssertTrue(syncedRequestEvent.idempotencyKey.contains("firebase_uid_456"))
        XCTAssertEqual(storedEvent.ownerUserID, "firebase_uid_456")
        XCTAssertEqual(storedEvent.syncStatus, .acknowledged)
        XCTAssertEqual(storedEvent.idempotencyKey, syncedRequestEvent.idempotencyKey)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.backendEvents, store.state.backendEvents)
    }

    func testBackendEventReowningPreservesOriginalEntityIDForIdempotency() {
        var event = BackendEventRecord(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            kind: .proofClaimed,
            ownerUserID: "local_user",
            occurredAt: Date(timeIntervalSince1970: 20_600),
            entityID: "33333333-3333-4333-8333-333333333333"
        )

        event.assignAuthenticatedOwnerIfLocal("firebase_uid_456")

        XCTAssertEqual(event.entityID, "33333333-3333-4333-8333-333333333333")
        XCTAssertEqual(
            event.idempotencyKey,
            "firebase_uid_456-proofClaimed-33333333-3333-4333-8333-333333333333"
        )
        XCTAssertFalse(event.idempotencyKey.contains(event.id.uuidString))
    }

    func testFirebaseFirestorePayloadEncodesDatesAsFirestoreTimestamps() throws {
        let event = BackendEventRecord(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            kind: .proofClaimed,
            ownerUserID: "firebase_uid_789",
            occurredAt: Date(timeIntervalSince1970: 20_600),
            entityID: "33333333-3333-4333-8333-333333333333",
            retryCount: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 20_650)
        )
        let document = FirebaseBackendEventDocument(
            event: event,
            acceptedAt: Date(timeIntervalSince1970: 20_700)
        )

        let data = try FirebaseFirestorePayload.dictionary(from: document)

        #if canImport(FirebaseFirestore)
        XCTAssertTrue(data["occurredAt"] is Timestamp)
        XCTAssertTrue(data["lastAttemptAt"] is Timestamp)
        XCTAssertTrue(data["acceptedAt"] is Timestamp)
        #else
        XCTAssertTrue((data["occurredAt"] as? String)?.contains("1970-01-01T05:43:20") == true)
        XCTAssertTrue((data["lastAttemptAt"] as? String)?.contains("1970-01-01T05:44:10") == true)
        XCTAssertTrue((data["acceptedAt"] as? String)?.contains("1970-01-01T05:45:00") == true)
        #endif
    }

    func testFirebaseReadyUnauthenticatedSessionLeavesBackendEventsPending() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let syncService = FailingIfCalledBackendEventSyncService()
        var session = BackendUserSession.localOnly(for: .empty)
        session.authProvider = .firebaseAuth
        session.auth = BackendIntegrationRoute(kind: .firebaseAuth, status: .needsAuthentication)
        session.firestore = BackendIntegrationRoute(kind: .firestore, status: .configured)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            backendSessionProvider: StaticBackendSessionProvider(session: session),
            now: { Date(timeIntervalSince1970: 21_000) }
        )

        await store.confirmGoal(goal)
        let eventBeforeSync = try XCTUnwrap(store.state.backendEvents.first)

        await store.syncBackendEvents()

        let eventAfterSync = try XCTUnwrap(store.state.backendEvents.first)
        XCTAssertEqual(eventAfterSync.id, eventBeforeSync.id)
        XCTAssertEqual(eventAfterSync.syncStatus, .pending)
        XCTAssertNil(eventAfterSync.lastAttemptAt)
        XCTAssertEqual(syncService.wasCalled, false)
    }

    func testFirebaseReadyMissingConfigurationLeavesBackendEventsPending() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let syncService = FailingIfCalledBackendEventSyncService()
        var session = BackendUserSession.localOnly(for: .empty)
        session.authProvider = .firebaseAuth
        session.auth = BackendIntegrationRoute(kind: .firebaseAuth, status: .notConnected)
        session.firestore = BackendIntegrationRoute(kind: .firestore, status: .notConnected)
        session.storage = BackendIntegrationRoute(kind: .firebaseStorage, status: .notConnected)
        session.functions = BackendIntegrationRoute(kind: .cloudFunctions, status: .notConnected)
        session.cloudRun = BackendIntegrationRoute(kind: .cloudRun, status: .notConnected)
        session.genkit = BackendIntegrationRoute(kind: .genkit, status: .configured)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            backendEventSyncService: syncService,
            backendSessionProvider: StaticBackendSessionProvider(session: session),
            now: { Date(timeIntervalSince1970: 21_500) }
        )

        await store.confirmGoal(goal)
        let eventBeforeSync = try XCTUnwrap(store.state.backendEvents.first)

        await store.syncBackendEvents()

        let eventAfterSync = try XCTUnwrap(store.state.backendEvents.first)
        XCTAssertEqual(eventAfterSync.id, eventBeforeSync.id)
        XCTAssertEqual(eventAfterSync.syncStatus, .pending)
        XCTAssertNil(eventAfterSync.lastAttemptAt)
        XCTAssertEqual(syncService.wasCalled, false)
    }
}

@MainActor
private struct StaticBackendSessionProvider: BackendSessionProviding {
    var session: BackendUserSession

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        session
    }
}

@MainActor
private final class SwitchingBackendSessionProvider: BackendSessionProviding {
    var authenticatedSession: BackendUserSession?

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        authenticatedSession ?? BackendUserSession.localOnly(for: state)
    }
}

@MainActor
private final class CapturingBackendEventSyncService: BackendEventSyncServicing {
    private(set) var requests: [BackendEventSyncRequest] = []

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        requests.append(request)
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
    }
}

@MainActor
private final class FailingIfCalledBackendEventSyncService: BackendEventSyncServicing {
    private(set) var wasCalled = false

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        wasCalled = true
        XCTFail("Sync service should not be called before Firebase authentication.")
        return BackendEventSyncResult(request: request, receipts: [])
    }
}
