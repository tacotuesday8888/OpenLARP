import Foundation

enum OpenLARPReleaseChannel: String, Equatable, Sendable {
    case appStore = "app-store"
    case internalBeta = "internal-beta"
}

enum OpenLARPReleaseAccessMode: Equatable, Sendable {
    case free
    case subscription
}

enum OpenLARPReleaseCapability: String, CaseIterable, Hashable, Sendable {
    case agent
    case account
    case cloudSync
    case subscriptions
    case developerTools
    case liveAI
}

struct OpenLARPReleaseConfiguration: Equatable, Sendable {
    static let infoDictionaryKey = "OpenLARPReleaseChannel"

    let channel: OpenLARPReleaseChannel
    let accessMode: OpenLARPReleaseAccessMode
    let enabledCapabilities: Set<OpenLARPReleaseCapability>

    static let appStoreMVP = OpenLARPReleaseConfiguration(
        channel: .appStore,
        accessMode: .free,
        enabledCapabilities: []
    )

    static let internalBeta = OpenLARPReleaseConfiguration(
        channel: .internalBeta,
        accessMode: .subscription,
        enabledCapabilities: [
            .agent,
            .account,
            .cloudSync,
            .subscriptions,
            .developerTools
        ]
    )

    static func current(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> OpenLARPReleaseConfiguration {
        guard let rawChannel = infoDictionary[infoDictionaryKey] as? String,
              let channel = OpenLARPReleaseChannel(rawValue: rawChannel) else {
            return .appStoreMVP
        }

        switch channel {
        case .appStore:
            return .appStoreMVP
        case .internalBeta:
            return .internalBeta
        }
    }

    func isEnabled(_ capability: OpenLARPReleaseCapability) -> Bool {
        enabledCapabilities.contains(capability)
    }

    var runsAuthenticationLifecycle: Bool { isEnabled(.account) }
    var runsSubscriptionLifecycle: Bool { isEnabled(.subscriptions) }
    var runsBackendEventSync: Bool { isEnabled(.cloudSync) }
}
