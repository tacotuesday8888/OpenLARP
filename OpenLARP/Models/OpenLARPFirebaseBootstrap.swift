import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum OpenLARPFirebaseBootstrap {
    enum Status: Equatable {
        case configured
        case missingSDK
        case missingConfiguration
    }

    enum AppCheckProviderMode: String, Equatable {
        case appAttest
        case debug
        case unavailable
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

        configureAppCheckIfAvailable()
        FirebaseApp.configure()
        return .configured
        #else
        return .missingSDK
        #endif
    }

    static func appCheckProviderMode(
        canUseFirebaseAppCheck: Bool,
        isSimulator: Bool,
        isDebugProviderEnabled: Bool
    ) -> AppCheckProviderMode {
        guard canUseFirebaseAppCheck else {
            return .unavailable
        }

        if isSimulator {
            return isDebugProviderEnabled ? .debug : .unavailable
        }

        return .appAttest
    }

    static var currentAppCheckProviderMode: AppCheckProviderMode {
        #if canImport(FirebaseAppCheck)
        #if targetEnvironment(simulator)
        return appCheckProviderMode(
            canUseFirebaseAppCheck: true,
            isSimulator: true,
            isDebugProviderEnabled: isAppCheckDebugProviderRequested
        )
        #else
        return appCheckProviderMode(
            canUseFirebaseAppCheck: true,
            isSimulator: false,
            isDebugProviderEnabled: false
        )
        #endif
        #else
        return appCheckProviderMode(
            canUseFirebaseAppCheck: false,
            isSimulator: false,
            isDebugProviderEnabled: false
        )
        #endif
    }

    private static func configureAppCheckIfAvailable() {
        #if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
        switch currentAppCheckProviderMode {
        case .appAttest:
            AppCheck.setAppCheckProviderFactory(OpenLARPAppAttestProviderFactory())
        case .debug:
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        case .unavailable:
            AppCheck.setAppCheckProviderFactory(OpenLARPNoAppCheckProviderFactory())
        }
        #endif
    }

    private static var isAppCheckDebugProviderRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["OPENLARP_ENABLE_FIREBASE_APP_CHECK_DEBUG"] == "1"
            || environment["AppCheckDebugToken"]?.isEmpty == false
            || environment["FIRAAppCheckDebugToken"]?.isEmpty == false
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
private final class OpenLARPAppAttestProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

private final class OpenLARPNoAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        nil
    }
}
#endif
