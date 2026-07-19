import Foundation

public struct OpenLARPReleaseContractSnapshot: Equatable, Sendable {
    public let bundleIdentifier: String
    public let bundledReleaseChannel: String
    public let channel: String
    public let accessMode: String
    public let serviceMode: String
    public let enabledCapabilities: [String]
    public let liveAIEnabled: Bool
    public let visibleTabs: [String]
    public let todaySections: [String]
    public let profileSections: [String]
    public let profilePrivacyPresentation: String
    public let activationOperations: [String]
    public let tabChangeOperations: [String]

    public static func current() -> OpenLARPReleaseContractSnapshot {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        let configuration = OpenLARPReleaseConfiguration.current(
            infoDictionary: infoDictionary
        )

        return OpenLARPReleaseContractSnapshot(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            bundledReleaseChannel: infoDictionary[
                OpenLARPReleaseConfiguration.infoDictionaryKey
            ] as? String ?? "",
            channel: configuration.channel.rawValue,
            accessMode: configuration.accessMode.releaseContractName,
            serviceMode: configuration.serviceMode.releaseContractName,
            enabledCapabilities: configuration.enabledCapabilities
                .map(\.rawValue)
                .sorted(),
            liveAIEnabled: configuration.isEnabled(.liveAI),
            visibleTabs: AppTab.visibleTabs(for: configuration).map(\.rawValue),
            todaySections: TodaySection.visibleSections(for: configuration).map(\.rawValue),
            profileSections: ProfileSection.visibleSections(for: configuration).map(\.rawValue),
            profilePrivacyPresentation: ProfilePrivacyPresentation.mode(
                for: configuration
            ).rawValue,
            activationOperations: AppLifecyclePolicy.activationOperations(
                for: configuration
            ).map(\.releaseContractName),
            tabChangeOperations: AppLifecyclePolicy.tabChangeOperations(
                for: configuration
            ).map(\.releaseContractName)
        )
    }
}

private extension OpenLARPReleaseAccessMode {
    var releaseContractName: String {
        switch self {
        case .free: "free"
        case .subscription: "subscription"
        }
    }
}

private extension OpenLARPReleaseServiceMode {
    var releaseContractName: String {
        switch self {
        case .localOnly: "local-only"
        case .firebaseBeta: "firebase-beta"
        }
    }
}

private extension AppLifecycleOperation {
    var releaseContractName: String {
        switch self {
        case .refreshDailyAvailability: "refreshDailyAvailability"
        case .restoreAuthentication: "restoreAuthentication"
        case .refreshSubscription: "refreshSubscription"
        case .syncBackendEvents: "syncBackendEvents"
        }
    }
}
