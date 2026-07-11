import SwiftUI

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
            ForEach(AppTab.visibleTabs(for: store.releaseConfiguration)) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
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

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            NavigationStack {
                TodayView(store: store)
            }
        case .map:
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
        case .progress:
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
        case .agent:
            NavigationStack {
                AgentDashboardView(store: store)
            }
        case .profile:
            NavigationStack {
                ProfileView(store: store)
            }
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
