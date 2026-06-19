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

    func testStoreRestoredAuthenticationSessionSynchronizesSubscriptionIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let now = Date(timeIntervalSince1970: 32_000)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_subscription_restore",
            accountID: "firebase_uid_subscription_restore",
            email: "student@example.com"
        )
        let subscriptionState = OpenLARPSubscriptionState(
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: now.addingTimeInterval(86_400 * 30)
            ),
            connectionStatus: .online,
            lastUpdatedAt: now
        )
        let subscriptionService = RecordingSubscriptionIdentityService(synchronizedState: subscriptionState)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            subscriptionService: subscriptionService,
            now: { now }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()

        XCTAssertEqual(subscriptionService.syncIdentityRequestCount, 1)
        XCTAssertEqual(subscriptionService.synchronizedOwnerUserIDs, ["firebase_uid_subscription_restore"])
        XCTAssertEqual(store.state.subscriptionState, subscriptionState)
        XCTAssertEqual(try persistence.load().subscriptionState, subscriptionState)
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

    func testStoreGoogleSignInSynchronizesSubscriptionIdentityBeforeBackendEvents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let now = Date(timeIntervalSince1970: 32_250)
        let googleSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_subscription_google",
            accountID: "firebase_uid_subscription_google",
            email: "newgrad@example.com"
        )
        let subscriptionState = OpenLARPSubscriptionState(
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: now.addingTimeInterval(86_400 * 30)
            ),
            connectionStatus: .online,
            lastUpdatedAt: now
        )
        let subscriptionService = RecordingSubscriptionIdentityService(synchronizedState: subscriptionState)
        let backendEventService = RecordingAuthenticationBackendEventSyncService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(googleSignInSession: googleSession),
            backendEventSyncService: backendEventService,
            subscriptionService: subscriptionService,
            now: { now }
        )

        await store.confirmGoal(goal)
        await store.signInWithGoogle(presenting: nil)

        XCTAssertEqual(subscriptionService.syncIdentityRequestCount, 1)
        XCTAssertEqual(subscriptionService.synchronizedOwnerUserIDs, ["firebase_uid_subscription_google"])
        XCTAssertEqual(store.state.subscriptionState, subscriptionState)
        XCTAssertEqual(backendEventService.requests.count, 1)
    }

    func testStoreAppleSignInUpdatesAccountFieldsWithoutOverwritingCareerProfile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previousSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_previous_apple",
            accountID: "firebase_uid_previous_apple",
            email: "previous@example.com"
        )
        let appleSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_apple",
            accountID: "firebase_uid_apple",
            email: "apple-user@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(
            restoredSession: previousSession,
            appleSignInSession: appleSession
        )
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            privateEvidenceCloudSyncConsentService: LocalMockPrivateEvidenceCloudSyncConsentService(),
            now: { Date(timeIntervalSince1970: 30_750) }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.setPrivateEvidenceCloudSyncEnabled(true)
        let originalDisplayName = try XCTUnwrap(store.state.userProfile?.displayName)
        let originalGoal = store.state.goal

        await store.signInWithApple(presenting: nil)

        XCTAssertEqual(store.authenticationResult?.operation, .signInWithApple)
        XCTAssertEqual(store.authenticationResult?.status, .authenticated)
        XCTAssertEqual(store.currentBackendSessionSnapshot().ownerUserID, "firebase_uid_apple")
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_apple")
        XCTAssertEqual(store.state.userProfile?.email, "apple-user@example.com")
        XCTAssertEqual(store.state.userProfile?.displayName, originalDisplayName)
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, false)
        XCTAssertEqual(store.state.goal, originalGoal)
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountSignInCompleted })
    }

    func testCancelledAppleSignInLeavesLocalAccountStateUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authService = MockOpenLARPAuthenticationService(appleSignInStatus: .cancelled)
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            now: { Date(timeIntervalSince1970: 30_800) }
        )

        await store.confirmGoal(goal)
        let originalProfile = store.state.userProfile
        await store.signInWithApple(presenting: nil)

        XCTAssertEqual(store.authenticationResult?.operation, .signInWithApple)
        XCTAssertEqual(store.authenticationResult?.status, .cancelled)
        XCTAssertEqual(store.state.userProfile, originalProfile)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .accountSignInFailed })
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

    func testStoreSignOutResetsSubscriptionIdentityAndClearsCachedOffering() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let now = Date(timeIntervalSince1970: 32_500)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_subscription_signout",
            accountID: "firebase_uid_subscription_signout",
            email: "switcher@example.com"
        )
        let activeState = OpenLARPSubscriptionState(
            freeSprint: OpenLARPFreeSprintEntitlement(startedAt: now.addingTimeInterval(-86_400)),
            customerInfo: RevenueCatCustomerInfoSnapshot(
                fetchedAt: now,
                activeEntitlementIDs: [OpenLARPSubscriptionConfiguration.placeholder.revenueCatEntitlementID],
                activeProductIDs: [OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID],
                entitlementExpirationDate: now.addingTimeInterval(86_400 * 30)
            ),
            connectionStatus: .online,
            lastUpdatedAt: now
        )
        let resetState = OpenLARPSubscriptionState(
            freeSprint: activeState.freeSprint,
            customerInfo: nil,
            connectionStatus: .notConfigured,
            lastUpdatedAt: now
        )
        let subscriptionService = RecordingSubscriptionIdentityService(resetState: resetState)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            subscriptionService: subscriptionService,
            now: { now }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        store.state.subscriptionState = activeState
        store.currentSubscriptionOffering = RevenueCatOfferingSnapshot(
            identifier: "beta",
            packages: [
                RevenueCatPackageSnapshot(
                    identifier: "monthly",
                    product: RevenueCatProductSnapshot(
                        productID: OpenLARPSubscriptionConfiguration.placeholder.monthlyProductID,
                        displayName: "OpenLARP Monthly",
                        displayPrice: "$9.99",
                        subscriptionPeriod: "1 month"
                    )
                )
            ]
        )

        await store.signOutOfAccount()

        XCTAssertEqual(subscriptionService.resetIdentityRequestCount, 1)
        XCTAssertNil(store.currentSubscriptionOffering)
        XCTAssertEqual(store.state.subscriptionState, resetState)
        XCTAssertEqual(try persistence.load().subscriptionState, resetState)
        XCTAssertEqual(store.subscriptionAccess().status, .freeSprint)
    }

    func testAuthenticationAndAccountDataActionsWaitDuringPrivateEvidenceConsentUpdate() async throws {
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
        let cleanupService = RecordingPrivateEvidenceBackupCleanupService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            privateEvidenceCloudSyncConsentService: consentService,
            privateEvidenceBackupCleanupService: cleanupService,
            now: { Date(timeIntervalSince1970: 31_250) }
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        let consentTask = Task { await store.setPrivateEvidenceCloudSyncEnabled(true) }
        await consentService.waitUntilRequestStarted()
        await store.signInWithGoogle(presenting: nil)
        XCTAssertEqual(store.errorMessage, "Wait for account data controls to finish before changing accounts.")
        await store.checkPrivateEvidenceBackupCleanupCandidates()
        XCTAssertTrue(cleanupService.requests.isEmpty)
        XCTAssertEqual(store.errorMessage, "Wait for account data controls to finish before checking synced private proof backups.")
        consentService.completePendingRequest()
        await consentTask.value

        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_slow_previous")
        XCTAssertEqual(store.state.userProfile?.privacy.allowsPrivateEvidenceCloudSync, true)
        XCTAssertNil(store.errorMessage)
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

    func testFirebaseAuthenticationServiceReportsReadinessWithoutFakeSuccess() async {
        let state = OpenLARPEngine.confirmGoal(goal)
        let service = FirebaseOpenLARPAuthenticationService()

        _ = await service.signOut(for: state)
        let restoreResult = await service.restorePreviousSession(for: state)
        let signInResult = await service.signInWithGoogle(presenting: nil, for: state)
        let appleSignInResult = await service.signInWithApple(presenting: nil, for: state)

        #if canImport(FirebaseCore)
        let hasRuntimeGoogleConfiguration = FirebaseApp.app()?.options.clientID?.isEmpty == false
        #else
        let hasRuntimeGoogleConfiguration = false
        #endif

        if hasRuntimeGoogleConfiguration {
            XCTAssertEqual(restoreResult.status, .signedOut)
            XCTAssertEqual(signInResult.status, .presentationRequired)
            XCTAssertEqual(appleSignInResult.status, .presentationRequired)
        } else {
            XCTAssertEqual(restoreResult.status, .configurationMissing)
            XCTAssertEqual(signInResult.status, .configurationMissing)
            XCTAssertEqual(appleSignInResult.status, .configurationMissing)
        }

        XCTAssertFalse(restoreResult.session.isAuthenticated)
        XCTAssertFalse(signInResult.session.isAuthenticated)
        XCTAssertFalse(appleSignInResult.session.isAuthenticated)
    }

    func testAppleNonceHelperUsesExpectedCharacterSetAndSHA256() throws {
        let bytes = Array(UInt8(0)..<UInt8(32))
        let nonce = OpenLARPAppleSignInCrypto.nonceString(from: bytes)

        XCTAssertEqual(nonce.count, 32)
        XCTAssertTrue(nonce.allSatisfy { OpenLARPAppleSignInCrypto.nonceCharacterSet.contains($0) })
        XCTAssertEqual(
            OpenLARPAppleSignInCrypto.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testPrivateEvidenceBackupCleanupRequiresAuthenticatedSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cleanupService = RecordingPrivateEvidenceBackupCleanupService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(),
            privateEvidenceBackupCleanupService: cleanupService
        )

        await store.confirmGoal(goal)
        await store.checkPrivateEvidenceBackupCleanupCandidates()

        XCTAssertTrue(cleanupService.requests.isEmpty)
        XCTAssertNil(store.privateEvidenceBackupCleanupResult)
        XCTAssertEqual(store.errorMessage, "Sign in before checking synced private proof backups.")
    }

    func testStoreReportsAndDeletesPrivateEvidenceBackupCandidates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_cleanup_store",
            accountID: "firebase_uid_cleanup_store",
            email: "student@example.com"
        )
        let cleanupService = RecordingPrivateEvidenceBackupCleanupService { request in
            switch request.mode {
            case .reportOnly:
                return PrivateEvidenceBackupCleanupResult(
                    request: request,
                    completedAt: request.requestedAt.addingTimeInterval(1),
                    didContactNetwork: true,
                    scannedCount: 1,
                    eligibleCount: 1,
                    candidates: [
                        PrivateEvidenceBackupCleanupCandidate(
                            attachmentID: "attachment_a",
                            proofID: "proof_a",
                            storagePath: "users/firebase_uid_cleanup_store/proofAttachments/attachment_a",
                            storageGeneration: "1",
                            status: .eligible,
                            canDelete: true,
                            deleted: false,
                            reason: "Revoked private evidence sync leaves this backup eligible."
                        )
                    ]
                )
            case .deleteSyncedEvidence:
                XCTAssertEqual(request.attachmentIDs, ["attachment_a"])
                XCTAssertTrue(request.confirmDeletion)
                return PrivateEvidenceBackupCleanupResult(
                    request: request,
                    completedAt: request.requestedAt.addingTimeInterval(1),
                    didContactNetwork: true,
                    scannedCount: 1,
                    eligibleCount: 1,
                    deletedCount: 1,
                    candidates: [
                        PrivateEvidenceBackupCleanupCandidate(
                            attachmentID: "attachment_a",
                            proofID: "proof_a",
                            storagePath: "users/firebase_uid_cleanup_store/proofAttachments/attachment_a",
                            storageGeneration: "1",
                            status: .deleted,
                            canDelete: false,
                            deleted: true,
                            reason: "Uploaded proof backup was deleted."
                        )
                    ],
                    externalActionTaken: true
                )
            }
        }
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            privateEvidenceBackupCleanupService: cleanupService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.checkPrivateEvidenceBackupCleanupCandidates()
        await store.deletePrivateEvidenceBackups(attachmentIDs: ["attachment_a", "attachment_a", " "])

        XCTAssertEqual(cleanupService.requests.map(\.mode), [.reportOnly, .deleteSyncedEvidence])
        XCTAssertEqual(store.privateEvidenceBackupCleanupResult?.mode, .deleteSyncedEvidence)
        XCTAssertEqual(store.privateEvidenceBackupCleanupResult?.deletedCount, 1)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .privateEvidenceBackupCleanupReported })
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .privateEvidenceBackupCleanupDeleted })

        let reloaded = try persistence.load()
        let persistedCandidate = try XCTUnwrap(reloaded.privateEvidenceBackupCleanupResult?.candidates.first)
        XCTAssertNil(persistedCandidate.proofID)
        XCTAssertEqual(persistedCandidate.storagePath, "private proof backup")
        XCTAssertEqual(persistedCandidate.attachmentID, "backup-1")
        XCTAssertFalse(persistedCandidate.canDelete)
    }

    func testBackupDeletionOnlyDeletesCurrentEligibleReportCandidates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_cleanup_eligible",
            accountID: "firebase_uid_cleanup_eligible",
            email: "student@example.com"
        )
        let cleanupService = RecordingPrivateEvidenceBackupCleanupService { request in
            if request.mode == .reportOnly {
                return PrivateEvidenceBackupCleanupResult(
                    request: request,
                    completedAt: request.requestedAt.addingTimeInterval(1),
                    didContactNetwork: true,
                    scannedCount: 1,
                    eligibleCount: 1,
                    candidates: [
                        PrivateEvidenceBackupCleanupCandidate(
                            attachmentID: "eligible_a",
                            proofID: "proof_a",
                            storagePath: "users/firebase_uid_cleanup_eligible/proofAttachments/eligible_a",
                            storageGeneration: "1",
                            status: .eligible,
                            canDelete: true,
                            deleted: false,
                            reason: "Eligible for cleanup."
                        )
                    ]
                )
            }

            XCTAssertEqual(request.attachmentIDs, ["eligible_a"])
            return PrivateEvidenceBackupCleanupResult(
                request: request,
                completedAt: request.requestedAt.addingTimeInterval(1),
                didContactNetwork: true,
                scannedCount: 1,
                eligibleCount: 1,
                deletedCount: 1,
                candidates: [
                    PrivateEvidenceBackupCleanupCandidate(
                        attachmentID: "eligible_a",
                        proofID: "proof_a",
                        storagePath: "users/firebase_uid_cleanup_eligible/proofAttachments/eligible_a",
                        storageGeneration: "1",
                        status: .deleted,
                        canDelete: false,
                        deleted: true,
                        reason: "Uploaded proof backup was deleted."
                    )
                ],
                externalActionTaken: true
            )
        }
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            privateEvidenceBackupCleanupService: cleanupService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.checkPrivateEvidenceBackupCleanupCandidates()
        await store.deletePrivateEvidenceBackups(attachmentIDs: ["eligible_a", "not_in_report"])

        XCTAssertEqual(cleanupService.requests.count, 2)
        XCTAssertEqual(cleanupService.requests.last?.attachmentIDs, ["eligible_a"])
    }

    func testBackupDeletionRejectsIncompleteBackendResponse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_cleanup_incomplete",
            accountID: "firebase_uid_cleanup_incomplete",
            email: "student@example.com"
        )
        let cleanupService = RecordingPrivateEvidenceBackupCleanupService { request in
            if request.mode == .reportOnly {
                return PrivateEvidenceBackupCleanupResult(
                    request: request,
                    completedAt: request.requestedAt.addingTimeInterval(1),
                    didContactNetwork: true,
                    scannedCount: 2,
                    eligibleCount: 2,
                    candidates: [
                        PrivateEvidenceBackupCleanupCandidate(
                            attachmentID: "eligible_a",
                            proofID: "proof_a",
                            storagePath: "users/firebase_uid_cleanup_incomplete/proofAttachments/eligible_a",
                            storageGeneration: "1",
                            status: .eligible,
                            canDelete: true,
                            deleted: false,
                            reason: "Eligible for cleanup."
                        ),
                        PrivateEvidenceBackupCleanupCandidate(
                            attachmentID: "eligible_b",
                            proofID: "proof_b",
                            storagePath: "users/firebase_uid_cleanup_incomplete/proofAttachments/eligible_b",
                            storageGeneration: "2",
                            status: .eligible,
                            canDelete: true,
                            deleted: false,
                            reason: "Eligible for cleanup."
                        )
                    ]
                )
            }

            XCTAssertEqual(request.attachmentIDs, ["eligible_a", "eligible_b"])
            return PrivateEvidenceBackupCleanupResult(
                request: request,
                completedAt: request.requestedAt.addingTimeInterval(1),
                didContactNetwork: true,
                scannedCount: 1,
                eligibleCount: 1,
                deletedCount: 1,
                candidates: [
                    PrivateEvidenceBackupCleanupCandidate(
                        attachmentID: "eligible_a",
                        proofID: "proof_a",
                        storagePath: "users/firebase_uid_cleanup_incomplete/proofAttachments/eligible_a",
                        storageGeneration: "1",
                        status: .deleted,
                        canDelete: false,
                        deleted: true,
                        reason: "Uploaded proof backup was deleted."
                    )
                ],
                externalActionTaken: true
            )
        }
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            privateEvidenceBackupCleanupService: cleanupService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.checkPrivateEvidenceBackupCleanupCandidates()
        await store.deletePrivateEvidenceBackups(attachmentIDs: ["eligible_a", "eligible_b"])

        XCTAssertEqual(cleanupService.requests.count, 2)
        XCTAssertEqual(store.privateEvidenceBackupCleanupResult?.mode, .reportOnly)
        XCTAssertEqual(store.privateEvidenceBackupCleanupResult?.candidates.count, 2)
        XCTAssertEqual(store.errorMessage, "Synced private proof backups could not be deleted.")
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .privateEvidenceBackupCleanupDeleted })
    }

    func testAccountDeletionRequiresExactConfirmationBeforeCallingBackend() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_guard",
            accountID: "firebase_uid_delete_guard",
            email: "student@example.com"
        )
        let deletionService = RecordingAccountDeletionService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: "delete")

        XCTAssertTrue(deletionService.requests.isEmpty)
        XCTAssertNil(store.accountDeletionResult)
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_delete_guard")
        XCTAssertEqual(store.errorMessage, "Type \(AccountDeletionRequest.confirmationText) exactly before deleting the cloud account.")
    }

    func testAccountDeletionCancelledDuringProviderPreparationDoesNotCallBackend() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_prepare_cancel",
            accountID: "firebase_uid_delete_prepare_cancel",
            email: "student@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(
            restoredSession: authenticatedSession,
            accountDeletionPreparationStatus: .cancelled
        )
        let deletionService = RecordingAccountDeletionService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        XCTAssertEqual(store.authenticationResult?.operation, .prepareAccountDeletion)
        XCTAssertEqual(store.authenticationResult?.status, .cancelled)
        XCTAssertTrue(deletionService.requests.isEmpty)
        XCTAssertNil(store.accountDeletionResult)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_delete_prepare_cancel")
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .accountDeletionRequested })
    }

    func testFullAccountDeletionClearsCloudAccountLinkAndSignsOut() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_store",
            accountID: "firebase_uid_delete_store",
            email: "student@example.com"
        )
        let deletionService = RecordingAccountDeletionService { request in
            AccountDeletionResult(
                request: request,
                completedAt: request.requestedAt.addingTimeInterval(2),
                didContactNetwork: true,
                status: .deleted,
                firestoreUserTree: AccountDeletionScopeResult(status: .completed, deletedCount: 4, attemptedCount: 4, failedCount: 0),
                storageUserPrefix: AccountDeletionScopeResult(status: .completed, deletedCount: 2, attemptedCount: 2, failedCount: 0),
                quotaUsageTree: AccountDeletionScopeResult(status: .completed, deletedCount: 1, attemptedCount: 1, failedCount: 0),
                firebaseAuthUser: AccountDeletionAuthResult(status: .deleted),
                deletionRequestMarker: AccountDeletionMarkerResult(status: .completed),
                externalActionTaken: true
            )
        }
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        XCTAssertEqual(deletionService.requests.count, 1)
        XCTAssertEqual(store.accountDeletionResult?.status, .deleted)
        XCTAssertFalse(store.currentBackendSessionSnapshot().isAuthenticated)
        XCTAssertNil(store.state.userProfile?.accountID)
        XCTAssertNil(store.state.userProfile?.email)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountDeletionRequested })
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountDeletionCompleted })
    }

    func testAccountDeletionResultPersistsForSupportAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_persist",
            accountID: "firebase_uid_delete_persist",
            email: "student@example.com"
        )
        let deletionService = RecordingAccountDeletionService { request in
            AccountDeletionResult(
                request: request,
                completedAt: request.requestedAt.addingTimeInterval(2),
                didContactNetwork: true,
                status: .partial,
                firestoreUserTree: AccountDeletionScopeResult(status: .completed, deletedCount: 1),
                storageUserPrefix: AccountDeletionScopeResult(status: .completed, deletedCount: 1),
                quotaUsageTree: AccountDeletionScopeResult(status: .completed, deletedCount: 1),
                firebaseAuthUser: AccountDeletionAuthResult(status: .failed, errorMessage: "auth failed"),
                deletionRequestMarker: AccountDeletionMarkerResult(status: .failed, errorMessage: "marker failed"),
                externalActionTaken: true
            )
        }
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        let reloaded = try persistence.load()
        XCTAssertEqual(reloaded.accountDeletionResult?.status, .partial)
        XCTAssertEqual(reloaded.accountDeletionResult?.firebaseAuthUser.status, .failed)
        XCTAssertEqual(reloaded.accountDeletionResult?.deletionRequestMarker.status, .failed)
        XCTAssertNil(reloaded.accountDeletionResult?.firebaseAuthUser.errorMessage)
        XCTAssertNil(reloaded.accountDeletionResult?.deletionRequestMarker.errorMessage)
    }

    func testSignOutWaitsWhileAccountDataOperationIsInFlight() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_signout_guard",
            accountID: "firebase_uid_signout_guard",
            email: "student@example.com"
        )
        let cleanupService = DelayedPrivateEvidenceBackupCleanupService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            privateEvidenceBackupCleanupService: cleanupService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        let cleanupTask = Task {
            await store.checkPrivateEvidenceBackupCleanupCandidates()
        }
        await cleanupService.waitUntilRequestStarted()
        await store.signOutOfAccount()
        XCTAssertEqual(store.errorMessage, "Wait for account data controls to finish before signing out.")
        cleanupService.completePendingRequest()
        await cleanupTask.value

        XCTAssertTrue(store.currentBackendSessionSnapshot().isAuthenticated)
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .accountSignedOut })
    }

    func testAutomaticRestoreDoesNotSwitchAccountsDuringAccountDataOperation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_restore_first",
            accountID: "firebase_uid_restore_first",
            email: "first@example.com"
        )
        let secondSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_restore_second",
            accountID: "firebase_uid_restore_second",
            email: "second@example.com"
        )
        let authService = MutableRestoreAuthenticationService(restoredSession: firstSession)
        let cleanupService = DelayedPrivateEvidenceBackupCleanupService()
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            privateEvidenceBackupCleanupService: cleanupService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        authService.restoredSession = secondSession
        let cleanupTask = Task {
            await store.checkPrivateEvidenceBackupCleanupCandidates()
        }
        await cleanupService.waitUntilRequestStarted()
        await store.restorePreviousAuthenticationSession()
        cleanupService.completePendingRequest()
        await cleanupTask.value

        XCTAssertEqual(store.currentBackendSessionSnapshot().ownerUserID, "firebase_uid_restore_first")
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_restore_first")
        XCTAssertEqual(authService.restoreCallCount, 1)
    }

    func testPartialAccountDeletionKeepsAccountLinkedForRetry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_partial",
            accountID: "firebase_uid_delete_partial",
            email: "student@example.com"
        )
        let deletionService = RecordingAccountDeletionService { request in
            AccountDeletionResult(
                request: request,
                completedAt: request.requestedAt.addingTimeInterval(2),
                didContactNetwork: true,
                status: .partial,
                firestoreUserTree: AccountDeletionScopeResult(
                    status: .failed,
                    deletedCount: 0,
                    attemptedCount: 1,
                    failedCount: 1,
                    failedPathSamples: ["users/firebase_uid_delete_partial/proofAttachments/private.txt"],
                    errorMessage: "Firestore cleanup failed."
                ),
                storageUserPrefix: AccountDeletionScopeResult(status: .completed, deletedCount: 0, attemptedCount: 0, failedCount: 0),
                quotaUsageTree: AccountDeletionScopeResult(status: .completed, deletedCount: 0, attemptedCount: 0, failedCount: 0),
                firebaseAuthUser: AccountDeletionAuthResult(status: .skipped),
                deletionRequestMarker: AccountDeletionMarkerResult(status: .completed),
                externalActionTaken: true
            )
        }
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        XCTAssertEqual(store.accountDeletionResult?.status, .partial)
        XCTAssertTrue(store.currentBackendSessionSnapshot().isAuthenticated)
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_delete_partial")
        XCTAssertEqual(store.errorMessage, "Cloud account deletion is partial. Keep this result for support and retry after reauthenticating.")
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountDeletionPartial })
    }

    func testPartialAccountDeletionAfterAuthRemovalRetainsSupportResultAcrossReauth() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let deletedAccountSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_auth_removed",
            accountID: "firebase_uid_delete_auth_removed",
            email: "student@example.com"
        )
        let nextAccountSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_after_partial_delete",
            accountID: "firebase_uid_after_partial_delete",
            email: "next@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(
            restoredSession: deletedAccountSession,
            googleSignInSession: nextAccountSession
        )
        let deletionService = RecordingAccountDeletionService { request in
            AccountDeletionResult(
                request: request,
                completedAt: request.requestedAt.addingTimeInterval(2),
                didContactNetwork: true,
                status: .partial,
                firestoreUserTree: AccountDeletionScopeResult(
                    status: .failed,
                    deletedCount: 0,
                    attemptedCount: 1,
                    failedCount: 1,
                    failedPathSamples: ["users/firebase_uid_delete_auth_removed/proofAttachments/private.txt"],
                    errorMessage: "Firestore cleanup failed."
                ),
                storageUserPrefix: AccountDeletionScopeResult(status: .completed, deletedCount: 1, attemptedCount: 1, failedCount: 0),
                quotaUsageTree: AccountDeletionScopeResult(status: .completed, deletedCount: 1, attemptedCount: 1, failedCount: 0),
                firebaseAuthUser: AccountDeletionAuthResult(status: .deleted),
                deletionRequestMarker: AccountDeletionMarkerResult(status: .completed),
                externalActionTaken: true
            )
        }
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        XCTAssertEqual(store.accountDeletionResult?.status, .partial)
        XCTAssertEqual(store.accountDeletionResult?.firebaseAuthUser.status, .deleted)
        XCTAssertFalse(store.currentBackendSessionSnapshot().isAuthenticated)
        XCTAssertNil(store.state.userProfile?.accountID)
        XCTAssertEqual(store.errorMessage, "Cloud account deletion is partial after Firebase Auth was removed. Keep this result for support and contact support.")

        await store.signInWithGoogle(presenting: nil)

        XCTAssertEqual(store.currentBackendSessionSnapshot().ownerUserID, "firebase_uid_after_partial_delete")
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_after_partial_delete")
        XCTAssertEqual(store.accountDeletionResult?.status, .partial)
        XCTAssertEqual(store.accountDeletionResult?.firebaseAuthUser.status, .deleted)
        XCTAssertNil(store.accountDeletionResult?.firestoreUserTree.failedPathSamples)
        XCTAssertNil(store.accountDeletionResult?.firestoreUserTree.errorMessage)
    }

    func testAccountDeletionBackendFailurePersistsUnknownSupportState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_unknown",
            accountID: "firebase_uid_delete_unknown",
            email: "student@example.com"
        )
        let deletionService = RecordingAccountDeletionService { _ in
            throw NSError(domain: "OpenLARPTests", code: 1001)
        }
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        let reloaded = try persistence.load()
        XCTAssertEqual(deletionService.requests.count, 1)
        XCTAssertEqual(store.accountDeletionResult?.status, .unknown)
        XCTAssertEqual(store.accountDeletionResult?.firestoreUserTree.status, .unknown)
        XCTAssertEqual(store.accountDeletionResult?.storageUserPrefix.status, .unknown)
        XCTAssertEqual(store.accountDeletionResult?.quotaUsageTree.status, .unknown)
        XCTAssertEqual(store.accountDeletionResult?.firebaseAuthUser.status, .unknown)
        XCTAssertEqual(store.accountDeletionResult?.deletionRequestMarker.status, .unknown)
        XCTAssertEqual(reloaded.accountDeletionResult?.status, .unknown)
        XCTAssertEqual(reloaded.accountDeletionResult?.firebaseAuthUser.status, .unknown)
        XCTAssertTrue(store.currentBackendSessionSnapshot().isAuthenticated)
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_delete_unknown")
        XCTAssertTrue(store.state.betaEvents.contains { $0.kind == .accountDeletionRequested })
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .accountDeletionCompleted })
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .accountDeletionPartial })
        XCTAssertEqual(
            store.errorMessage,
            "Cloud account deletion started, but OpenLARP could not confirm the final backend result. Keep this status for support, sign in again, and retry before assuming cloud data still exists."
        )
    }

    func testAccountDeletionPersistsUnknownBeforeBackendResponseReturns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_suspended",
            accountID: "firebase_uid_delete_suspended",
            email: "student@example.com"
        )
        let deletionService = DelayedAccountDeletionService()
        let persistence = OpenLARPPersistence(directory: directory)
        let store = OpenLARPStore(
            persistence: persistence,
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        let deletionTask = Task {
            await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)
        }
        await deletionService.waitUntilRequestStarted()

        let reloadedDuringSuspendedCall = try persistence.load()
        XCTAssertEqual(deletionService.requests.count, 1)
        XCTAssertEqual(reloadedDuringSuspendedCall.accountDeletionResult?.status, .unknown)
        XCTAssertEqual(reloadedDuringSuspendedCall.accountDeletionResult?.firebaseAuthUser.status, .unknown)
        XCTAssertTrue(reloadedDuringSuspendedCall.betaEvents.contains { $0.kind == .accountDeletionRequested })
        XCTAssertFalse(reloadedDuringSuspendedCall.betaEvents.contains { $0.kind == .accountDeletionCompleted })
        XCTAssertFalse(reloadedDuringSuspendedCall.betaEvents.contains { $0.kind == .accountDeletionPartial })

        deletionService.completePendingRequest()
        await deletionTask.value
    }

    func testAccountDeletionDoesNotCallBackendWhenUnknownStatusCannotBeSaved() async throws {
        let failingPersistence = OpenLARPPersistence(directory: URL(fileURLWithPath: "/dev/null"))
        let attachmentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authenticatedSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_save_failed",
            accountID: "firebase_uid_delete_save_failed",
            email: "student@example.com"
        )
        let deletionService = RecordingAccountDeletionService()
        let store = OpenLARPStore(
            persistence: failingPersistence,
            attachmentStore: OpenLARPAttachmentStore(directory: attachmentDirectory),
            authenticationService: MockOpenLARPAuthenticationService(restoredSession: authenticatedSession),
            accountDeletionService: deletionService
        )
        store.state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 20_600))
        await store.restorePreviousAuthenticationSession()

        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)

        XCTAssertTrue(deletionService.requests.isEmpty)
        XCTAssertNil(store.accountDeletionResult)
        XCTAssertFalse(store.state.betaEvents.contains { $0.kind == .accountDeletionRequested })
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_delete_save_failed")
        XCTAssertEqual(
            store.errorMessage,
            "Cloud account deletion could not start because local support status could not be saved."
        )
    }

    func testUnknownAccountDeletionSupportResultPersistsAcrossAccountSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let deletedAccountSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_delete_unknown_switch",
            accountID: "firebase_uid_delete_unknown_switch",
            email: "student@example.com"
        )
        let nextAccountSession = BackendUserSession.firebaseAuthenticated(
            ownerUserID: "firebase_uid_after_unknown_delete",
            accountID: "firebase_uid_after_unknown_delete",
            email: "next@example.com"
        )
        let authService = MockOpenLARPAuthenticationService(
            restoredSession: deletedAccountSession,
            googleSignInSession: nextAccountSession
        )
        let deletionService = RecordingAccountDeletionService { _ in
            throw NSError(domain: "OpenLARPTests", code: 1002)
        }
        let store = OpenLARPStore(
            persistence: OpenLARPPersistence(directory: directory),
            attachmentStore: OpenLARPAttachmentStore(directory: directory),
            authenticationService: authService,
            accountDeletionService: deletionService
        )

        await store.confirmGoal(goal)
        await store.restorePreviousAuthenticationSession()
        await store.deleteCloudAccount(confirmationText: AccountDeletionRequest.confirmationText)
        await store.signInWithGoogle(presenting: nil)

        XCTAssertEqual(store.currentBackendSessionSnapshot().ownerUserID, "firebase_uid_after_unknown_delete")
        XCTAssertEqual(store.state.userProfile?.accountID, "firebase_uid_after_unknown_delete")
        XCTAssertEqual(store.accountDeletionResult?.status, .unknown)
        XCTAssertEqual(store.accountDeletionResult?.firebaseAuthUser.status, .unknown)
        XCTAssertNil(store.accountDeletionResult?.firestoreUserTree.failedPathSamples)
        XCTAssertNil(store.accountDeletionResult?.firestoreUserTree.errorMessage)
    }
}

@MainActor
private final class RecordingSubscriptionIdentityService: OpenLARPSubscriptionServicing {
    var subscriptionConfiguration: OpenLARPSubscriptionConfiguration
    var synchronizedState: OpenLARPSubscriptionState?
    var resetState: OpenLARPSubscriptionState?
    private(set) var syncIdentityRequestCount = 0
    private(set) var resetIdentityRequestCount = 0
    private(set) var synchronizedOwnerUserIDs: [String] = []

    init(
        subscriptionConfiguration: OpenLARPSubscriptionConfiguration = .placeholder,
        synchronizedState: OpenLARPSubscriptionState? = nil,
        resetState: OpenLARPSubscriptionState? = nil
    ) {
        self.subscriptionConfiguration = subscriptionConfiguration
        self.synchronizedState = synchronizedState
        self.resetState = resetState
    }

    func currentOffering() async throws -> RevenueCatOfferingSnapshot? {
        nil
    }

    func synchronizeSubscriberIdentity(
        session: BackendUserSession,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        syncIdentityRequestCount += 1
        synchronizedOwnerUserIDs.append(session.ownerUserID)
        var state = synchronizedState ?? currentState
        state.lastUpdatedAt = timestamp
        return state
    }

    func resetSubscriberIdentity(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        resetIdentityRequestCount += 1
        var state = resetState ?? currentState
        state.customerInfo = nil
        state.connectionStatus = .notConfigured
        state.lastUpdatedAt = timestamp
        return state
    }

    func refreshSubscriptionState(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        currentState
    }

    func restorePurchases(
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionState {
        currentState.restoreFailed(at: timestamp)
    }

    func purchasePackage(
        identifier: String,
        expectedProductID: String,
        currentState: OpenLARPSubscriptionState,
        at timestamp: Date
    ) async throws -> OpenLARPSubscriptionPurchaseResult {
        OpenLARPSubscriptionPurchaseResult(
            outcome: .failed(.notConfigured),
            subscriptionState: currentState
        )
    }
}

@MainActor
private final class RecordingAuthenticationBackendEventSyncService: BackendEventSyncServicing {
    private(set) var requests: [BackendEventSyncRequest] = []

    func syncEvents(_ request: BackendEventSyncRequest) async throws -> BackendEventSyncResult {
        requests.append(request)
        return BackendEventSyncResult(
            request: request,
            didContactNetwork: false,
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
private final class DelayedAccountDeletionService: AccountDeletionServicing {
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private(set) var requests: [AccountDeletionRequest] = []

    func deleteAccount(_ request: AccountDeletionRequest) async throws -> AccountDeletionResult {
        requests.append(request)
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
        return AccountDeletionResult(
            request: request,
            completedAt: request.requestedAt.addingTimeInterval(2),
            didContactNetwork: true,
            status: .partial,
            firestoreUserTree: AccountDeletionScopeResult(status: .failed, deletedCount: 0, attemptedCount: 1, failedCount: 1),
            storageUserPrefix: AccountDeletionScopeResult(status: .completed, deletedCount: 0, attemptedCount: 0, failedCount: 0),
            quotaUsageTree: AccountDeletionScopeResult(status: .completed, deletedCount: 0, attemptedCount: 0, failedCount: 0),
            firebaseAuthUser: AccountDeletionAuthResult(status: .skipped),
            deletionRequestMarker: AccountDeletionMarkerResult(status: .completed),
            externalActionTaken: true
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

@MainActor
private final class RecordingPrivateEvidenceBackupCleanupService: PrivateEvidenceBackupCleanupServicing {
    private let handler: (PrivateEvidenceBackupCleanupRequest) throws -> PrivateEvidenceBackupCleanupResult
    private(set) var requests: [PrivateEvidenceBackupCleanupRequest] = []

    init(
        handler: @escaping (PrivateEvidenceBackupCleanupRequest) throws -> PrivateEvidenceBackupCleanupResult = {
            PrivateEvidenceBackupCleanupResult(request: $0, didContactNetwork: false)
        }
    ) {
        self.handler = handler
    }

    func cleanUpBackups(_ request: PrivateEvidenceBackupCleanupRequest) async throws -> PrivateEvidenceBackupCleanupResult {
        requests.append(request)
        return try handler(request)
    }
}

@MainActor
private final class DelayedPrivateEvidenceBackupCleanupService: PrivateEvidenceBackupCleanupServicing {
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func cleanUpBackups(_ request: PrivateEvidenceBackupCleanupRequest) async throws -> PrivateEvidenceBackupCleanupResult {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
        return PrivateEvidenceBackupCleanupResult(
            request: request,
            completedAt: request.requestedAt.addingTimeInterval(1),
            didContactNetwork: true,
            scannedCount: 0,
            eligibleCount: 0
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

@MainActor
private final class MutableRestoreAuthenticationService: OpenLARPAuthenticationServicing {
    var restoredSession: BackendUserSession?
    private(set) var restoreCallCount = 0
    private var activeSession: BackendUserSession?

    init(restoredSession: BackendUserSession?) {
        self.restoredSession = restoredSession
    }

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        activeSession ?? BackendUserSession.localOnly(for: state)
    }

    func restorePreviousSession(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        restoreCallCount += 1
        guard let restoredSession else {
            activeSession = nil
            return OpenLARPAuthenticationResult(
                operation: .restorePreviousSession,
                status: .signedOut,
                session: currentSession(for: state)
            )
        }

        activeSession = restoredSession
        return OpenLARPAuthenticationResult(
            operation: .restorePreviousSession,
            status: .authenticated,
            session: restoredSession
        )
    }

    func signInWithGoogle(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        OpenLARPAuthenticationResult(
            operation: .signInWithGoogle,
            status: .providerSetupRequired,
            session: currentSession(for: state)
        )
    }

    func signInWithApple(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        OpenLARPAuthenticationResult(
            operation: .signInWithApple,
            status: .providerSetupRequired,
            session: currentSession(for: state)
        )
    }

    func prepareAccountDeletion(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        let session = currentSession(for: state)
        return OpenLARPAuthenticationResult(
            operation: .prepareAccountDeletion,
            status: session.isAuthenticated ? .authenticated : .signedOut,
            session: session
        )
    }

    func signOut(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        activeSession = nil
        return OpenLARPAuthenticationResult(
            operation: .signOut,
            status: .signedOut,
            session: currentSession(for: state)
        )
    }

    func handleOpenURL(_ url: URL) -> Bool {
        false
    }
}

@MainActor
private final class RecordingAccountDeletionService: AccountDeletionServicing {
    private let handler: (AccountDeletionRequest) throws -> AccountDeletionResult
    private(set) var requests: [AccountDeletionRequest] = []

    init(
        handler: @escaping (AccountDeletionRequest) throws -> AccountDeletionResult = {
            AccountDeletionResult(request: $0, didContactNetwork: false)
        }
    ) {
        self.handler = handler
    }

    func deleteAccount(_ request: AccountDeletionRequest) async throws -> AccountDeletionResult {
        requests.append(request)
        return try handler(request)
    }
}
