import XCTest
@testable import OpenLARP
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@MainActor
final class AuthenticationReadinessTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .newGrad,
        targetRole: "AI product engineer",
        timeline: "30 days",
        background: "Recent graduate with one AI prototype.",
        existingProof: "Prototype demo and project notes.",
        confidence: 3,
        biggestBlocker: "Needs stronger product proof."
    )

    func testMockAuthenticationStartsInLocalModeWithoutPretendingFirebaseIsReady() async {
        let state = OpenLARPEngine.confirmGoal(goal)
        let service = MockOpenLARPAuthenticationService()

        let result = await service.restorePreviousSession(for: state)

        XCTAssertEqual(result.operation, .restorePreviousSession)
        XCTAssertEqual(result.status, .signedOut)
        XCTAssertEqual(result.session.authProvider, .localMock)
        XCTAssertFalse(result.session.isAuthenticated)
        XCTAssertEqual(result.session.auth.status, .notConnected)
    }

    func testMockAuthenticationCanRestoreAConfiguredAuthenticatedSession() async {
        let state = OpenLARPEngine.confirmGoal(goal)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_123",
            accountID: "firebase_uid_123",
            email: "student@example.com"
        )
        let service = MockOpenLARPAuthenticationService(restoredSession: authenticatedSession)

        let result = await service.restorePreviousSession(for: state)

        XCTAssertEqual(result.status, .authenticated)
        XCTAssertEqual(result.session.ownerUserID, "firebase_uid_123")
        XCTAssertEqual(result.session.email, "student@example.com")
        XCTAssertEqual(service.currentSession(for: state), authenticatedSession)
    }

    func testMockAuthenticationSignOutReturnsToLocalSession() async {
        let state = OpenLARPEngine.confirmGoal(goal)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_456",
            accountID: "firebase_uid_456",
            email: "switcher@example.com"
        )
        let service = MockOpenLARPAuthenticationService(restoredSession: authenticatedSession)
        _ = await service.restorePreviousSession(for: state)

        let result = await service.signOut(for: state)

        XCTAssertEqual(result.operation, .signOut)
        XCTAssertEqual(result.status, .signedOut)
        XCTAssertEqual(result.session.authProvider, .localMock)
        XCTAssertFalse(result.session.isAuthenticated)
        XCTAssertEqual(service.currentSession(for: state).authProvider, .localMock)
    }

    func testStoreRestoresPreviousAuthenticationSessionAndUsesItForBackendOwnership() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_store_restore",
            accountID: "firebase_uid_store_restore",
            email: "student@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(restoredSession: authenticatedSession)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            now: { Date(timeIntervalSince1970: 30_000) }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()

        let session = store.currentBackendSessionSnapshot()
        XCTAssertEqual(store.authenticationResult?.operation, .restorePreviousSession)
        XCTAssertEqual(store.authenticationResult?.status, .authenticated)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.ownerUserID, "firebase_uid_store_restore")
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_store_restore")
        XCTAssertEqual(store.state.userProfile?.email, "student@example.com")
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountSessionRestored })
    }

    func testStoreGoogleSignInUpdatesAccountFieldsWithoutOverwritingCareerProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previousSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_previous",
            accountID: "firebase_uid_previous",
            email: "previous@example.com"
        )
        let googleSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_google",
            accountID: "firebase_uid_google",
            email: "newgrad@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(
            restoredSession: previousSession,
            googleSignInSession: googleSession
        )
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            privateEvidenceCloudSyncConsentService: LocalMockPrivateEvidenceCloudSyncConsentService(),
            now: { Date(timeIntervalSince1970: 30_500) }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.setPrivateEvidenceCloudSyncEnabled(true)
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, true)
        let originalDisplayName = try XCTUnwrap(store.state.userProfile?.displayName)
        let originalGoal = store.state.goal

        await store.signInWithGoogle(presenting: nil)

        XCTAssertEqual(store.authenticationResult?.operation, .signInWithGoogle)
        XCTAssertEqual(store.authenticationResult?.status, .authenticated)
        XCTAssertEqual(store.currentBackendSessionSnapshot().ownerUserID, "firebase_uid_google")
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_google")
        XCTAssertEqual(store.state.userProfile?.email, "newgrad@example.com")
        XCTAssertEqual(store.state.userProfile?.displayName, originalDisplayName)
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, false)
        XCTAssertEqual(store.state.goal, originalGoal)
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountSignInCompleted })
    }

    func testStoreSignOutClearsAccountFieldsAndReturnsToLocalSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_signout",
            accountID: "firebase_uid_signout",
            email: "switcher@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(restoredSession: authenticatedSession)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            privateEvidenceCloudSyncConsentService: LocalMockPrivateEvidenceCloudSyncConsentService(),
            now: { Date(timeIntervalSince1970: 31_000) }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.setPrivateEvidenceCloudSyncEnabled(true)
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, true)
        await store.signOutOfAccount()

        XCTAssertEqual(store.authenticationResult?.operation, .signOut)
        XCTAssertEqual(store.authenticationResult?.status, .signedOut)
        XCTAssertFalse(store.currentBackendSessionSnapshot().isAuthenticated)
        XCTAssertEqual(store.currentBackendSessionSnapshot().authProvider, .localMock)
        XCTAssertNil(store.state.userProfile?.accountID)
        XCTAssertNil(store.state.userProfile?.email)
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, false)
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountSignedOut })
    }

    func testPrivateEvidenceConsentResultIsIgnoredWhenAccountChangesDuringRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previousSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_slow_previous",
            accountID: "firebase_uid_slow_previous",
            email: "previous@example.com"
        )
        let nextSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_slow_next",
            accountID: "firebase_uid_slow_next",
            email: "next@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(
            restoredSession: previousSession,
            googleSignInSession: nextSession
        )
        let consentService = DelayedPrivateEvidenceCloudSyncConsentService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            privateEvidenceCloudSyncConsentService: consentService,
            now: { Date(timeIntervalSince1970: 31_250) }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        let consentTask = Task { await store.setPrivateEvidenceCloudSyncEnabled(true) }
        await consentService.waitUntilRequestStarted()
        await store.signInWithGoogle(presenting: nil)
        consentService.completePendingRequest()
        await consentTask.value

        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_slow_next")
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, false)
        XCTAssertEqual(store.errorMessage, "Private evidence cloud sync could not be enabled.")
    }

    func testStoreForwardsAuthenticationOpenURLToInjectedService() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authService = MockOpenLARPAuthenticationService(
            handledURLSchemes: ["com.googleusercontent.apps.openlarp-test"]
        )
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService
        )

        XCTAssertTrue(store.handleOpenURL(URL(string: "com.googleusercontent.apps.openlarp-test:/oauth2redirect")!))
        XCTAssertFalse(store.handleOpenURL(URL(string: "openlarp:/not-google")!))
    }

    func testFirebaseGoogleSignInServiceReportsReadinessWithoutFakeSuccess() async {
        let state = OpenLARPEngine.confirmGoal(goal)
        let service = FirebaseGoogleSignInAuthenticationService()

        _ = await service.signOut(for: state)
        let restoreResult = await service.restorePreviousSession(for: state)
        let signInResult = await service.signInWithGoogle(presenting: nil, for: state)

        #if canImport(FirebaseCore)
        let hasRuntimeGoogleConfiguration = FirebaseApp.app()?.options.clientID?.isEmpty == false
        #else
        let hasRuntimeGoogleConfiguration = false
        #endif

        if hasRuntimeGoogleConfiguration {
            XCTAssertEqual(restoreResult.status, .signedOut)
            XCTAssertEqual(signInResult.status, .presentationRequired)
        } else {
            XCTAssertEqual(restoreResult.status, .configurationMissing)
            XCTAssertEqual(signInResult.status, .configurationMissing)
        }

        XCTAssertFalse(restoreResult.session.isAuthenticated)
        XCTAssertFalse(signInResult.session.isAuthenticated)
    }
}

@MainActor
private final class DelayedPrivateEvidenceCloudSyncConsentService: PrivateEvidenceCloudSyncConsentServicing {
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func setConsent(_ request: PrivateEvidenceCloudSyncConsentRequest) async throws -> PrivateEvidenceCloudSyncConsentResult {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
        return PrivateEvidenceCloudSyncConsentResult(
            request: request,
            completedAt: request.requestedAt.addingTimeInterval(1),
            didContactNetwork: true,
            status: request.enabled ? .accepted : .revoked,
            firestoreDocumentPath: "users/\(request.session.ownerUserID)/consents/privateEvidenceCloudSync"
        )
    }

    func waitUntilRequestStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func completePendingRequest() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }
}
