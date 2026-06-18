import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store = OpenLARPStore()

    init() {
        OpenLARPFirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
