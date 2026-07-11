import Foundation

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case map
    case progress
    case agent
    case profile

    var id: String { rawValue }

    static func visibleTabs(
        for configuration: OpenLARPReleaseConfiguration
    ) -> [AppTab] {
        var tabs: [AppTab] = [.today, .map, .progress]
        if configuration.isEnabled(.agent) {
            tabs.append(.agent)
        }
        tabs.append(.profile)
        return tabs
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .map: "Map"
        case .progress: "Progress"
        case .agent: "Agent"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "bolt.fill"
        case .map: "map.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        case .agent: "sparkles"
        case .profile: "person.crop.circle"
        }
    }
}

enum TodaySection: String, CaseIterable, Identifiable, Sendable {
    case header
    case subscriptionAccess
    case quest
    case diagnostic
    case progress
    case agentBrief
    case agentAction
    case outcome

    var id: String { rawValue }

    static func visibleSections(
        for configuration: OpenLARPReleaseConfiguration
    ) -> [TodaySection] {
        var sections: [TodaySection] = [.header]
        if configuration.isEnabled(.subscriptions) {
            sections.append(.subscriptionAccess)
        }
        sections.append(contentsOf: [.quest, .diagnostic, .progress])
        if configuration.isEnabled(.agent) {
            sections.append(contentsOf: [.agentBrief, .agentAction])
        }
        sections.append(.outcome)
        return sections
    }
}

enum ProfileSection: String, CaseIterable, Identifiable, Sendable {
    case hero
    case careerSummary
    case accountProfile
    case accountDataControls
    case subscriptionStatus
    case careerGraphStatus
    case betaMeasurement
    case activeGoal
    case recentOutcomes
    case streak
    case privacy
    case badges
    case proof
    case rules

    var id: String { rawValue }

    static func visibleSections(
        for configuration: OpenLARPReleaseConfiguration
    ) -> [ProfileSection] {
        var sections: [ProfileSection] = [.hero, .careerSummary]
        if configuration.isEnabled(.account) {
            sections.append(contentsOf: [.accountProfile, .accountDataControls])
        }
        if configuration.isEnabled(.subscriptions) {
            sections.append(.subscriptionStatus)
        }
        if configuration.isEnabled(.cloudSync) {
            sections.append(.careerGraphStatus)
        }
        if configuration.isEnabled(.developerTools) {
            sections.append(.betaMeasurement)
        }
        sections.append(contentsOf: [
            .activeGoal,
            .recentOutcomes,
            .streak,
            .privacy,
            .badges,
            .proof,
            .rules
        ])
        return sections
    }
}

enum ProfilePrivacyPresentation: String, Equatable, Sendable {
    case localOnlyNotice
    case cloudControls

    static func mode(
        for configuration: OpenLARPReleaseConfiguration
    ) -> ProfilePrivacyPresentation {
        configuration.isEnabled(.cloudSync) ? .cloudControls : .localOnlyNotice
    }
}
