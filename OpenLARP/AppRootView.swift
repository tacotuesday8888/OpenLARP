import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case map
    case chat
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .map: "Map"
        case .chat: "Chat"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "target"
        case .map: "map"
        case .chat: "sparkles"
        case .profile: "person.crop.circle"
        }
    }
}

struct AppRootView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tabContent(for: tab)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
        .tint(.openLARPGreen)
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayView(snapshot: .sample)
        case .map:
            QuestMapView(quests: QuestDay.sampleWeek)
        case .chat:
            AgentChatView(prompts: AgentPrompt.samplePrompts)
        case .profile:
            ProfileView(profile: .sample)
        }
    }
}
