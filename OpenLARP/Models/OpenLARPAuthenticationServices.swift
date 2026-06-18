import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
@preconcurrency import FirebaseAuth
#endif

#if canImport(GoogleSignIn)
@preconcurrency import GoogleSignIn
#endif

#if canImport(UIKit)
import UIKit
typealias OpenLARPAuthenticationPresentationAnchor = UIViewController
#else
typealias OpenLARPAuthenticationPresentationAnchor = AnyObject
#endif

enum OpenLARPAuthenticationOperation: String, Codable, Equatable, CaseIterable {
    case restorePreviousSession
    case signInWithGoogle
    case signOut
    case handleOpenURL
}

enum OpenLARPAuthenticationStatus: String, Codable, Equatable, CaseIterable {
    case signedOut
    case authenticated
    case configurationMissing
    case sdkUnavailable
    case providerSetupRequired
    case presentationRequired
    case failed
}

struct OpenLARPAuthenticationResult: Equatable {
    var operation: OpenLARPAuthenticationOperation
    var status: OpenLARPAuthenticationStatus
    var session: BackendUserSession
    var message: String?

    init(
        operation: OpenLARPAuthenticationOperation,
        status: OpenLARPAuthenticationStatus,
        session: BackendUserSession,
        message: String? = nil
    ) {
        self.operation = operation
        self.status = status
        self.session = session
        self.message = message
    }
}

@MainActor
protocol OpenLARPAuthenticationServicing: BackendSessionProviding {
    func restorePreviousSession(for state: OpenLARPState) async -> OpenLARPAuthenticationResult
    func signInWithGoogle(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult
    func signOut(for state: OpenLARPState) async -> OpenLARPAuthenticationResult
    func handleOpenURL(_ url: URL) -> Bool
}

@MainActor
final class MockOpenLARPAuthenticationService: OpenLARPAuthenticationServicing {
    private let restoredSession: BackendUserSession?
    private let googleSignInSession: BackendUserSession?
    private let handledURLSchemes: Set<String>
    private var activeSession: BackendUserSession?

    init(
        restoredSession: BackendUserSession? = nil,
        googleSignInSession: BackendUserSession? = nil,
        handledURLSchemes: Set<String> = []
    ) {
        self.restoredSession = restoredSession
        self.googleSignInSession = googleSignInSession
        self.handledURLSchemes = handledURLSchemes
    }

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        activeSession ?? BackendUserSession.localOnly(for: state)
    }

    func restorePreviousSession(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
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
        guard let googleSignInSession else {
            activeSession = nil
            return OpenLARPAuthenticationResult(
                operation: .signInWithGoogle,
                status: .providerSetupRequired,
                session: currentSession(for: state),
                message: "Mock Google sign-in is not configured for this test."
            )
        }

        activeSession = googleSignInSession
        return OpenLARPAuthenticationResult(
            operation: .signInWithGoogle,
            status: .authenticated,
            session: googleSignInSession
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
        guard let scheme = url.scheme else { return false }
        return handledURLSchemes.contains(scheme)
    }
}

struct FirebaseGoogleSignInAuthenticationService: OpenLARPAuthenticationServicing {
    private let sessionProvider: FirebaseBackendSessionProvider

    /// Real Google Sign-In needs the ignored Firebase plist at runtime, the Google provider enabled
    /// in Firebase Auth, the reversed client ID URL scheme in app configuration, and app-level URL
    /// forwarding to `handleOpenURL(_:)`.
    init(sessionProvider: FirebaseBackendSessionProvider = FirebaseBackendSessionProvider()) {
        self.sessionProvider = sessionProvider
    }

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        sessionProvider.currentSession(for: state)
    }

    func restorePreviousSession(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard configureGoogleSignInIfPossible() else {
            return setupResult(operation: .restorePreviousSession, status: .configurationMissing, state: state)
        }

        do {
            let googleUser = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return await signInToFirebase(with: googleUser, operation: .restorePreviousSession, state: state)
        } catch {
            return OpenLARPAuthenticationResult(
                operation: .restorePreviousSession,
                status: .signedOut,
                session: currentSession(for: state),
                message: error.localizedDescription
            )
        }
        #else
        return setupResult(operation: .restorePreviousSession, status: .sdkUnavailable, state: state)
        #endif
    }

    func signInWithGoogle(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(GoogleSignIn) && canImport(UIKit)
        guard configureGoogleSignInIfPossible() else {
            return setupResult(operation: .signInWithGoogle, status: .configurationMissing, state: state)
        }

        guard let anchor else {
            return OpenLARPAuthenticationResult(
                operation: .signInWithGoogle,
                status: .presentationRequired,
                session: currentSession(for: state),
                message: "Google Sign-In needs a presenting UIViewController from the app UI."
            )
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: anchor)
            return await signInToFirebase(with: result.user, operation: .signInWithGoogle, state: state)
        } catch {
            return OpenLARPAuthenticationResult(
                operation: .signInWithGoogle,
                status: .failed,
                session: currentSession(for: state),
                message: error.localizedDescription
            )
        }
        #elseif canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(GoogleSignIn)
        return setupResult(operation: .signInWithGoogle, status: .presentationRequired, state: state)
        #else
        return setupResult(operation: .signInWithGoogle, status: .sdkUnavailable, state: state)
        #endif
    }

    func signOut(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard FirebaseApp.app() != nil else {
            return setupResult(operation: .signOut, status: .configurationMissing, state: state)
        }

        GIDSignIn.sharedInstance.signOut()

        do {
            try Auth.auth().signOut()
            return OpenLARPAuthenticationResult(
                operation: .signOut,
                status: .signedOut,
                session: currentSession(for: state)
            )
        } catch {
            return OpenLARPAuthenticationResult(
                operation: .signOut,
                status: .failed,
                session: currentSession(for: state),
                message: error.localizedDescription
            )
        }
        #else
        return setupResult(operation: .signOut, status: .sdkUnavailable, state: state)
        #endif
    }

    func handleOpenURL(_ url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.handle(url)
        #else
        false
        #endif
    }

    private func setupResult(
        operation: OpenLARPAuthenticationOperation,
        status: OpenLARPAuthenticationStatus,
        state: OpenLARPState
    ) -> OpenLARPAuthenticationResult {
        OpenLARPAuthenticationResult(
            operation: operation,
            status: status,
            session: currentSession(for: state),
            message: setupMessage(for: status)
        )
    }

    private func setupMessage(for status: OpenLARPAuthenticationStatus) -> String? {
        switch status {
        case .configurationMissing:
            "Firebase must be configured with local GoogleService-Info.plist and Google provider setup before Google Sign-In can run."
        case .sdkUnavailable:
            "FirebaseAuth and GoogleSignIn SDK products must be linked before Google Sign-In can run."
        case .providerSetupRequired:
            "Google provider setup is incomplete. Enable Google Sign-In in Firebase Auth and add the reversed client ID URL scheme."
        case .presentationRequired:
            "Google Sign-In needs a presenting UIViewController from the app UI."
        case .signedOut, .authenticated, .failed:
            nil
        }
    }

    #if canImport(FirebaseCore) && canImport(GoogleSignIn)
    private func configureGoogleSignInIfPossible() -> Bool {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            return false
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        return true
    }
    #endif

    #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
    private func signInToFirebase(
        with googleUser: GIDGoogleUser,
        operation: OpenLARPAuthenticationOperation,
        state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        guard let idToken = googleUser.idToken?.tokenString else {
            return setupResult(operation: operation, status: .providerSetupRequired, state: state)
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )

        do {
            _ = try await Auth.auth().signIn(with: credential)
            let session = currentSession(for: state)
            return OpenLARPAuthenticationResult(
                operation: operation,
                status: session.isAuthenticated ? .authenticated : .failed,
                session: session
            )
        } catch {
            return OpenLARPAuthenticationResult(
                operation: operation,
                status: .failed,
                session: currentSession(for: state),
                message: error.localizedDescription
            )
        }
    }
    #endif
}
