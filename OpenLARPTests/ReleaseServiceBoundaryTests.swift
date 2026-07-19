import XCTest
@testable import OpenLARP

@MainActor
final class ReleaseServiceBoundaryTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .newGrad,
        targetRole: "iOS product engineer",
        timeline: "30 days",
        background: "Recent graduate with one shipped prototype.",
        existingProof: "Prototype demo and project notes.",
        confidence: 3,
        biggestBlocker: "Needs stronger product proof."
    )

    func testReleaseProfilesUseDistinctExplicitServiceModes() {
        XCTAssertEqual(OpenLARPReleaseConfiguration.appStoreMVP.serviceMode, .localOnly)
        XCTAssertEqual(OpenLARPReleaseConfiguration.internalBeta.serviceMode, .firebaseBeta)
    }

    func testAppStoreFactorySkipsFirebaseBootstrapAndInternalBuilder() {
        let localServices = makeTemporaryLocalServices()
        defer { try? FileManager.default.removeItem(at: localServices.directory) }
        var calls: [String] = []
        let factory = OpenLARPAppStoreFactory(
            localPersistence: localServices.persistence,
            localAttachmentStore: localServices.attachmentStore,
            firebaseBootstrap: {
                calls.append("bootstrap")
            },
            internalStoreBuilder: { configuration in
                calls.append("builder")
                return OpenLARPStore(
                    persistence: localServices.persistence,
                    attachmentStore: localServices.attachmentStore,
                    releaseConfiguration: configuration
                )
            }
        )

        let store = factory.makeStore(for: .appStoreMVP)

        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(store.releaseConfiguration, .appStoreMVP)
    }

    func testInternalFactoryBootstrapsBeforeCallingInjectedBuilder() {
        let localServices = makeTemporaryLocalServices()
        defer { try? FileManager.default.removeItem(at: localServices.directory) }
        var calls: [String] = []
        let factory = OpenLARPAppStoreFactory(
            localPersistence: localServices.persistence,
            localAttachmentStore: localServices.attachmentStore,
            firebaseBootstrap: {
                calls.append("bootstrap")
            },
            internalStoreBuilder: { configuration in
                calls.append("builder:\(configuration.channel.rawValue)")
                return OpenLARPStore(
                    persistence: localServices.persistence,
                    attachmentStore: localServices.attachmentStore,
                    releaseConfiguration: configuration
                )
            }
        )

        let store = factory.makeStore(for: .internalBeta)

        XCTAssertEqual(calls, ["bootstrap", "builder:internal-beta"])
        XCTAssertEqual(store.releaseConfiguration, .internalBeta)
    }

    func testAppStoreWorkflowStaysLocalAndNeverCallsInjectedRemoteAuthOrSessionServices() async throws {
        let localServices = makeTemporaryLocalServices()
        defer { try? FileManager.default.removeItem(at: localServices.directory) }
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_public_boundary",
            accountID: "account-public-boundary",
            email: "public-boundary@example.com"
        )
        let workflow = RecordingRemoteWorkflowService()
        let authentication = RecordingAuthenticationService(session: authenticatedSession)
        let sessionProvider = RecordingBackendSessionProvider(session: authenticatedSession)
        let store = OpenLARPStore(
            persistence: localServices.persistence,
            attachmentStore: localServices.attachmentStore,
            aiWorkflowService: workflow,
            authenticationService: authentication,
            backendSessionProvider: sessionProvider,
            releaseConfiguration: .appStoreMVP,
            now: { Date(timeIntervalSince1970: 80_000) }
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I mapped role requirements into a concrete prototype improvement.",
            link: "https://example.com/local-proof"
        )
        let session = store.currentBackendSessionSnapshot()
        let handledURL = store.handleOpenURL(
            URL(string: "com.googleusercontent.apps.openlarp:/oauth2redirect")!
        )

        XCTAssertEqual(workflow.calls, [])
        XCTAssertEqual(authentication.totalCallCount, 0)
        XCTAssertEqual(sessionProvider.callCount, 0)
        XCTAssertEqual(store.state.aiWorkflowRuns.map(\.kind), [
            .cookedDiagnostic,
            .questPlan,
            .proofQualityCheck
        ])
        XCTAssertTrue(store.state.aiWorkflowRuns.allSatisfy { $0.providerRoute == .localMock })
        XCTAssertNotNil(store.pendingQualityResult)
        XCTAssertNil(store.state.userProfile?.accountID)
        XCTAssertNil(store.state.userProfile?.email)
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertEqual(session.authProvider, .localMock)
        XCTAssertTrue(session.ownerUserID.hasPrefix("local_"))
        XCTAssertFalse(store.state.backendEvents.isEmpty)
        XCTAssertTrue(store.state.backendEvents.allSatisfy { $0.ownerUserID == session.ownerUserID })
        XCTAssertFalse(handledURL)
    }

    func testAppStoreStoreReplacesEveryInjectedExternalService() async {
        let localServices = makeTemporaryLocalServices()
        defer { try? FileManager.default.removeItem(at: localServices.directory) }
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_service_graph",
            accountID: "account-service-graph",
            email: "service-graph@example.com"
        )
        let workflow = RecordingRemoteWorkflowService()
        let agent = RecordingAgentService()
        let graph = RecordingCareerGraphSyncService()
        let authentication = RecordingAuthenticationService(session: authenticatedSession)
        let backendEvents = RecordingBackendEventSyncService()
        let consent = RecordingPrivateEvidenceConsentService()
        let cleanup = RecordingPrivateEvidenceCleanupService()
        let deletion = RecordingAccountDeletionService()
        let sessionProvider = RecordingBackendSessionProvider(session: authenticatedSession)
        let subscriptions = RecordingSubscriptionService()
        let store = OpenLARPStore(
            persistence: localServices.persistence,
            attachmentStore: localServices.attachmentStore,
            aiWorkflowService: workflow,
            agentService: agent,
            careerGraphSyncService: graph,
            authenticationService: authentication,
            backendEventSyncService: backendEvents,
            privateEvidenceCloudSyncConsentService: consent,
            privateEvidenceBackupCleanupService: cleanup,
            accountDeletionService: deletion,
            backendSessionProvider: sessionProvider,
            subscriptionService: subscriptions,
            releaseConfiguration: .appStoreMVP,
            now: { Date(timeIntervalSince1970: 81_000) }
        )

        await store.confirmGoal(goal)
        await store.runAgentScan()
        await store.prepareCareerGraphSyncPreview()
        await store.syncBackendEvents()
        await store.setPrivateEvidenceCloudSyncEnabled(true)
        await store.checkPrivateEvidenceBackupCleanupCandidates()
        await store.refreshSubscriptionStatus()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        XCTAssertEqual(workflow.calls, [])
        XCTAssertEqual(agent.callCount, 0)
        XCTAssertEqual(graph.callCount, 0)
        XCTAssertEqual(authentication.totalCallCount, 0)
        XCTAssertEqual(backendEvents.callCount, 0)
        XCTAssertEqual(consent.callCount, 0)
        XCTAssertEqual(cleanup.callCount, 0)
        XCTAssertEqual(deletion.callCount, 0)
        XCTAssertEqual(sessionProvider.callCount, 0)
        XCTAssertEqual(subscriptions.totalCallCount, 0)
        XCTAssertEqual(store.careerGraphSyncPreview?.didContactNetwork, false)
    }

    func testAccountDisabledConfigurationFailsClosedEvenInFirebaseServiceMode() {
        let localServices = makeTemporaryLocalServices()
        defer { try? FileManager.default.removeItem(at: localServices.directory) }
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_disabled_account",
            accountID: "account-disabled",
            email: "disabled-account@example.com"
        )
        let authentication = RecordingAuthenticationService(session: authenticatedSession)
        let sessionProvider = RecordingBackendSessionProvider(session: authenticatedSession)
        let configuration = OpenLARPReleaseConfiguration(
            channel: .internalBeta,
            accessMode: .free,
            serviceMode: .firebaseBeta,
            enabledCapabilities: []
        )
        let store = OpenLARPStore(
            persistence: localServices.persistence,
            attachmentStore: localServices.attachmentStore,
            authenticationService: authentication,
            backendSessionProvider: sessionProvider,
            releaseConfiguration: configuration
        )

        let session = store.currentBackendSessionSnapshot()
        let handledURL = store.handleOpenURL(
            URL(string: "com.googleusercontent.apps.openlarp:/oauth2redirect")!
        )

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertEqual(session.authProvider, .localMock)
        XCTAssertTrue(session.ownerUserID.hasPrefix("local_"))
        XCTAssertEqual(sessionProvider.callCount, 0)
        XCTAssertFalse(handledURL)
        XCTAssertEqual(authentication.totalCallCount, 0)
    }

    func testInternalBetaPreservesInjectedWorkflowAuthenticationAndSessionServices() async throws {
        let localServices = makeTemporaryLocalServices()
        defer { try? FileManager.default.removeItem(at: localServices.directory) }
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_internal_boundary",
            accountID: "account-internal-boundary",
            email: "internal-boundary@example.com"
        )
        let workflow = RecordingRemoteWorkflowService()
        let authentication = RecordingAuthenticationService(session: authenticatedSession)
        let sessionProvider = RecordingBackendSessionProvider(session: authenticatedSession)
        let store = OpenLARPStore(
            persistence: localServices.persistence,
            attachmentStore: localServices.attachmentStore,
            aiWorkflowService: workflow,
            authenticationService: authentication,
            backendSessionProvider: sessionProvider,
            releaseConfiguration: .internalBeta,
            now: { Date(timeIntervalSince1970: 82_000) }
        )

        await store.confirmGoal(goal)
        store.startCurrentQuest()
        await store.checkProof(
            kind: .proof,
            text: "I completed a concrete internal beta proof artifact.",
            link: "https://example.com/internal-proof"
        )
        let session = store.currentBackendSessionSnapshot()
        let handledURL = store.handleOpenURL(
            URL(string: "com.googleusercontent.apps.openlarp:/oauth2redirect")!
        )

        XCTAssertEqual(workflow.calls, [.cookedDiagnostic, .questPlan, .proofQualityCheck])
        XCTAssertEqual(store.state.aiWorkflowRuns.map(\.providerRoute), [
            .firebaseCallableGenkit,
            .firebaseCallableGenkit,
            .firebaseCallableGenkit
        ])
        XCTAssertGreaterThan(sessionProvider.callCount, 0)
        XCTAssertEqual(authentication.handleURLCallCount, 1)
        XCTAssertTrue(handledURL)
        XCTAssertEqual(session, authenticatedSession)
        XCTAssertEqual(store.state.userProfile?.accountID, "account-internal-boundary")
        XCTAssertEqual(store.state.userProfile?.email, "internal-boundary@example.com")
        XCTAssertTrue(store.state.backendEvents.allSatisfy { $0.ownerUserID == "firebase_internal_boundary" })
    }

    private func makeTemporaryLocalServices() -> (
        directory: URL,
        persistence: OpenLARPPersistence,
        attachmentStore: OpenLARPAttachmentStore
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (
            directory,
            OpenLARPPersistence(directory: directory),
            OpenLARPAttachmentStore(directory: directory)
        )
    }
}

@MainActor
private final class RecordingRemoteWorkflowService: V0AIWorkflowServicing {
    private(set) var calls: [V0AIWorkflowKind] = []

    func generateDiagnostic(_ request: V0DiagnosticRequest) async throws -> V0DiagnosticResponse {
        calls.append(.cookedDiagnostic)
        var response = try await LocalMockV0AIWorkflowService().generateDiagnostic(request)
        response.run.providerRoute = .firebaseCallableGenkit
        return response
    }

    func generateQuestPlan(_ request: V0QuestPlanRequest) async throws -> V0QuestPlanResponse {
        calls.append(.questPlan)
        var response = try await LocalMockV0AIWorkflowService().generateQuestPlan(request)
        response.run.providerRoute = .firebaseCallableGenkit
        return response
    }

    func reviewProof(_ request: V0ProofReviewRequest) async throws -> V0ProofReviewResponse {
        calls.append(.proofQualityCheck)
        var response = try await LocalMockV0AIWorkflowService().reviewProof(request)
        response.run.providerRoute = .firebaseCallableGenkit
        return response
    }

    func summarizeProgress(_ request: V0ProgressSummaryRequest) async throws -> V0ProgressSummaryResponse {
        calls.append(.progressSummary)
        var response = try await LocalMockV0AIWorkflowService().summarizeProgress(request)
        response.run.providerRoute = .firebaseCallableGenkit
        return response
    }
}

@MainActor
private final class RecordingAuthenticationService: OpenLARPAuthenticationServicing {
    let session: BackendUserSession
    private(set) var currentSessionCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var googleSignInCallCount = 0
    private(set) var appleSignInCallCount = 0
    private(set) var deletionPreparationCallCount = 0
    private(set) var signOutCallCount = 0
    private(set) var handleURLCallCount = 0

    var totalCallCount: Int {
        currentSessionCallCount + restoreCallCount + googleSignInCallCount +
            appleSignInCallCount + deletionPreparationCallCount + signOutCallCount +
            handleURLCallCount
    }

    init(session: BackendUserSession) {
        self.session = session
    }

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        currentSessionCallCount += 1
        return session
    }

    func restorePreviousSession(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        restoreCallCount += 1
        return authenticatedResult(for: .restorePreviousSession)
    }

    func signInWithGoogle(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        googleSignInCallCount += 1
        return authenticatedResult(for: .signInWithGoogle)
    }

    func signInWithApple(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        appleSignInCallCount += 1
        return authenticatedResult(for: .signInWithApple)
    }

    func prepareAccountDeletion(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        deletionPreparationCallCount += 1
        return authenticatedResult(for: .prepareAccountDeletion)
    }

    func signOut(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        signOutCallCount += 1
        return OpenLARPAuthenticationResult(
            operation: .signOut,
            status: .signedOut,
            session: BackendUserSession.localOnly(for: state)
        )
    }

    func handleOpenURL(_ url: URL) -> Bool {
        handleURLCallCount += 1
        return true
    }

    private func authenticatedResult(
        for operation: OpenLARPAuthenticationOperation
    ) -> OpenLARPAuthenticationResult {
        OpenLARPAuthenticationResult(
            operation: operation,
            status: .authenticated,
            session: session
        )
    }
}

@MainActor
private final class RecordingBackendSessionProvider: BackendSessionProviding {
    let session: BackendUserSession
    private(set) var callCount = 0

    init(session: BackendUserSession) {
        self.session = session
    }

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        callCount += 1
        return session
    }
}

@MainActor
private final class RecordingAgentService: CareerAgentBriefServicing {
    private(set) var callCount = 0

    func generateBrief(for state: OpenLARPState) async throws -> AgentBrief {
        callCount += 1
        return try await MockCareerAgentService().generateBrief(for: state)
    }
}

private final class RecordingCareerGraphSyncService: CareerGraphSyncServicing, @unchecked Sendable {
    private(set) var callCount = 0

    func prepareSync(_ request: CareerGraphSyncPreparationRequest) async throws -> CareerGraphSyncResult {
        callCount += 1
        return try await LocalMockCareerGraphSyncService().prepareSync(request)
    }
}

@MainActor
private final class RecordingBackendEventSyncService: BackendEventSyncServicing {
    private(set) var callCount = 0

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        callCount += 1
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
private final class RecordingPrivateEvidenceConsentService: PrivateEvidenceCloudSyncConsentServicing {
    private(set) var callCount = 0

    func setConsent(
        _ request: PrivateEvidenceCloudSyncConsentRequest
    ) async throws -> PrivateEvidenceCloudSyncConsentResult {
        callCount += 1
        return PrivateEvidenceCloudSyncConsentResult(
            request: request,
            didContactNetwork: true,
            status: request.enabled ? .accepted : .revoked
        )
    }
}

@MainActor
private final class RecordingPrivateEvidenceCleanupService: PrivateEvidenceBackupCleanupServicing {
    private(set) var callCount = 0

    func cleanUpBackups(
        _ request: PrivateEvidenceBackupCleanupRequest
    ) async throws -> PrivateEvidenceBackupCleanupResult {
        callCount += 1
        return PrivateEvidenceBackupCleanupResult(
            request: request,
            didContactNetwork: true
        )
    }
}

@MainActor
private final class RecordingAccountDeletionService: AccountDeletionServicing {
    private(set) var callCount = 0

    func deleteAccount(_ request: AccountDeletionRequest) async throws -> AccountDeletionResult {
        callCount += 1
        return AccountDeletionResult(
            request: request,
            didContactNetwork: true
        )
    }
}

@MainActor
private final class RecordingSubscriptionService: OpenLARPSubscriptionServicing {
    let subscriptionConfiguration = OpenLARPSubscriptionConfiguration.placeholder
    private(set) var offeringCallCount = 0
    private(set) var synchronizeCallCount = 0
    private(set) var resetCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var purchaseCallCount = 0

    var totalCallCount: Int {
        offeringCallCount + synchronizeCallCount + resetCallCount +
            refreshCallCount + restoreCallCount + purchaseCallCount
    }

    func currentOffering() async throws -> RevenueCatOfferingSnapshot? {
        offeringCallCount += 1
        return nil
    }

    func synchronizeSubscriberIdentity(
        session: BackendUserSession,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        synchronizeCallCount += 1
        return currentState
    }

    func resetSubscriberIdentity(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        resetCallCount += 1
        return currentState
    }

    func refreshSubscriptionState(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        refreshCallCount += 1
        return currentState
    }

    func restorePurchases(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        restoreCallCount += 1
        return currentState
    }

    func purchasePackage(
        identifier: String,
        expectedProductID: String,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionPurchaseResult {
        purchaseCallCount += 1
        return OpenLARPSubscriptionPurchaseResult(
            outcome: .failed(.notConfigured),
            subscriptionState: currentState
        )
    }
}
