import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
@preconcurrency import FirebaseAuth
#endif

#if canImport(GoogleSignIn)
@preconcurrency import GoogleSignIn
#endif

#if canImport(Security)
import Security
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
    case signInWithApple
    case prepareAccountDeletion
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
    case cancelled
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
    func signInWithApple(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult
    func prepareAccountDeletion(
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
    private let appleSignInSession: BackendUserSession?
    private let appleSignInStatus: OpenLARPAuthenticationStatus
    private let accountDeletionPreparationStatus: OpenLARPAuthenticationStatus
    private let handledURLSchemes: Set<String>
    private var activeSession: BackendUserSession?

    init(
        restoredSession: BackendUserSession? = nil,
        googleSignInSession: BackendUserSession? = nil,
        appleSignInSession: BackendUserSession? = nil,
        appleSignInStatus: OpenLARPAuthenticationStatus = .authenticated,
        accountDeletionPreparationStatus: OpenLARPAuthenticationStatus = .authenticated,
        handledURLSchemes: Set<String> = []
    ) {
        self.restoredSession = restoredSession
        self.googleSignInSession = googleSignInSession
        self.appleSignInSession = appleSignInSession
        self.appleSignInStatus = appleSignInStatus
        self.accountDeletionPreparationStatus = accountDeletionPreparationStatus
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

    func signInWithApple(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        guard appleSignInStatus != .cancelled else {
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: .cancelled,
                session: currentSession(for: state),
                message: "Sign in with Apple was cancelled."
            )
        }

        guard let appleSignInSession else {
            activeSession = nil
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: .providerSetupRequired,
                session: currentSession(for: state),
                message: "Mock Apple sign-in is not configured for this test."
            )
        }

        guard appleSignInStatus == .authenticated else {
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: appleSignInStatus,
                session: currentSession(for: state)
            )
        }

        activeSession = appleSignInSession
        return OpenLARPAuthenticationResult(
            operation: .signInWithApple,
            status: .authenticated,
            session: appleSignInSession
        )
    }

    func prepareAccountDeletion(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        let session = currentSession(for: state)
        guard accountDeletionPreparationStatus == .authenticated else {
            return OpenLARPAuthenticationResult(
                operation: .prepareAccountDeletion,
                status: accountDeletionPreparationStatus,
                session: session,
                message: accountDeletionPreparationStatus == .cancelled
                    ? "Apple account deletion confirmation was cancelled."
                    : "Cloud account deletion needs recent sign-in before it can continue."
            )
        }

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
        guard let scheme = url.scheme else { return false }
        return handledURLSchemes.contains(scheme)
    }
}

struct FirebaseOpenLARPAuthenticationService: OpenLARPAuthenticationServicing {
    private let sessionProvider: FirebaseBackendSessionProvider

    /// Real provider sign-in needs the ignored Firebase plist at runtime, provider setup in
    /// Firebase Auth, app-level callback/capability setup, and backend-owned account deletion.
    init(sessionProvider: FirebaseBackendSessionProvider = FirebaseBackendSessionProvider()) {
        self.sessionProvider = sessionProvider
    }

    func currentSession(for state: OpenLARPState) -> BackendUserSession {
        sessionProvider.currentSession(for: state)
    }

    func restorePreviousSession(for state: OpenLARPState) async -> OpenLARPAuthenticationResult {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard FirebaseApp.app() != nil else {
            return setupResult(operation: .restorePreviousSession, status: .configurationMissing, state: state)
        }

        if Auth.auth().currentUser != nil {
            return OpenLARPAuthenticationResult(
                operation: .restorePreviousSession,
                status: .authenticated,
                session: currentSession(for: state)
            )
        }

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

    func signInWithApple(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(AuthenticationServices) && canImport(UIKit) && canImport(CryptoKit)
        guard FirebaseApp.app() != nil else {
            return setupResult(operation: .signInWithApple, status: .configurationMissing, state: state)
        }

        guard let presentationAnchor = applePresentationAnchor(from: anchor) else {
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: .presentationRequired,
                session: currentSession(for: state),
                message: "Sign in with Apple needs a presentation window from the current iOS screen."
            )
        }

        do {
            let appleCredential = try await requestAppleCredential(
                presenting: presentationAnchor,
                requestedScopes: [.fullName, .email]
            )
            let credential = try firebaseCredential(from: appleCredential)
            _ = try await Auth.auth().signIn(with: credential)
            let session = currentSession(for: state)
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: session.isAuthenticated ? .authenticated : .failed,
                session: session
            )
        } catch OpenLARPAppleAuthorizationError.cancelled {
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: .cancelled,
                session: currentSession(for: state),
                message: "Sign in with Apple was cancelled."
            )
        } catch OpenLARPAppleAuthorizationError.nonceUnavailable {
            return setupResult(operation: .signInWithApple, status: .sdkUnavailable, state: state)
        } catch OpenLARPAppleAuthorizationError.missingIdentityToken {
            return setupResult(operation: .signInWithApple, status: .providerSetupRequired, state: state)
        } catch {
            return OpenLARPAuthenticationResult(
                operation: .signInWithApple,
                status: .failed,
                session: currentSession(for: state),
                message: error.localizedDescription
            )
        }
        #elseif canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(AuthenticationServices)
        return setupResult(operation: .signInWithApple, status: .presentationRequired, state: state)
        #else
        return setupResult(operation: .signInWithApple, status: .sdkUnavailable, state: state)
        #endif
    }

    func prepareAccountDeletion(
        presenting anchor: OpenLARPAuthenticationPresentationAnchor?,
        for state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(UIKit)
        guard FirebaseApp.app() != nil else {
            return setupResult(operation: .prepareAccountDeletion, status: .configurationMissing, state: state)
        }

        guard let user = Auth.auth().currentUser else {
            return OpenLARPAuthenticationResult(
                operation: .prepareAccountDeletion,
                status: .signedOut,
                session: currentSession(for: state),
                message: "Sign in again before deleting the cloud account."
            )
        }

        let providerIDs = Set(user.providerData.map(\.providerID))

        if providerIDs.contains("apple.com") {
            #if canImport(AuthenticationServices) && canImport(CryptoKit)
            guard let presentationAnchor = applePresentationAnchor(from: anchor) else {
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .presentationRequired,
                    session: currentSession(for: state),
                    message: "Apple account deletion needs a fresh Sign in with Apple confirmation window."
                )
            }

            do {
                let appleCredential = try await requestAppleCredential(
                    presenting: presentationAnchor,
                    requestedScopes: []
                )
                let credential = try firebaseCredential(from: appleCredential)
                guard let authorizationCode = appleCredential.authorizationCode else {
                    return setupResult(operation: .prepareAccountDeletion, status: .providerSetupRequired, state: state)
                }
                _ = try await user.reauthenticate(with: credential)
                _ = try await user.getIDTokenResult(forcingRefresh: true)
                try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .authenticated,
                    session: currentSession(for: state)
                )
            } catch OpenLARPAppleAuthorizationError.cancelled {
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .cancelled,
                    session: currentSession(for: state),
                    message: "Apple account deletion confirmation was cancelled."
                )
            } catch OpenLARPAppleAuthorizationError.nonceUnavailable {
                return setupResult(operation: .prepareAccountDeletion, status: .sdkUnavailable, state: state)
            } catch OpenLARPAppleAuthorizationError.missingIdentityToken,
                    OpenLARPAppleAuthorizationError.missingAuthorizationCode {
                return setupResult(operation: .prepareAccountDeletion, status: .providerSetupRequired, state: state)
            } catch {
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .failed,
                    session: currentSession(for: state),
                    message: error.localizedDescription
                )
            }
            #else
            return setupResult(operation: .prepareAccountDeletion, status: .sdkUnavailable, state: state)
            #endif
        }

        if providerIDs.contains("google.com") {
            #if canImport(GoogleSignIn)
            guard configureGoogleSignInIfPossible() else {
                return setupResult(operation: .prepareAccountDeletion, status: .configurationMissing, state: state)
            }

            guard let anchor else {
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .presentationRequired,
                    session: currentSession(for: state),
                    message: "Google account deletion needs a fresh Google Sign-In confirmation window."
                )
            }

            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: anchor)
                guard let credential = firebaseCredential(from: result.user) else {
                    return setupResult(operation: .prepareAccountDeletion, status: .providerSetupRequired, state: state)
                }
                _ = try await user.reauthenticate(with: credential)
                _ = try await user.getIDTokenResult(forcingRefresh: true)
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .authenticated,
                    session: currentSession(for: state)
                )
            } catch {
                return OpenLARPAuthenticationResult(
                    operation: .prepareAccountDeletion,
                    status: .failed,
                    session: currentSession(for: state),
                    message: error.localizedDescription
                )
            }
            #else
            return setupResult(operation: .prepareAccountDeletion, status: .sdkUnavailable, state: state)
            #endif
        }

        if providerIDs.isEmpty {
            return setupResult(operation: .prepareAccountDeletion, status: .providerSetupRequired, state: state)
        }

        return OpenLARPAuthenticationResult(
            operation: .prepareAccountDeletion,
            status: .providerSetupRequired,
            session: currentSession(for: state),
            message: "Cloud account deletion needs a supported provider reauthentication step before it can continue."
        )
        #elseif canImport(FirebaseCore) && canImport(FirebaseAuth)
        return setupResult(operation: .prepareAccountDeletion, status: .presentationRequired, state: state)
        #else
        return setupResult(operation: .prepareAccountDeletion, status: .sdkUnavailable, state: state)
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
            message: setupMessage(for: status, operation: operation)
        )
    }

    private func setupMessage(
        for status: OpenLARPAuthenticationStatus,
        operation: OpenLARPAuthenticationOperation
    ) -> String? {
        switch status {
        case .configurationMissing:
            configurationMessage(for: operation)
        case .sdkUnavailable:
            sdkUnavailableMessage(for: operation)
        case .providerSetupRequired:
            providerSetupMessage(for: operation)
        case .presentationRequired:
            presentationMessage(for: operation)
        case .signedOut, .authenticated, .cancelled, .failed:
            nil
        }
    }

    private func configurationMessage(for operation: OpenLARPAuthenticationOperation) -> String {
        switch operation {
        case .signInWithApple:
            "Firebase must be configured with local GoogleService-Info.plist and Apple provider setup before Sign in with Apple can run."
        case .prepareAccountDeletion:
            "Firebase must be configured with local GoogleService-Info.plist and provider setup before cloud account deletion can run."
        case .restorePreviousSession, .signInWithGoogle, .signOut, .handleOpenURL:
            "Firebase must be configured with local GoogleService-Info.plist and Google provider setup before Google Sign-In can run."
        }
    }

    private func sdkUnavailableMessage(for operation: OpenLARPAuthenticationOperation) -> String {
        switch operation {
        case .signInWithApple:
            "FirebaseAuth, AuthenticationServices, and CryptoKit must be available before Sign in with Apple can run."
        case .prepareAccountDeletion:
            "FirebaseAuth and the signed-in account provider SDK must be linked before cloud account deletion can run."
        case .restorePreviousSession, .signInWithGoogle, .signOut, .handleOpenURL:
            "FirebaseAuth and GoogleSignIn SDK products must be linked before Google Sign-In can run."
        }
    }

    private func providerSetupMessage(for operation: OpenLARPAuthenticationOperation) -> String {
        switch operation {
        case .signInWithApple:
            "Apple provider setup is incomplete. Enable Sign in with Apple in Apple Developer and Firebase Auth."
        case .prepareAccountDeletion:
            "Provider setup is incomplete. Enable the signed-in provider in Firebase Auth before cloud account deletion."
        case .restorePreviousSession, .signInWithGoogle, .signOut, .handleOpenURL:
            "Google provider setup is incomplete. Enable Google Sign-In in Firebase Auth and add the reversed client ID URL scheme."
        }
    }

    private func presentationMessage(for operation: OpenLARPAuthenticationOperation) -> String {
        switch operation {
        case .signInWithApple:
            "Sign in with Apple needs a presentation window from the current iOS screen."
        case .prepareAccountDeletion:
            "Cloud account deletion needs a fresh provider confirmation window."
        case .restorePreviousSession, .signInWithGoogle, .signOut, .handleOpenURL:
            "Google Sign-In needs a presenting UIViewController from the app UI."
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

    #if canImport(AuthenticationServices) && canImport(UIKit)
    private func applePresentationAnchor(
        from anchor: OpenLARPAuthenticationPresentationAnchor?
    ) -> ASPresentationAnchor? {
        anchor?.view.window
    }
    #endif

    #if canImport(FirebaseAuth) && canImport(AuthenticationServices) && canImport(CryptoKit) && canImport(UIKit)
    private func requestAppleCredential(
        presenting presentationAnchor: ASPresentationAnchor,
        requestedScopes: [ASAuthorization.Scope]
    ) async throws -> OpenLARPAppleAuthorizationCredential {
        let rawNonce = try OpenLARPAppleSignInCrypto.randomNonceString()
        guard let nonce = OpenLARPAppleSignInCrypto.sha256(rawNonce) else {
            throw OpenLARPAppleAuthorizationError.nonceUnavailable
        }

        let coordinator = OpenLARPAppleAuthorizationCoordinator()
        return try await coordinator.requestCredential(
            rawNonce: rawNonce,
            nonce: nonce,
            requestedScopes: requestedScopes,
            presentationAnchor: presentationAnchor
        )
    }

    private func firebaseCredential(
        from appleCredential: OpenLARPAppleAuthorizationCredential
    ) throws -> AuthCredential {
        guard let identityToken = appleCredential.identityToken else {
            throw OpenLARPAppleAuthorizationError.missingIdentityToken
        }

        return OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: appleCredential.rawNonce,
            fullName: appleCredential.fullName
        )
    }
    #endif

    #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
    private func signInToFirebase(
        with googleUser: GIDGoogleUser,
        operation: OpenLARPAuthenticationOperation,
        state: OpenLARPState
    ) async -> OpenLARPAuthenticationResult {
        guard let credential = firebaseCredential(from: googleUser) else {
            return setupResult(operation: operation, status: .providerSetupRequired, state: state)
        }

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

    private func firebaseCredential(from googleUser: GIDGoogleUser) -> AuthCredential? {
        guard let idToken = googleUser.idToken?.tokenString else {
            return nil
        }

        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleUser.accessToken.tokenString
        )
    }
    #endif
}

enum OpenLARPAppleSignInCrypto {
    enum NonceGenerationError: Error {
        case invalidLength
        case generationFailed(OSStatus)
        case securityUnavailable
    }

    static let nonceCharacterSet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func randomNonceString(length: Int = 32) throws -> String {
        guard length > 0 else {
            throw NonceGenerationError.invalidLength
        }

        #if canImport(Security)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard status == errSecSuccess else {
            throw NonceGenerationError.generationFailed(status)
        }

        return nonceString(from: randomBytes)
        #else
        throw NonceGenerationError.securityUnavailable
        #endif
    }

    static func nonceString(from randomBytes: [UInt8]) -> String {
        String(randomBytes.map { byte in
            nonceCharacterSet[Int(byte) % nonceCharacterSet.count]
        })
    }

    static func sha256(_ input: String) -> String? {
        #if canImport(CryptoKit)
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map {
            String(format: "%02x", $0)
        }.joined()
        #else
        return nil
        #endif
    }
}

enum OpenLARPAppleAuthorizationError: Error {
    case cancelled
    case nonceUnavailable
    case missingCredential
    case missingIdentityToken
    case missingAuthorizationCode
}

#if canImport(AuthenticationServices) && canImport(UIKit)
struct OpenLARPAppleAuthorizationCredential {
    var rawNonce: String
    var identityToken: String?
    var authorizationCode: String?
    var fullName: PersonNameComponents?
}

@MainActor
private final class OpenLARPAppleAuthorizationCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<OpenLARPAppleAuthorizationCredential, Error>?
    private var rawNonce: String?
    private var presentationAnchor: ASPresentationAnchor?
    private var authorizationController: ASAuthorizationController?

    func requestCredential(
        rawNonce: String,
        nonce: String,
        requestedScopes: [ASAuthorization.Scope],
        presentationAnchor: ASPresentationAnchor
    ) async throws -> OpenLARPAppleAuthorizationCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.rawNonce = rawNonce
            self.presentationAnchor = presentationAnchor

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = requestedScopes
            request.nonce = nonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            authorizationController = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchor ?? ASPresentationAnchor()
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            finish(with: authorization)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            finish(with: error)
        }
    }

    private func finish(with authorization: ASAuthorization) {
        defer { clear() }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let rawNonce
        else {
            continuation?.resume(throwing: OpenLARPAppleAuthorizationError.missingCredential)
            return
        }

        let identityToken = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        continuation?.resume(
            returning: OpenLARPAppleAuthorizationCredential(
                rawNonce: rawNonce,
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: credential.fullName
            )
        )
    }

    private func finish(with error: Error) {
        defer { clear() }

        let error = error as NSError
        if error.domain == ASAuthorizationError.errorDomain,
           error.code == ASAuthorizationError.canceled.rawValue
        {
            continuation?.resume(throwing: OpenLARPAppleAuthorizationError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
    }

    private func clear() {
        continuation = nil
        rawNonce = nil
        presentationAnchor = nil
        authorizationController = nil
    }
}
#endif
