import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        OpenLARPFirebaseBootstrap.configureIfAvailable()
        let attachmentStore = OpenLARPAttachmentStore.live
        let authenticationService = FirebaseGoogleSignInAuthenticationService()
        _store = State(
            initialValue: OpenLARPStore(
                attachmentStore: attachmentStore,
                careerGraphSyncService: FirebaseReadyCareerGraphSyncService(
                    firebaseService: FirebaseFirestoreCareerGraphSyncService(
                        attachmentDataProvider: attachmentStore
                    )
                ),
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
