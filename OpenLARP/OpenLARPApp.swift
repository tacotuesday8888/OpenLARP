import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        if environment["OPENLARP_UI_TEST_RESET_LOCAL_DATA"] == "1" {
            do {
                _ = try OpenLARPLocalDataStore.live.eraseAllOnDeviceData()
            } catch {
                assertionFailure("UI test local-data reset failed: \(error)")
            }
        }
        #endif
        let now = Self.nowProvider(environment: environment)
        let releaseConfiguration = OpenLARPReleaseConfiguration.current()
        _store = State(
            initialValue: OpenLARPAppStoreFactory(
                localDataStore: .live,
                now: now
            ).makeStore(for: releaseConfiguration)
        )
    }

    private static func nowProvider(environment: [String: String]) -> () -> Date {
        #if DEBUG
        if let rawTimestamp = environment["OPENLARP_UI_TEST_NOW"],
           let timestamp = TimeInterval(rawTimestamp) {
            let fixedDate = Date(timeIntervalSince1970: timestamp)
            return { fixedDate }
        }
        #endif
        return { Date() }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
