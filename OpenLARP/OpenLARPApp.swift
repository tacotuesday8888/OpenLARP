import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPENLARP_UI_TEST_RESET_LOCAL_DATA"] == "1" {
            do {
                _ = try OpenLARPLocalDataStore.live.eraseAllOnDeviceData()
            } catch {
                assertionFailure("UI test local-data reset failed: \(error)")
            }
        }
        #endif
        let releaseConfiguration = OpenLARPReleaseConfiguration.current()
        _store = State(
            initialValue: OpenLARPAppStoreFactory(
                localDataStore: .live
            ).makeStore(for: releaseConfiguration)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
