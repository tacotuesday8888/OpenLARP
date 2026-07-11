import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore

    init() {
        let releaseConfiguration = OpenLARPReleaseConfiguration.current()
        _store = State(
            initialValue: OpenLARPAppStoreFactory().makeStore(for: releaseConfiguration)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
