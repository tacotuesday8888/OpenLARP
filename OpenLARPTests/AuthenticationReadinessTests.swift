import XCTest
@testable import OpenLARP

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

    func testFirebaseGoogleSignInServiceReportsMissingConfigurationInsteadOfFakeSuccess() async {
        let state = OpenLARPEngine.confirmGoal(goal)
        let service = FirebaseGoogleSignInAuthenticationService()

        let restoreResult = await service.restorePreviousSession(for: state)
        let signInResult = await service.signInWithGoogle(presenting: nil, for: state)

        XCTAssertEqual(restoreResult.status, .configurationMissing)
        XCTAssertEqual(signInResult.status, .configurationMissing)
        XCTAssertFalse(restoreResult.session.isAuthenticated)
        XCTAssertFalse(signInResult.session.isAuthenticated)
    }
}
