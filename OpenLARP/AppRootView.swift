import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case map
    case progress
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .map: "Map"
        case .progress: "Progress"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "bolt.fill"
        case .map: "map.fill"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}

struct AppRootView: View {
    let store: OpenLARPStore

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
                    }
                )
            }
            .tabItem {
                Label(AppTab.progress.title, systemImage: AppTab.progress.systemImage)
            }
            .tag(AppTab.progress)

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
            store.refreshDailyAvailability()
        }
        .onChange(of: selectedTab) {
            store.refreshDailyAvailability()
        }
    }
}
