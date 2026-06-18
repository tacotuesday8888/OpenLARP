import XCTest
@testable import OpenLARP

final class AppCheckReadinessTests: XCTestCase {
    func testAppCheckProviderModeStaysUnavailableWhenSDKIsNotLinked() {
        XCTAssertEqual(
            OpenLARPFirebaseBootstrap.appCheckProviderMode(
                canUseFirebaseAppCheck: false,
                isSimulator: true,
                isDebugProviderEnabled: true
            ),
            .unavailable
        )
        XCTAssertEqual(
            OpenLARPFirebaseBootstrap.appCheckProviderMode(
                canUseFirebaseAppCheck: false,
                isSimulator: false,
                isDebugProviderEnabled: false
            ),
            .unavailable
        )
    }

    func testAppCheckUsesDebugProviderOnlyWhenExplicitlyEnabledForSimulatorBuilds() {
        XCTAssertEqual(
            OpenLARPFirebaseBootstrap.appCheckProviderMode(
                canUseFirebaseAppCheck: true,
                isSimulator: true,
                isDebugProviderEnabled: true
            ),
            .debug
        )
        XCTAssertEqual(
            OpenLARPFirebaseBootstrap.appCheckProviderMode(
                canUseFirebaseAppCheck: true,
                isSimulator: true,
                isDebugProviderEnabled: false
            ),
            .unavailable
        )
        XCTAssertEqual(
            OpenLARPFirebaseBootstrap.appCheckProviderMode(
                canUseFirebaseAppCheck: true,
                isSimulator: false,
                isDebugProviderEnabled: false
            ),
            .appAttest
        )
    }

    func testCurrentBuildAppCheckProviderModeMatchesCompilationEnvironment() {
        #if canImport(FirebaseAppCheck)
        #if targetEnvironment(simulator)
        XCTAssertEqual(OpenLARPFirebaseBootstrap.currentAppCheckProviderMode, .unavailable)
        #else
        XCTAssertEqual(OpenLARPFirebaseBootstrap.currentAppCheckProviderMode, .appAttest)
        #endif
        #else
        XCTAssertEqual(OpenLARPFirebaseBootstrap.currentAppCheckProviderMode, .unavailable)
        #endif
    }
}
