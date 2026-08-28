import SwiftUI

@main
struct OpenLARPApp: App {
    @State private var store: OpenLARPStore
    #if DEBUG
    private let uiTestDynamicTypeSize: DynamicTypeSize?
    #endif

    init() {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
        uiTestDynamicTypeSize = Self.dynamicTypeSizeOverride(environment: environment)
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

    #if DEBUG
    private static func dynamicTypeSizeOverride(
        environment: [String: String]
    ) -> DynamicTypeSize? {
        switch environment["OPENLARP_UI_TEST_DYNAMIC_TYPE_SIZE"] {
        case "accessibility5": .accessibility5
        default: nil
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let uiTestDynamicTypeSize {
                AppRootView(store: store)
                    .dynamicTypeSize(uiTestDynamicTypeSize)
            } else {
                AppRootView(store: store)
            }
            #else
            AppRootView(store: store)
            #endif
        }
    }
}
