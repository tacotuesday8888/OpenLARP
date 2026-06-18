import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        OpenLARPFirebaseBootstrap.configureIfAvailable()
        _store = State(
            initialValue: OpenLARPStore(
                backendEventSyncService: FirebaseReadyBackendEventSyncService(),
                backendSessionProvider: FirebaseBackendSessionProvider()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
