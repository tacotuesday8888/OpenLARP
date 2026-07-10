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
            store.refreshDailyAvailability()
            guard store.releaseConfiguration.runsBackendEventSync else { return }
            Task { await store.syncBackendEvents() }
        }
        .onOpenURL { url in
            _ = store.handleOpenURL(url)
        }
    }

    private func refreshForActiveState() {
        store.refreshDailyAvailability()
        let configuration = store.releaseConfiguration

        Task {
            if configuration.runsAuthenticationLifecycle {
                await store.restorePreviousAuthenticationSession()
            }
            if configuration.runsSubscriptionLifecycle {
                await store.refreshSubscriptionStatus()
            }
            if configuration.runsBackendEventSync {
                await store.syncBackendEvents()
            }
        }
    }
}
