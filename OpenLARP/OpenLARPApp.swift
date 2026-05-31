import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store = OpenLARPStore()

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
