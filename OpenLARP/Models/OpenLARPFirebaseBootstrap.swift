import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum OpenLARPFirebaseBootstrap {
    enum Status: Equatable {
        case configured
        case missingSDK
        case missingConfiguration
    }

    @discardableResult
    static func configureIfAvailable() -> Status {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() != nil {
            return .configured
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return .missingConfiguration
        }

        FirebaseApp.configure()
        return .configured
        #else
        return .missingSDK
        #endif
    }
}
