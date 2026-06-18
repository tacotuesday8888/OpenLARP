import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        OpenLARPFirebaseBootstrap.configureIfAvailable()
        let authenticationService = FirebaseGoogleSignInAuthenticationService()
        _store = State(
            initialValue: OpenLARPStore(
                authenticationService: authenticationService,
                backendEventSyncService: FirebaseReadyBackendEventSyncService()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
