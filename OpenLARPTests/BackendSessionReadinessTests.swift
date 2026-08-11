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
        let document = FirestoreTimestampProbe(
            occurredAt: Date(timeIntervalSince1970: 20_600),
            lastAttemptAt: Date(timeIntervalSince1970: 20_650),
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

    func testFirebaseBackendEventSyncResponseValidatesReceiptsAndBuildsResult() throws {
        let request = makeAuthenticatedBackendEventSyncRequest()
        let response = validFirebaseBackendEventSyncResponse(for: request)

        let result = try response.validatedResult(for: request)

        XCTAssertEqual(result.requestedAt, request.requestedAt)
        XCTAssertEqual(result.completedAt, response.completedAt)
        XCTAssertEqual(result.didContactNetwork, true)
        XCTAssertEqual(result.receipts, response.receipts)
        XCTAssertEqual(result.integrationRoutes, request.integrationRoutes)
    }

    func testFirebaseBackendEventSyncResponseRejectsMismatchedUserID() throws {
        let request = makeAuthenticatedBackendEventSyncRequest()
        var response = validFirebaseBackendEventSyncResponse(for: request)
        response.userID = "other_user"

        XCTAssertThrowsError(try response.validatedResult(for: request)) { error in
            guard case FirebaseBackendServiceError.contractMismatch = error else {
                return XCTFail("Expected contract mismatch, got \(error)")
            }
        }
    }

    func testFirebaseBackendEventSyncResponseRejectsMismatchedRequestedAt() throws {
        let request = makeAuthenticatedBackendEventSyncRequest()
        var response = validFirebaseBackendEventSyncResponse(for: request)
        response.requestedAt = Date(timeIntervalSince1970: 20_701)

        XCTAssertThrowsError(try response.validatedResult(for: request)) { error in
            guard case FirebaseBackendServiceError.contractMismatch = error else {
                return XCTFail("Expected contract mismatch, got \(error)")
            }
        }
    }

    func testFirebaseBackendEventSyncResponseRejectsMismatchedReceipt() throws {
        let request = makeAuthenticatedBackendEventSyncRequest()
        var response = validFirebaseBackendEventSyncResponse(for: request)
        response.receipts[0] = BackendEventSyncReceipt(
            eventID: request.events[0].id,
            idempotencyKey: "forged-key",
            status: .acknowledged,
            acceptedAt: response.completedAt
        )

        XCTAssertThrowsError(try response.validatedResult(for: request)) { error in
            guard case FirebaseBackendServiceError.contractMismatch = error else {
                return XCTFail("Expected contract mismatch, got \(error)")
            }
        }
    }

    func testFirebaseBackendEventSyncResponseRejectsReceiptAfterCompletion() throws {
        let request = makeAuthenticatedBackendEventSyncRequest()
        var response = validFirebaseBackendEventSyncResponse(for: request)
        response.receipts[0] = BackendEventSyncReceipt(
            eventID: request.events[0].id,
            idempotencyKey: request.events[0].idempotencyKey,
            status: .acknowledged,
            acceptedAt: Date(timeIntervalSince1970: 20_900)
        )

        XCTAssertThrowsError(try response.validatedResult(for: request)) { error in
            guard case FirebaseBackendServiceError.contractMismatch = error else {
                return XCTFail("Expected contract mismatch, got \(error)")
            }
        }
    }

    func testFirebaseAccountDeletionResponseRejectsUnknownStatusesFromBackend() throws {
        let request = makeAuthenticatedAccountDeletionRequest()
        var response = validFirebaseAccountDeletionResponse(for: request)
        response.status = .partial
        response.firestoreUserTree = AccountDeletionScopeResult(
            status: .unknown,
            deletedCount: 0,
            attemptedCount: nil,
            failedCount: nil
        )

        XCTAssertThrowsError(try response.validatedResult(for: request)) { error in
            guard case FirebaseBackendServiceError.contractMismatch = error else {
                return XCTFail("Expected contract mismatch, got \(error)")
            }
        }
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

    private func makeAuthenticatedBackendEventSyncRequest() -> BackendEventSyncRequest {
        BackendEventSyncRequest(
            session: BackendUserSession.firebaseAuthenticated(
                ownerUserID: "firebase_uid_789",
                accountID: "account-should-not-sync",
                email: "private@example.com"
            ),
            events: [
                BackendEventRecord(
                    id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                    kind: .proofClaimed,
                    syncStatus: .inFlight,
                    ownerUserID: "firebase_uid_789",
                    occurredAt: Date(timeIntervalSince1970: 20_600),
                    entityID: "33333333-3333-4333-8333-333333333333",
                    retryCount: 1,
                    lastAttemptAt: Date(timeIntervalSince1970: 20_650),
                    summary: BackendEventSummary(proofCount: 1, qualityAccepted: true)
                )
            ],
            requestedAt: Date(timeIntervalSince1970: 20_700)
        )
    }

    private func validFirebaseBackendEventSyncResponse(
        for request: BackendEventSyncRequest
    ) -> FirebaseBackendEventSyncResponse {
        FirebaseBackendEventSyncResponse(
            ok: true,
            schemaVersion: 1,
            userID: request.session.ownerUserID,
            requestedAt: request.requestedAt,
            completedAt: Date(timeIntervalSince1970: 20_800),
            didContactNetwork: true,
            receipts: request.events.map {
                BackendEventSyncReceipt(
                    eventID: $0.id,
                    idempotencyKey: $0.idempotencyKey,
                    status: .acknowledged,
                    acceptedAt: Date(timeIntervalSince1970: 20_800)
                )
            },
            externalActionTaken: false
        )
    }

    private func makeAuthenticatedAccountDeletionRequest() -> AccountDeletionRequest {
        AccountDeletionRequest(
            session: BackendUserSession.firebaseAuthenticated(
                ownerUserID: "firebase_uid_delete_contract",
                accountID: "account-should-not-sync",
                email: "private@example.com"
            ),
            confirmDeletion: true,
            confirmationText: AccountDeletionRequest.confirmationText,
            requestedAt: Date(timeIntervalSince1970: 21_000)
        )
    }

    private func validFirebaseAccountDeletionResponse(
        for request: AccountDeletionRequest
    ) -> FirebaseAccountDeletionResponse {
        FirebaseAccountDeletionResponse(
            ok: true,
            schemaVersion: 1,
            userID: request.session.ownerUserID,
            status: .deleted,
            requestedAt: request.requestedAt,
            completedAt: Date(timeIntervalSince1970: 21_100),
            firestoreUserTree: AccountDeletionScopeResult(
                status: .completed,
                deletedCount: 4,
                attemptedCount: 4,
                failedCount: 0
            ),
            storageUserPrefix: AccountDeletionScopeResult(
                status: .completed,
                deletedCount: 2,
                attemptedCount: 2,
                failedCount: 0
            ),
            quotaUsageTree: AccountDeletionScopeResult(
                status: .completed,
                deletedCount: 1,
                attemptedCount: 1,
                failedCount: 0
            ),
            firebaseAuthUser: AccountDeletionAuthResult(status: .deleted),
            deletionRequestMarker: AccountDeletionMarkerResult(status: .completed),
            externalActionTaken: true
        )
    }
    func testCareerStateCloudPayloadKeepsDeviceAndPrivateDataOutWithoutConsent() throws {
        let timestamp = Date(timeIntervalSince1970: 24_000)
        var state = OpenLARPEngine.confirmGoal(goal, now: timestamp)
        state.userProfile?.accountID = "firebase_uid_private"
        state.userProfile?.email = "private@example.com"
        state.questReminders = QuestReminderPreferences(
            isEnabled: true,
            hour: 9,
            minute: 30,
            cadence: .everyDay
        )
        let proof = ProofRecord(
            id: UUID(),
            questID: state.plan[0].id,
            questTitle: state.plan[0].title,
            kind: .proof,
            text: "Private proof text",
            link: "https://private.example.com",
            attachments: [ProofAttachment(
                fileName: "private.png",
                contentType: "image/png",
                byteCount: 123,
                createdAt: timestamp,
                localRelativePath: "ProofAttachments/device-only.png"
            )],
            submittedAt: timestamp,
            quality: nil
        )
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1
        state.outcomeLog = [CareerOutcomeRecord(
            kind: .interview,
            title: "Private interview",
            note: "Sensitive note",
            occurredAt: timestamp,
            targetRoleTitle: goal.targetRole,
            isPrivate: true
        )]

        let payload = CareerStateCloudPayload(state: state)
        let encoded = String(decoding: try JSONEncoder.openLARPPersistence.encode(payload), as: UTF8.self)

        XCTAssertFalse(payload.includesPrivateEvidence)
        XCTAssertNil(payload.state.userProfile?.accountID)
        XCTAssertNil(payload.state.userProfile?.email)
        XCTAssertEqual(payload.state.questReminders, .off)
        XCTAssertTrue(payload.state.progress.recentProof.isEmpty)
        XCTAssertTrue(payload.state.outcomeLog.isEmpty)
        XCTAssertFalse(encoded.contains("private@example.com"))
        XCTAssertFalse(encoded.contains("Private proof text"))
        XCTAssertFalse(encoded.contains("device-only.png"))
        XCTAssertFalse(encoded.contains("Sensitive note"))
        XCTAssertEqual(payload, CareerStateCloudPayload(state: state))
        XCTAssertEqual(payload.state.agentBrief, .empty)
    }

    func testStateMigrationDefaultsCareerStateSyncMetadataForSchemaFifteen() throws {
        let data = try JSONEncoder.openLARPPersistence.encode(OpenLARPState.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 15
        object.removeValue(forKey: "careerStateSync")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.openLARPPersistence.decode(OpenLARPState.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, OpenLARPState.currentSchemaVersion)
        XCTAssertEqual(decoded.careerStateSync, .empty)
    }

    func testCareerStateSyncRequestUsesFirebaseAuthAsOwnerAuthority() throws {
        let timestamp = Date(timeIntervalSince1970: 24_050)
        let state = OpenLARPEngine.confirmGoal(goal, now: timestamp)
        let request = CareerStateSyncRequest(
            state: state,
            session: BackendUserSession.firebaseAuthenticated(
                ownerUserID: "firebase_uid_should_not_be_in_payload",
                accountID: "private-account-id",
                email: "private@example.com"
            ),
            requestedAt: timestamp
        )

        let encoded = String(decoding: try JSONEncoder.openLARPPersistence.encode(request), as: UTF8.self)

        XCTAssertTrue(request.session.isAuthenticated)
        XCTAssertNil(request.session.accountID)
        XCTAssertNil(request.session.email)
        XCTAssertFalse(encoded.contains("firebase_uid_should_not_be_in_payload"))
        XCTAssertFalse(encoded.contains("private-account-id"))
        XCTAssertFalse(encoded.contains("private@example.com"))
    }

    func testCareerStateCloudPayloadRestoresReceiptsWithoutReplacingLocalAttachmentFiles() throws {
        let timestamp = Date(timeIntervalSince1970: 24_100)
        var state = OpenLARPEngine.confirmGoal(goal, now: timestamp)
        state.userProfile?.privacy.allowsPrivateEvidenceCloudSync = true
        let proofID = UUID()
        let localAttachment = ProofAttachment(
            fileName: "private.png",
            contentType: "image/png",
            byteCount: 123,
            createdAt: timestamp,
            localRelativePath: "ProofAttachments/device-only.png"
        )
        let proof = ProofRecord(
            id: proofID,
            questID: state.plan[0].id,
            questTitle: state.plan[0].title,
            kind: .proof,
            text: "Truthful proof receipt",
            link: "",
            attachments: [localAttachment],
            submittedAt: timestamp,
            quality: nil
        )
        state.progress.recentProof = [proof]
        state.progress.proofCount = 1

        let payload = CareerStateCloudPayload(state: state)
        let encoded = String(decoding: try JSONEncoder.openLARPPersistence.encode(payload), as: UTF8.self)
        let restored = try XCTUnwrap(payload.restoredState(preserving: state))

        XCTAssertTrue(payload.includesPrivateEvidence)
        XCTAssertEqual(payload.state.progress.recentProof.first?.text, "Truthful proof receipt")
        XCTAssertTrue(payload.state.progress.recentProof.first?.attachments.isEmpty ?? false)
        XCTAssertFalse(encoded.contains("device-only.png"))
        XCTAssertEqual(restored.progress.recentProof.first?.attachments, [localAttachment])
    }

    func testStoreRestoresCloudCareerStateOntoEmptyAuthenticatedDevice() async throws {
        let timestamp = Date(timeIntervalSince1970: 24_200)
        let session = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_restore",
            email: "restored@example.com"
        )
        var cloudState = OpenLARPEngine.confirmGoal(goal, now: timestamp)
        cloudState.progress.xp = 420
        let payload = CareerStateCloudPayload(state: cloudState)
        let syncService = RecordingCareerStateSyncService(results: [CareerStateSyncResult(
            schemaVersion: 1,
            status: .restored,
            revision: 4,
            payloadHash: String(repeating: "a", count: 64),
            cloudPayload: payload,
            serverUpdatedAt: timestamp,
            completedAt: timestamp,
            didWrite: false
        )])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            careerStateSyncService: syncService,
            backendSessionProvider: StaticBackendSessionProvider(session: session),
            now: { timestamp }
        )

        await store.synchronizeCareerState()

        XCTAssertEqual(store.state.goal, goal)
        XCTAssertEqual(store.state.progress.xp, 420)
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_restore")
        XCTAssertEqual(store.state.userProfile?.email, "restored@example.com")
        XCTAssertEqual(store.state.careerStateSync.status, .inSync)
        XCTAssertEqual(store.state.careerStateSync.revision, 4)
        XCTAssertNil(store.careerStateSyncConflict)
        XCTAssertEqual(try persistence.load(), store.state)
    }

    func testStorePreservesLocalStateOnConflictAndUsesObservedRevisionWhenKeepingDevice() async throws {
        let timestamp = Date(timeIntervalSince1970: 24_300)
        let session = BackendUserSession.firebaseAuthenticated(ownerUserID: "firebase_uid_conflict")
        var localState = OpenLARPEngine.confirmGoal(goal, now: timestamp)
        localState.progress.xp = 111
        var cloudState = localState
        cloudState.progress.xp = 999
        let cloudPayload = CareerStateCloudPayload(state: cloudState)
        let syncService = RecordingCareerStateSyncService(results: [
            CareerStateSyncResult(
                schemaVersion: 1,
                status: .conflict,
                revision: 7,
                payloadHash: String(repeating: "b", count: 64),
                cloudPayload: cloudPayload,
                serverUpdatedAt: timestamp,
                completedAt: timestamp,
                didWrite: false
            ),
            CareerStateSyncResult(
                schemaVersion: 1,
                status: .uploaded,
                revision: 8,
                payloadHash: String(repeating: "c", count: 64),
                cloudPayload: nil,
                serverUpdatedAt: timestamp,
                completedAt: timestamp,
                didWrite: true
            )
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            careerStateSyncService: syncService,
            backendSessionProvider: StaticBackendSessionProvider(session: session),
            now: { timestamp }
        )
        store.state = localState

        await store.synchronizeCareerState()

        XCTAssertEqual(store.state.progress.xp, 111)
        XCTAssertEqual(store.state.careerStateSync.status, .conflict)
        XCTAssertEqual(store.careerStateSyncConflict?.revision, 7)

        await store.resolveCareerStateConflictKeepingThisDevice()

        XCTAssertEqual(syncService.requests.last?.action, .keepLocal)
        XCTAssertEqual(syncService.requests.last?.expectedRevision, 7)
        XCTAssertEqual(store.state.progress.xp, 111)
        XCTAssertEqual(store.state.careerStateSync.revision, 8)
        XCTAssertEqual(store.state.careerStateSync.status, .inSync)
    }
}

private struct FirestoreTimestampProbe: Encodable {
    var occurredAt: Date
    var lastAttemptAt: Date
    var acceptedAt: Date
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
private final class RecordingCareerStateSyncService: CareerStateSyncServicing {
    private(set) var requests: [CareerStateSyncRequest] = []
    private var results: [CareerStateSyncResult]

    init(results: [CareerStateSyncResult]) {
        self.results = results
    }

    func sync(_ request: CareerStateSyncRequest) async throws -> CareerStateSyncResult {
        requests.append(request)
        guard !results.isEmpty else {
            throw BackendSessionReadinessTestError.missingCareerStateSyncResult
        }
        return results.removeFirst()
    }
}

private enum BackendSessionReadinessTestError: Error {
    case missingCareerStateSyncResult
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
