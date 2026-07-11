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
        allCases.filter { tab in
            tab != .agent || configuration.isEnabled(.agent)
        }
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
        allCases.filter { section in
            switch section {
            case .subscriptionAccess:
                configuration.isEnabled(.subscriptions)
            case .agentBrief, .agentAction:
                configuration.isEnabled(.agent)
            case .header, .quest, .diagnostic, .progress, .outcome:
                true
            }
        }
    }
}

enum ProfileSection: String, CaseIterable, Identifiable, Sendable {
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
        allCases.filter { section in
            switch section {
            case .accountProfile, .accountDataControls:
                configuration.isEnabled(.account)
            case .subscriptionStatus:
                configuration.isEnabled(.subscriptions)
            case .careerGraphStatus:
                configuration.isEnabled(.cloudSync)
            case .betaMeasurement:
                configuration.isEnabled(.developerTools)
            case .careerSummary,
                 .activeGoal,
                 .recentOutcomes,
                 .streak,
                 .privacy,
                 .badges,
                 .proof,
                 .rules:
                true
            }
        }
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
