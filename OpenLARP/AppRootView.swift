import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
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

enum AppLifecycleOperation: Equatable, Sendable {
    case refreshDailyAvailability
    case restoreAuthentication
    case refreshSubscription
    case syncBackendEvents
}

struct AppLifecyclePolicy {
    static func activationOperations(
        for configuration: OpenLARPReleaseConfiguration
    ) -> [AppLifecycleOperation] {
        var operations: [AppLifecycleOperation] = [.refreshDailyAvailability]
        if configuration.runsAuthenticationLifecycle {
            operations.append(.restoreAuthentication)
        }
        if configuration.runsSubscriptionLifecycle {
            operations.append(.refreshSubscription)
        }
        if configuration.runsBackendEventSync {
            operations.append(.syncBackendEvents)
        }
        return operations
    }

    static func tabChangeOperations(
        for configuration: OpenLARPReleaseConfiguration
    ) -> [AppLifecycleOperation] {
        var operations: [AppLifecycleOperation] = [.refreshDailyAvailability]
        if configuration.runsBackendEventSync {
            operations.append(.syncBackendEvents)
        }
        return operations
    }
}

struct AppRootView: View {
    let store: OpenLARPStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(store: store)
            }
            .tabItem {
                Label(AppTab.today.title, systemImage: AppTab.today.systemImage)
            }
            .tag(AppTab.today)

            NavigationStack {
                QuestMapView(
                    state: store.state,
                    attachmentURL: { attachment in
                        store.localURL(for: attachment)
                    },
                    viewToday: {
                        selectedTab = .today
                    }
                )
            }
            .tabItem {
                Label(AppTab.map.title, systemImage: AppTab.map.systemImage)
            }
            .tag(AppTab.map)

            NavigationStack {
                ProgressTabView(
                    state: store.state,
                    attachmentURL: { attachment in
                        store.localURL(for: attachment)
                    },
                    improveWeakestArea: {
                        selectedTab = .today
                    },
                    logOutcome: { kind, title, organizationName, note, occurredAt, isPrivate in
                        store.logOutcome(
                            kind: kind,
                            title: title,
                            organizationName: organizationName,
                            note: note,
                            occurredAt: occurredAt,
                            isPrivate: isPrivate
                        )
                    },
                    updateOutcome: { id, kind, title, organizationName, note, occurredAt, isPrivate in
                        store.updateOutcome(
                            id: id,
                            kind: kind,
                            title: title,
                            organizationName: organizationName,
                            note: note,
                            occurredAt: occurredAt,
                            isPrivate: isPrivate
                        )
                    },
                    deleteOutcome: { id in
                        store.deleteOutcome(id: id)
                    }
                )
            }
            .tabItem {
                Label(AppTab.progress.title, systemImage: AppTab.progress.systemImage)
            }
            .tag(AppTab.progress)

            if store.releaseConfiguration.isEnabled(.agent) {
                NavigationStack {
                    AgentDashboardView(store: store)
                }
                .tabItem {
                    Label(AppTab.agent.title, systemImage: AppTab.agent.systemImage)
                }
                .tag(AppTab.agent)
            }

            NavigationStack {
                ProfileView(store: store)
            }
            .tabItem {
                Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage)
            }
            .tag(AppTab.profile)
        }
        .tint(.openLARPBlue)
        .onAppear {
            refreshForActiveState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshForActiveState()
        }
        .onChange(of: selectedTab) {
            performLifecycleOperations(
                AppLifecyclePolicy.tabChangeOperations(
                    for: store.releaseConfiguration
                )
            )
        }
        .onOpenURL { url in
            guard store.releaseConfiguration.serviceMode != .localOnly,
                  store.releaseConfiguration.isEnabled(.account) else {
                return
            }
            _ = store.handleOpenURL(url)
        }
    }

    private func refreshForActiveState() {
        performLifecycleOperations(
            AppLifecyclePolicy.activationOperations(
                for: store.releaseConfiguration
            )
        )
    }

    private func performLifecycleOperations(
        _ operations: [AppLifecycleOperation]
    ) {
        var serviceOperations: [AppLifecycleOperation] = []
        for operation in operations {
            if operation == .refreshDailyAvailability {
                store.refreshDailyAvailability()
            } else {
                serviceOperations.append(operation)
            }
        }

        guard !serviceOperations.isEmpty else { return }

        Task {
            for operation in serviceOperations {
                switch operation {
                case .refreshDailyAvailability:
                    break
                case .restoreAuthentication:
                    await store.restorePreviousAuthenticationSession()
                case .refreshSubscription:
                    await store.refreshSubscriptionStatus()
                case .syncBackendEvents:
                    await store.syncBackendEvents()
                }
            }
        }
    }
}
