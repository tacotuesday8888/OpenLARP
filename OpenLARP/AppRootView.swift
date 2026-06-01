import PhotosUI
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case path
    case quest
    case cooked
    case proof
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .path: "Path"
        case .quest: "Quest"
        case .cooked: "Cooked"
        case .proof: "Proof"
        case .stats: "Stats"
        }
    }

    var systemImage: String {
        switch self {
        case .path: "map.fill"
        case .quest: "bolt.fill"
        case .cooked: "flame.fill"
        case .proof: "doc.fill"
        case .stats: "chart.bar.fill"
        }
    }

    var accent: Color {
        switch self {
        case .path: .openLARPBlue
        case .quest: .openLARPPurple
        case .cooked: .openLARPCoral
        case .proof: .openLARPGreen
        case .stats: .openLARPOrange
        }
    }

    var headerColors: [Color] {
        switch self {
        case .path:
            [.openLARPBlue, Color(red: 0.25, green: 0.40, blue: 1.00)]
        case .quest:
            [Color(red: 0.55, green: 0.49, blue: 1.00), Color(red: 0.39, green: 0.33, blue: 0.91)]
        case .cooked:
            [Color(red: 1.00, green: 0.50, blue: 0.67), .openLARPCoral]
        case .proof:
            [Color(red: 0.21, green: 0.86, blue: 0.63), Color(red: 0.09, green: 0.72, blue: 0.44)]
        case .stats:
            [Color(red: 1.00, green: 0.75, blue: 0.30), .openLARPOrange]
        }
    }
}

enum OpenLARPDesignCatalog {
    static let screenTitles = [
        "Set your goal",
        "The roast report",
        "Proof Sprint",
        "Public proof",
        "Add evidence",
        "Review result",
        "Comeback Map",
        "Less cooked",
        "Evidence bank",
        "Not over",
        "Career Hub",
        "Settings"
    ]
}

private enum FeatureMarkKind {
    case path
    case quest
    case cooked
    case proof
    case stats
    case recovery
    case me
    case settings

    var icon: String {
        switch self {
        case .path: "map.fill"
        case .quest: "bolt.fill"
        case .cooked: "flame.fill"
        case .proof: "doc.fill"
        case .stats: "chart.bar.fill"
        case .recovery: "shield.fill"
        case .me: "briefcase.fill"
        case .settings: "gearshape.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .path:
            [Color.openLARPCyan, Color.openLARPBlue]
        case .quest:
            [Color(red: 0.61, green: 0.55, blue: 1.00), Color.openLARPPurple]
        case .cooked:
            [Color(red: 1.00, green: 0.56, blue: 0.71), Color.openLARPCoral]
        case .proof:
            [Color.openLARPMint, Color.openLARPGreen]
        case .stats:
            [Color.openLARPYellow, Color.openLARPOrange]
        case .recovery:
            [Color(red: 0.55, green: 0.63, blue: 0.72), Color(red: 0.15, green: 0.23, blue: 0.35)]
        case .me, .settings:
            [Color(red: 0.37, green: 0.46, blue: 0.59), Color(red: 0.08, green: 0.15, blue: 0.24)]
        }
    }

    var shadow: Color {
        switch self {
        case .path: Color.openLARPBlueDark
        case .quest: Color(red: 0.32, green: 0.26, blue: 0.79)
        case .cooked: Color(red: 0.72, green: 0.13, blue: 0.28)
        case .proof: Color(red: 0.05, green: 0.53, blue: 0.31)
        case .stats: Color(red: 0.71, green: 0.33, blue: 0.09)
        case .recovery: Color(red: 0.08, green: 0.15, blue: 0.24)
        case .me, .settings: Color(red: 0.04, green: 0.06, blue: 0.12)
        }
    }
}

private extension AppTab {
    var featureMarkKind: FeatureMarkKind {
        switch self {
        case .path: .path
        case .quest: .quest
        case .cooked: .cooked
        case .proof: .proof
        case .stats: .stats
        }
    }
}

private enum PathMode {
    case sprint
    case sevenDay
}

private enum ProofMode {
    case add
    case review
    case bank
}

private enum SecondaryScreen {
    case recovery
    case careerHub
    case settings
}

struct AppRootView: View {
    let store: OpenLARPStore

    @State private var selectedTab: AppTab = .path
    @State private var pathMode: PathMode = .sprint
    @State private var proofMode: ProofMode = .add
    @State private var secondaryScreen: SecondaryScreen?
    @State private var toastMessage: String?
    @State private var memoryEnabled = true
    @State private var notificationsEnabled = true

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.state.needsGoalSetup {
                GoalSetupDesignScreen(store: store) {
                    selectedTab = .cooked
                    secondaryScreen = nil
                    showToast("Cooked check built around this goal.")
                }
            } else if let secondaryScreen {
                secondaryContent(for: secondaryScreen)
            } else {
                mainContent
            }

            toastView
        }
        .background(Color.openLARPPanel)
        .onAppear {
            store.refreshDailyAvailability()
        }
        .onChange(of: selectedTab) {
            store.refreshDailyAvailability()
        }
        .alert(
            "OpenLARP",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var mainContent: some View {
        Group {
            if selectedTab == .path {
                VStack(spacing: 0) {
                    selectedScreen

                    MainTabBar(selectedTab: $selectedTab, onSelect: selectMainTab)
                }
                .background(Color.openLARPPanel)
                .ignoresSafeArea(edges: .top)
            } else {
                DesignShell(
                    tab: selectedTab,
                    titleSmall: titleSmall,
                    titleMain: titleMain,
                    stat: headerStat,
                    statAction: statAction,
                    selectedTab: $selectedTab,
                    onSelectTab: selectMainTab
                ) {
                    selectedScreen
                }
            }
        }
    }

    private func selectMainTab(_ tab: AppTab) {
        if tab == .proof {
            proofMode = .add
        }
        secondaryScreen = nil
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch selectedTab {
        case .path:
            if pathMode == .sprint {
                SprintPathScreen(
                    state: store.state,
                    showSevenDayMap: { pathMode = .sevenDay },
                    openRecovery: { secondaryScreen = .recovery },
                    showToast: showToast
                )
            } else {
                SevenDayMapScreen(
                    state: store.state,
                    showSprintPath: { pathMode = .sprint },
                    viewToday: { selectedTab = .quest },
                    openRecovery: { secondaryScreen = .recovery },
                    showToast: showToast
                )
            }
        case .quest:
            TodayQuestDesignScreen(
                addProof: {
                    if let quest = store.state.currentQuest, quest.status != .inProgress {
                        store.startCurrentQuest()
                    }
                    proofMode = .add
                    selectedTab = .proof
                },
                swapQuest: {
                    store.swapCurrentQuest()
                    showToast("Quest swapped to a smaller proof artifact.")
                }
            )
        case .cooked:
            CookedDiagnosticDesignScreen(
                state: store.state,
                startFix: {
                    store.startCurrentQuest()
                    selectedTab = .quest
                    showToast("Progress updated. You are slightly less cooked.")
                },
                shareCard: {
                    showToast("Share card preview would hide private details by default.")
                }
            )
        case .proof:
            proofContent
        case .stats:
            StatsDesignScreen(state: store.state)
        }
    }

    @ViewBuilder
    private var proofContent: some View {
        switch proofMode {
        case .add:
            AddProofDesignScreen(
                store: store,
                openReview: {
                    proofMode = .review
                },
                showToast: showToast
            )
        case .review:
            ProofReviewDesignScreen(
                result: store.pendingQualityResult,
                claimXP: {
                    if store.pendingQualityResult != nil {
                        store.claimPendingQualityResult()
                        selectedTab = .stats
                        showToast("XP claimed. Readiness moved up.")
                    } else {
                        showToast("Check proof first, then claim XP.")
                    }
                },
                improveProof: {
                    store.discardPendingQualityResult()
                    proofMode = .add
                    showToast("Proof sheet reopened.")
                }
            )
        case .bank:
            EvidenceBankDesignScreen(
                state: store.state,
                addProof: {
                    proofMode = .add
                },
                improveWeakest: {
                    selectedTab = .quest
                    showToast("Today quest is the cleanest way to improve proof.")
                }
            )
        }
    }

    @ViewBuilder
    private func secondaryContent(for screen: SecondaryScreen) -> some View {
        switch screen {
        case .recovery:
            SecondaryDesignShell(
                titleSmall: "Recovery",
                titleMain: "Not over",
                stat: "1 freeze",
                mark: .recovery,
                selectedTab: $selectedTab,
                closeToMain: { secondaryScreen = nil }
            ) {
                RecoveryDesignScreen(
                    saveStreak: {
                        store.startCurrentQuest()
                        secondaryScreen = nil
                        selectedTab = .quest
                        showToast("Recovery quest started.")
                    },
                    useFreeze: {
                        showToast("Streak freeze saved for the next missed day.")
                    }
                )
            }
        case .careerHub:
            SecondaryDesignShell(
                titleSmall: "Me",
                titleMain: "Career Hub",
                stat: "L3",
                mark: .me,
                selectedTab: $selectedTab,
                closeToMain: { secondaryScreen = nil }
            ) {
                CareerHubDesignScreen(
                    state: store.state,
                    editGoal: {
                        store.resetGoal()
                        secondaryScreen = nil
                        showToast("Goal controls opened.")
                    },
                    exportData: {
                        showToast("Export is local-only for now.")
                    },
                    openSettings: {
                        secondaryScreen = .settings
                    }
                )
            }
        case .settings:
            SecondaryDesignShell(
                titleSmall: "Me",
                titleMain: "Settings",
                stat: "Account",
                mark: .settings,
                selectedTab: $selectedTab,
                closeToMain: { secondaryScreen = nil }
            ) {
                SettingsDesignScreen(
                    notificationsEnabled: $notificationsEnabled,
                    memoryEnabled: $memoryEnabled,
                    showToast: showToast
                )
            }
        }
    }

    private var titleSmall: String {
        switch selectedTab {
        case .path: pathMode == .sprint ? "Path" : "Week"
        case .quest: "Quest"
        case .cooked: "Am I Cooked?"
        case .proof: "Proof"
        case .stats: "Stats"
        }
    }

    private var titleMain: String {
        switch selectedTab {
        case .path: pathMode == .sprint ? "Proof Sprint" : "Comeback Map"
        case .quest: "Public proof"
        case .cooked: "The roast report"
        case .proof:
            switch proofMode {
            case .add: "Add evidence"
            case .review: "Review result"
            case .bank: "Evidence bank"
            }
        case .stats: "Less cooked"
        }
    }

    private var headerStat: String {
        switch selectedTab {
        case .path: pathMode == .sprint ? "580 XP" : "56 goal"
        case .quest: "+35"
        case .cooked: "64%"
        case .proof:
            switch proofMode {
            case .add: "3 items"
            case .review: "+35"
            case .bank: "\(max(8, store.state.progress.proofCount))"
            }
        case .stats: "+7%"
        }
    }

    private var statAction: (() -> Void)? {
        switch selectedTab {
        case .path:
            { secondaryScreen = .recovery }
        case .proof:
            proofMode == .review ? nil : {
                proofMode = proofMode == .bank ? .add : .bank
            }
        case .stats:
            { secondaryScreen = .careerHub }
        default:
            nil
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toastMessage {
            Text(toastMessage)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color(red: 0.03, green: 0.07, blue: 0.15).opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.55), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 12)
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard toastMessage == message else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                toastMessage = nil
            }
        }
    }
}

private struct DesignShell<Content: View>: View {
    let tab: AppTab
    let titleSmall: String
    let titleMain: String
    let stat: String
    let statAction: (() -> Void)?
    @Binding var selectedTab: AppTab
    let onSelectTab: (AppTab) -> Void
    let content: Content

    init(
        tab: AppTab,
        titleSmall: String,
        titleMain: String,
        stat: String,
        statAction: (() -> Void)? = nil,
        selectedTab: Binding<AppTab>,
        onSelectTab: @escaping (AppTab) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.tab = tab
        self.titleSmall = titleSmall
        self.titleMain = titleMain
        self.stat = stat
        self.statAction = statAction
        _selectedTab = selectedTab
        self.onSelectTab = onSelectTab
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                colors: tab.headerColors,
                mark: tab.featureMarkKind,
                titleSmall: titleSmall,
                titleMain: titleMain,
                stat: stat,
                statAction: statAction
            )

            content

            MainTabBar(selectedTab: $selectedTab, onSelect: onSelectTab)
        }
        .background(Color.openLARPPanel)
        .ignoresSafeArea(edges: .top)
    }
}

private struct SecondaryDesignShell<Content: View>: View {
    let titleSmall: String
    let titleMain: String
    let stat: String
    let mark: FeatureMarkKind
    let colors: [Color]
    @Binding var selectedTab: AppTab
    let closeToMain: () -> Void
    let content: Content

    init(
        titleSmall: String,
        titleMain: String,
        stat: String,
        mark: FeatureMarkKind,
        colors: [Color] = [Color(red: 0.15, green: 0.25, blue: 0.39), Color(red: 0.08, green: 0.15, blue: 0.24)],
        selectedTab: Binding<AppTab>,
        closeToMain: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.titleSmall = titleSmall
        self.titleMain = titleMain
        self.stat = stat
        self.mark = mark
        self.colors = colors
        _selectedTab = selectedTab
        self.closeToMain = closeToMain
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                colors: colors,
                mark: mark,
                titleSmall: titleSmall,
                titleMain: titleMain,
                stat: stat
            )

            content

            SecondaryTabBar(selectedTab: $selectedTab, closeToMain: closeToMain)
        }
        .background(Color.openLARPPanel)
        .ignoresSafeArea(edges: .top)
    }
}

private struct TopBar: View {
    let colors: [Color]
    let mark: FeatureMarkKind
    let titleSmall: String
    let titleMain: String
    let stat: String
    var statAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            FeatureMarkView(kind: mark, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleSmall.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)

                Text(titleMain)
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 6)

            Group {
                if let statAction {
                    Button(action: statAction) {
                        statLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    statLabel
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 50)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var statLabel: some View {
        Text(stat)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: 45, minHeight: 29)
            .padding(.horizontal, 9)
            .background(.white.opacity(0.18))
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct MainTabBar: View {
    @Binding var selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    onSelect(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? .white : tab.accent)
                            .frame(width: 28, height: 25)
                            .background(selectedTab == tab ? tab.accent : Color(red: 0.93, green: 0.96, blue: 0.98))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(tab.title)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? tab.accent : Color(red: 0.54, green: 0.60, blue: 0.67))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 10)
        .background(.white.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0.89, green: 0.93, blue: 0.97))
                .frame(height: 2)
        }
    }
}

private struct SecondaryTabBar: View {
    @Binding var selectedTab: AppTab
    let closeToMain: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases.dropLast()) { tab in
                Button {
                    selectedTab = tab
                    closeToMain()
                } label: {
                    tabItem(title: tab.title, image: tab.systemImage, active: false, accent: tab.accent)
                }
                .buttonStyle(.plain)
            }

            tabItem(title: "Me", image: "briefcase.fill", active: true, accent: Color(red: 0.08, green: 0.15, blue: 0.24))
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 10)
        .background(.white.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0.89, green: 0.93, blue: 0.97))
                .frame(height: 2)
        }
    }

    private func tabItem(title: String, image: String, active: Bool, accent: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(active ? .white : accent)
                .frame(width: 28, height: 25)
                .background(active ? accent : Color(red: 0.93, green: 0.96, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(active ? accent : Color(red: 0.54, green: 0.60, blue: 0.67))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FeatureMarkView: View {
    let kind: FeatureMarkKind
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            LinearGradient(colors: kind.colors, startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(.white.opacity(0.30))
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: size * 0.38, y: -size * 0.38)
            Image(systemName: kind.icon)
                .font(.system(size: size * 0.50, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size >= 38 ? 15 : 13, style: .continuous))
            .shadow(color: kind.shadow.opacity(0.72), radius: 0, x: 0, y: size >= 38 ? 5 : 4)
            .accessibilityHidden(true)
    }
}

private struct GoalSetupDesignScreen: View {
    let store: OpenLARPStore
    let completed: () -> Void

    @State private var selectedRole = "Product Design internship"

    private let roles = [
        "Product Design internship",
        "Software internship",
        "First full-time role"
    ]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                colors: [.openLARPBlue, .openLARPBlue],
                mark: .path,
                titleSmall: "Setup",
                titleMain: "Set your goal",
                stat: "1/4"
            )

            VStack(alignment: .leading, spacing: 10) {
                GradientHeroCard(
                    icon: nil,
                    eyebrow: "Start here",
                    title: "Choose the role you are chasing.",
                    copy: "OpenLARP will build the cooked score and quest path around this target.",
                    colors: [.openLARPBlue, .openLARPBlueDark]
                )

                VStack(spacing: 8) {
                    ForEach(roles, id: \.self) { role in
                        ChoiceRow(
                            title: role,
                            trailing: selectedRole == role ? "Picked" : "",
                            isOn: selectedRole == role,
                            accent: .openLARPBlue
                        ) {
                            selectedRole = role
                        }
                    }
                }

                Spacer(minLength: 12)

                Button {
                    store.confirmGoal(
                        CareerGoal(
                            currentStatus: .student,
                            targetRole: selectedRole,
                            timeline: "12 days",
                            background: "Student or new grad building honest proof for this target.",
                            existingProof: "Class work, side project notes, or early drafts that need clearer evidence.",
                            confidence: 3,
                            biggestBlocker: "The strongest evidence is still private or incomplete."
                        )
                    )
                    completed()
                } label: {
                    Text("Continue to Cooked Check")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .background(Color.openLARPPanel)
        }
        .ignoresSafeArea(edges: .top)
    }
}

private struct CookedDiagnosticDesignScreen: View {
    let state: OpenLARPState
    let startFix: () -> Void
    let shareCard: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        FeatureMarkView(kind: .cooked, size: 34)
                        Text("Diagnostic".uppercased())
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.openLARPBlue)
                    }

                    HStack(alignment: .bottom) {
                        Text("64%")
                            .font(.system(size: 76, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text("Proof check")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.52, green: 0.31, blue: 0.00))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color(red: 1.00, green: 0.95, blue: 0.80))
                            .clipShape(Capsule())
                    }

                    Text("cooked, but not burnt.")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("The good news: you have raw material. The bad news: recruiters cannot inspect vibes.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    HeatMeter()
                }
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.06, green: 0.13, blue: 0.24), Color(red: 0.04, green: 0.24, blue: 0.69), .openLARPBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color(red: 0.02, green: 0.12, blue: 0.40), radius: 0, x: 0, y: 8)

                VStack(spacing: 8) {
                    MemeRow(title: "Resume energy: \"trust me bro\"", tag: "Roast")
                    MemeRow(title: "Fastest fix: one public proof artifact", tag: "Quest")
                    MemeRow(title: "Strongest signal: you actually ship", tag: "Not cooked")
                }

                DesignCard {
                    HStack(alignment: .top, spacing: 10) {
                        FeatureMarkView(kind: .cooked, size: 34)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                DesignPill("Verdict", style: .bad)
                                Spacer()
                                Text("Proof is hiding")
                                    .font(.system(size: 19, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.openLARPInk)
                            }
                            Text("You are not behind because you lack talent. You are behind because the strongest evidence is still sitting in private folders.")
                                .designCopy()
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Start Roast Fix", action: startFix)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Share Card", action: shareCard)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct SprintPathScreen: View {
    let state: OpenLARPState
    let showSevenDayMap: () -> Void
    let openRecovery: () -> Void
    let showToast: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DuoHeader(
                stats: ["PD", "12d", "\(max(580, state.progress.xp)) XP", "5 HP"],
                title: "Proof Sprint",
                subtitle: "Beat the cooked score with public evidence.",
                mark: .path,
                menuAction: showSevenDayMap,
                recoveryAction: openRecovery
            )

            RoadmapContent(
                showsMapBand: false,
                projectedLabel: "READINESS",
                projectedValue: "\(state.progress.readiness.overall)",
                projectedSubtitle: "Next focus: public proof",
                speech: "Proof beats \"trust me.\" Show the artifact.",
                steps: [
                    RoadmapStep(title: "Cooked check", subtitle: "Done - you survived", state: .done),
                    RoadmapStep(title: "Post proof", subtitle: "Today - +35 XP", state: .today),
                    RoadmapStep(title: "Alumni ask", subtitle: "Unlocks tomorrow", state: .locked),
                    RoadmapStep(title: "Skill gap check", subtitle: "Find repeated role signals", state: .locked)
                ],
                nodeAction: {
                    showToast("Preview opened. Today remains the main action.")
                }
            )
        }
    }
}

private struct SevenDayMapScreen: View {
    let state: OpenLARPState
    let showSprintPath: () -> Void
    let viewToday: () -> Void
    let openRecovery: () -> Void
    let showToast: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DuoHeader(
                stats: ["W1", "3d", "\(max(615, state.progress.xp)) XP", "56 goal"],
                title: "Comeback Map",
                subtitle: "Seven days to turn proof weak into usable.",
                mark: .path,
                menuAction: showSprintPath,
                recoveryAction: openRecovery
            )

            RoadmapContent(
                showsMapBand: true,
                projectedLabel: "TARGET",
                projectedValue: "56",
                projectedSubtitle: "Projected readiness by day 7",
                speech: "The plan is not \"apply harder.\" It is \"be easier to believe.\"",
                steps: [
                    RoadmapStep(title: "Public proof", subtitle: "Done - case study draft", state: .done),
                    RoadmapStep(title: "Message 2 alumni", subtitle: "Today - specific ask", state: .today),
                    RoadmapStep(title: "Extract skill gap", subtitle: "3 roles - repeated signal", state: .locked),
                    RoadmapStep(title: "Weekly report", subtitle: "What changed, what still cooks", state: .locked)
                ],
                nodeAction: {
                    showToast("Day preview opened.")
                },
                todayAction: viewToday
            )
        }
    }
}

private struct TodayQuestDesignScreen: View {
    let addProof: () -> Void
    let swapQuest: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                GradientHeroCard(
                    icon: "bolt.fill",
                    mark: .quest,
                    eyebrow: nil,
                    title: "Post a 150-word project breakdown.",
                    copy: "Goal: make a real artifact visible without pretending it is bigger than it is.",
                    colors: [Color(red: 0.58, green: 0.51, blue: 1.00), Color(red: 0.34, green: 0.27, blue: 0.85)]
                )

                DesignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Steps")
                            .eyebrow(color: .openLARPPurple)
                        ChoiceRow(title: "Pick one class or side project", isOn: true, accent: .openLARPPurple)
                        ChoiceRow(title: "Write problem, action, result", isOn: true, accent: .openLARPPurple)
                        ChoiceRow(title: "Post or save the proof link", isOn: false, accent: .openLARPPurple)
                    }
                }

                DesignCard {
                    HStack(alignment: .top, spacing: 10) {
                        FeatureMarkView(kind: .quest, size: 34)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                DesignPill("Difficulty", style: .warn)
                                Spacer()
                                Text("Medium")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                            }
                            Text("Proof required: link, screenshot, or pasted text.")
                                .designCopy()
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Add Proof", action: addProof)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Swap", action: swapQuest)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct AddProofDesignScreen: View {
    let store: OpenLARPStore
    let openReview: () -> Void
    let showToast: (String) -> Void

    @State private var proofText = "Project breakdown draft with problem, action, user feedback, result, next step, and one honest outcome line for the proof sheet."
    @State private var proofLink = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachments: [ProofAttachment] = []
    @State private var isSavingAttachments = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                DesignCard {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: 10) {
                            FeatureMarkView(kind: .proof, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Evidence pack")
                                    .eyebrow(color: .openLARPGreen)
                                Text("Turn \"I did stuff\" into proof.")
                                    .designHeadline(size: 23)
                            }
                        }
                        Text("Add the smallest believable artifact: text, link, screenshot, or outcome note.")
                            .designCopy()

                        ProofTicket()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(Color(red: 0.95, green: 1.00, blue: 0.97))
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    GridChoice(title: "Text proof", subtitle: "Ready", isOn: true)
                    GridChoice(title: "Project link", subtitle: "Ready", isOn: true)
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 4, matching: .images) {
                        GridChoice(title: "Screenshot", subtitle: "Optional", isOn: false)
                    }
                    .disabled(isSavingAttachments)
                    .onChange(of: selectedPhotoItems) { _, newItems in
                        Task {
                            await saveSelectedPhotos(newItems)
                        }
                    }
                    GridChoice(title: "Outcome note", subtitle: "Needed", isOn: false)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        FeatureMarkView(kind: .proof, size: 30)
                        Text("Proof sheet")
                            .eyebrow(color: .openLARPGreen)
                    }

                    Text("Prompt: \"What changed because of your work, even if it was small?\"")
                        .designCopy()

                    if isSavingAttachments {
                        Label("Saving proof images locally...", systemImage: "arrow.down.doc")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPSoftInk)
                    }

                    HStack(spacing: 10) {
                        Button("Save Draft") {
                            showToast("Draft saved locally for this session.")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button("Check Proof") {
                            guard store.state.currentQuest != nil else {
                                store.errorMessage = nil
                                openReview()
                                showToast("Proof review opened.")
                                return
                            }

                            store.checkProof(kind: .proof, text: proofText, link: proofLink, attachments: attachments)
                            if store.pendingQualityResult != nil {
                                openReview()
                                showToast("Proof review opened.")
                            } else {
                                showToast(store.errorMessage ?? "Add proof before checking.")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSavingAttachments)
                    }
                }
                .padding(12)
                .background(Color.openLARPPaper)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.openLARPLine, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(14)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }

    @MainActor
    private func saveSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isSavingAttachments = true
        defer { isSavingAttachments = false }

        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let attachment = try store.saveProofImage(
                        data: data,
                        contentType: "image/jpeg",
                        originalFileName: "proof-screenshot.jpg"
                    )
                    attachments.append(attachment)
                }
            } catch {
                showToast("That proof image could not be saved.")
            }
        }
    }
}

private struct ProofReviewDesignScreen: View {
    let result: QualityCheckResult?
    let claimXP: () -> Void
    let improveProof: () -> Void

    private var grade: String {
        guard let score = result?.qualityScore else { return "B+" }
        switch score {
        case 86...100:
            return "A-"
        case 72..<86:
            return "B+"
        case 56..<72:
            return "B-"
        default:
            return "C"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ReviewHeroCard(
                    grade: grade,
                    eyebrow: "Signal check",
                    title: "Proof passes. Needs one outcome.",
                    copy: "The work is believable. Add the result so it feels hireable.",
                    score: 72
                )

                DesignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            DesignPill(result?.isAccepted == false ? "Partial" : "Approved", style: result?.isAccepted == false ? .warn : .good)
                            Spacer()
                            Text("+35 XP")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                        }
                        SignalRow(title: "Real artifact attached", tag: result?.isAccepted == false ? "partial" : "strong", state: .good)
                        SignalRow(title: "Context is understandable", tag: "clear", state: .good)
                        SignalRow(title: "Impact is still vague", tag: "fix", state: .warn)
                    }
                }

                DesignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            DesignPill("Next fix", style: .warn)
                            Spacer()
                            Text("Add one result line")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                        }
                        Text("Example: \"This clarified the signup flow for 5 classmates.\" Keep it honest.")
                            .designCopy()
                    }
                }

                HStack(spacing: 10) {
                    Button("Claim XP", action: claimXP)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Improve", action: improveProof)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct StatsDesignScreen: View {
    let state: OpenLARPState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                DesignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            FeatureMarkView(kind: .stats, size: 34)
                            Text("Readiness")
                                .eyebrow(color: .openLARPOrange)
                        }
                        ReadinessRings(value: max(42, state.progress.readiness.overall))
                        Text("Overall readiness moved 42 to \(max(49, state.progress.readiness.overall)) this week.")
                            .designCopy()
                    }
                }

                MetricMeter(title: "Proof strength", tag: "Developing", value: 0.58, color: .openLARPGreen)
                MetricMeter(title: "Network", tag: "Weak", value: 0.34, color: .openLARPOrange)

                DesignCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            FeatureMarkView(kind: .stats, size: 34)
                            Text("Activity heatmap")
                                .eyebrow(color: .openLARPOrange)
                        }
                        ActivityHeatmap()
                        HStack {
                            Text("5 proof days this month")
                            Spacer()
                            Text("Current: \(max(3, state.progress.streakCount)) day streak")
                        }
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color.openLARPSoftInk)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct EvidenceBankDesignScreen: View {
    let state: OpenLARPState
    let addProof: () -> Void
    let improveWeakest: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                GradientHeroCard(
                    icon: "doc.fill",
                    mark: .proof,
                    eyebrow: "Vault",
                    title: "Proof beats profile polish.",
                    copy: "Everything here came from a quest: links, screenshots, notes, and outcomes.",
                    colors: [.openLARPMint, .openLARPGreen]
                )

                VStack(spacing: 8) {
                    ChoiceRow(title: "Project breakdown", trailing: "B+", isOn: true, accent: .openLARPGreen)
                    ChoiceRow(title: "Alumni message", trailing: "Draft", isOn: false, accent: .openLARPGreen)
                    ChoiceRow(title: "Interview story", trailing: "Missing", isOn: false, accent: .openLARPGreen)
                    ChoiceRow(title: "Target roles", trailing: "3 saved", isOn: false, accent: .openLARPGreen)
                }

                HStack(spacing: 10) {
                    Button("Improve Weakest", action: improveWeakest)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Add Proof", action: addProof)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct RecoveryDesignScreen: View {
    let saveStreak: () -> Void
    let useFreeze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GradientHeroCard(
                icon: "shield.fill",
                mark: .recovery,
                eyebrow: "Missed day",
                title: "Your chain is dented, not dead.",
                copy: "Do a 7-minute recovery quest to protect the streak.",
                colors: [Color(red: 0.38, green: 0.48, blue: 0.62), Color(red: 0.14, green: 0.23, blue: 0.35)]
            )

            DesignCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 9) {
                        FeatureMarkView(kind: .recovery, size: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            DesignPill("Recovery quest", style: .warn)
                            Text("Find 3 repeated skill gaps")
                                .designHeadline(size: 18)
                        }
                    }
                    Text("Paste three role descriptions, then pull out the requirement that keeps showing up.")
                        .designCopy()
                }
            }

            HStack(spacing: 10) {
                Button("Save My Streak", action: saveStreak)
                    .buttonStyle(PrimaryButtonStyle())
                Button("Use Freeze", action: useFreeze)
                    .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()
        }
        .padding(16)
        .background(Color.openLARPPanel)
    }
}

private struct CareerHubDesignScreen: View {
    let state: OpenLARPState
    let editGoal: () -> Void
    let exportData: () -> Void
    let openSettings: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Career sprint")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color.openLARPBlue)
                        .clipShape(Capsule())

                    HStack(spacing: 11) {
                        AvatarBadge()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.goal?.targetRole ?? "Product Design internship")
                                .designHeadline(size: 16)
                            Text("Private career profile built from quests, proof, and honest outcomes.")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        SummaryTile(value: "\(max(49, state.progress.readiness.overall))", label: "Readiness", color: .openLARPBlue)
                        SummaryTile(value: "\(max(8, state.progress.proofCount))", label: "Proofs saved", color: .openLARPGreen)
                        SummaryTile(value: "\(max(3, state.progress.streakCount))d", label: "Current streak", color: .openLARPOrange)
                        SummaryTile(value: "Private", label: "Profile mode", color: .openLARPPurple)
                    }
                }
                .padding(13)
                .background(
                    LinearGradient(colors: [.white, Color(red: 0.93, green: 0.97, blue: 1.00), Color(red: 0.97, green: 1.00, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(Color(red: 0.84, green: 0.90, blue: 0.97), lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .shadow(color: Color(red: 0.78, green: 0.86, blue: 0.94), radius: 0, x: 0, y: 5)

                HStack(spacing: 8) {
                    VisualSignalCard()
                    VisualRoleCard()
                }

                NativeGroup(rows: [
                    NativeRowModel(icon: "briefcase.fill", title: "Target role", subtitle: "Product Design internships", badge: "Edit", color: .openLARPBlue, action: editGoal),
                    NativeRowModel(icon: "doc.fill", title: "Proof vault", subtitle: "\(max(8, state.progress.proofCount)) private items", badge: "Private", color: .openLARPGreen, action: {}),
                    NativeRowModel(icon: "brain.head.profile", title: "Quest memory", subtitle: "Goal + proof history only", badge: "On", color: .openLARPPurple, action: openSettings)
                ])

                DesignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("14-day sprint")
                            .designHeadline(size: 13)
                        SprintStrip()
                    }
                }
                .background(Color(red: 1.00, green: 0.98, blue: 0.92))

                HStack(spacing: 10) {
                    Button("Edit Goal", action: editGoal)
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Export Data", action: exportData)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct SettingsDesignScreen: View {
    @Binding var notificationsEnabled: Bool
    @Binding var memoryEnabled: Bool
    let showToast: (String) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 11) {
                    AvatarBadge()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenLARP account")
                            .designHeadline(size: 16)
                        Text("langqi@example.com")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.openLARPSoftInk)
                    }
                    Spacer()
                    Text("Pro")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.45, blue: 0.28))
                        .frame(width: 46, height: 34)
                        .background(Color(red: 0.87, green: 0.97, blue: 0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(11)
                .background(
                    LinearGradient(colors: [.white, Color(red: 0.96, green: 0.98, blue: 1.00), Color(red: 0.97, green: 1.00, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(Color(red: 0.84, green: 0.90, blue: 0.97), lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                .shadow(color: Color(red: 0.81, green: 0.88, blue: 0.94), radius: 0, x: 0, y: 5)

                SettingsSection(
                    title: "Account",
                    rows: [
                        NativeRowModel(icon: "envelope.fill", title: "Email", subtitle: "langqi@example.com", badge: "Edit", color: .openLARPBlue, action: { showToast("Email controls opened.") }),
                        NativeRowModel(icon: "lock.fill", title: "Password", subtitle: "Last changed recently", badge: "Change", color: .openLARPGreen, action: { showToast("Password controls opened.") }),
                        NativeRowModel(icon: "creditcard.fill", title: "Subscription", subtitle: "14-day sprint, then $29/month", badge: "Manage", color: .openLARPOrange, action: { showToast("Subscription controls opened.") })
                    ]
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("App")
                        .settingsLabel()
                    VStack(spacing: 0) {
                        ToggleNativeRow(
                            icon: "bell.fill",
                            title: "Notifications",
                            subtitle: "Daily quest reminder at 7:30 PM",
                            isOn: $notificationsEnabled,
                            color: .openLARPPurple
                        )
                        Divider().padding(.leading, 52)
                        NativeRow(model: NativeRowModel(icon: "doc.fill", title: "Privacy", subtitle: "Proof stays private by default", badge: "On", color: .openLARPGreen, action: { showToast("Privacy controls opened.") }))
                        Divider().padding(.leading, 52)
                        NativeRow(model: NativeRowModel(icon: "questionmark.circle.fill", title: "Help & support", subtitle: "FAQ, contact, report a problem", badge: "Open", color: .openLARPCoral, action: { showToast("Help opened.") }))
                    }
                    .settingsListStyle()
                }

                SettingsSection(
                    title: "Account management",
                    rows: [
                        NativeRowModel(icon: "clock.fill", title: "Session", subtitle: "Sign out on this device", badge: "Log Out", color: Color(red: 0.45, green: 0.54, blue: 0.64), action: { showToast("Session controls opened.") }),
                        NativeRowModel(icon: "lock.fill", title: "Advanced", subtitle: "Export, closure, and recovery options.", badge: "View", color: Color(red: 0.55, green: 0.60, blue: 0.66), isDanger: true, action: { showToast("Advanced controls opened.") })
                    ]
                )
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Color.openLARPPanel)
    }
}

private struct DuoHeader: View {
    let stats: [String]
    let title: String
    let subtitle: String
    let mark: FeatureMarkKind
    let menuAction: () -> Void
    let recoveryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    if index == 3 {
                        statBadge(stat)
                            .contentShape(Capsule())
                            .onTapGesture(perform: recoveryAction)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(stat)
                    } else {
                        statBadge(stat)
                    }
                }
            }

            HStack(spacing: 10) {
                FeatureMarkView(kind: mark, size: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 29, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: menuAction) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .shadow(color: Color(red: 0.00, green: 0.28, blue: 0.75).opacity(0.4), radius: 0, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title == "Proof Sprint" ? "Show 7-Day Map" : "Show Proof Sprint")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 50)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: [.openLARPBlue, Color(red: 0.46, green: 0.41, blue: 1.00)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .ignoresSafeArea(edges: .top)
    }

    private func statBadge(_ stat: String) -> some View {
        Text(stat)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(.white.opacity(0.18))
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 2))
            .clipShape(Capsule())
    }
}

private struct RoadmapContent: View {
    let showsMapBand: Bool
    let projectedLabel: String
    let projectedValue: String
    let projectedSubtitle: String
    let speech: String
    let steps: [RoadmapStep]
    let nodeAction: () -> Void
    var todayAction: (() -> Void)?

    private var projectionIndex: Int {
        min(2, steps.count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if showsMapBand {
                    HStack(spacing: 5) {
                        ForEach(1...7, id: \.self) { day in
                            Text("\(day)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(day <= 2 ? .white : Color.openLARPSoftInk)
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(day == 1 ? Color.openLARPGreen : day == 2 ? Color.openLARPCoral : Color(red: 0.93, green: 0.96, blue: 0.98))
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .shadow(color: day <= 2 ? .black.opacity(0.18) : Color(red: 0.82, green: 0.86, blue: 0.91), radius: 0, x: 0, y: 4)
                        }
                    }
                }

                ZStack {
                    WindingPath()
                        .stroke(Color(red: 0.83, green: 0.88, blue: 0.93), style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [1, 24]))
                        .padding(.horizontal, 30)

                    VStack(spacing: showsMapBand ? 10 : 13) {
                        ForEach(Array(steps.prefix(projectionIndex).enumerated()), id: \.offset) { index, step in
                            RoadmapStepRow(step: step, index: index, action: nodeAction, todayAction: todayAction)
                        }

                        RoadmapProjectionRow(
                            label: projectedLabel,
                            value: projectedValue,
                            subtitle: projectedSubtitle,
                            index: projectionIndex
                        )

                        Text(speech)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color.openLARPInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 260)
                            .background(.white)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.openLARPLine, lineWidth: 3))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color(red: 0.82, green: 0.87, blue: 0.92), radius: 0, x: 0, y: 5)

                        ForEach(Array(steps.dropFirst(projectionIndex).enumerated()), id: \.offset) { offset, step in
                            RoadmapStepRow(step: step, index: offset + projectionIndex, action: nodeAction, todayAction: todayAction)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(14)
            .padding(.bottom, 18)
        }
        .background(
            LinearGradient(colors: [.white, .openLARPPanel, Color(red: 0.96, green: 0.99, blue: 0.97)], startPoint: .top, endPoint: .bottom)
        )
    }
}

private enum RoadmapNodeState {
    case done
    case today
    case locked
}

private struct RoadmapStep {
    let title: String
    let subtitle: String
    let state: RoadmapNodeState
}

private struct RoadmapStepRow: View {
    let step: RoadmapStep
    let index: Int
    let action: () -> Void
    var todayAction: (() -> Void)?

    private var isEven: Bool { index.isMultiple(of: 2) }

    var body: some View {
        HStack(spacing: 6) {
            if isEven {
                node
                note
                Spacer(minLength: 16)
            } else {
                Spacer(minLength: 16)
                note
                node
            }
        }
        .frame(minHeight: 68)
    }

    private var node: some View {
        Button(action: {
            if step.state == .today, let todayAction {
                todayAction()
            } else {
                action()
            }
        }) {
            Image(systemName: iconName)
                .font(.system(size: step.state == .today ? 20 : 18, weight: .black))
                .foregroundStyle(nodeForeground)
                .frame(width: step.state == .today ? 70 : 62, height: step.state == .today ? 58 : 52)
                .background(nodeBackground)
                .overlay {
                    if step.state == .today {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(Color(red: 1.00, green: 0.91, blue: 0.64), lineWidth: 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .shadow(color: shadowColor, radius: 0, x: 0, y: step.state == .today ? 10 : 8)
                .overlay(alignment: .top) {
                    if step.state == .today {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(Color.openLARPBlueDark)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white)
                            .overlay(Capsule().stroke(Color.openLARPLine, lineWidth: 2))
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.77, green: 0.84, blue: 0.90), radius: 0, x: 0, y: 4)
                            .offset(y: -24)
                    }
                }
        }
        .buttonStyle(.plain)
        .padding(.top, step.state == .today ? 18 : 0)
    }

    private var note: some View {
        VStack(alignment: isEven ? .leading : .trailing, spacing: 2) {
            Text(step.title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(step.subtitle)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.openLARPSoftInk)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .multilineTextAlignment(isEven ? .leading : .trailing)
        .frame(maxWidth: 118, alignment: isEven ? .leading : .trailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.openLARPLine, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color(red: 0.83, green: 0.88, blue: 0.93), radius: 0, x: 0, y: 2)
        .rotationEffect(.degrees(isEven ? -1 : 1))
    }

    private var iconName: String {
        switch step.state {
        case .done: "checkmark"
        case .today: "bolt.fill"
        case .locked: "lock.fill"
        }
    }

    private var nodeForeground: Color {
        step.state == .locked ? Color(red: 0.65, green: 0.71, blue: 0.76) : .white
    }

    private var nodeBackground: LinearGradient {
        switch step.state {
        case .done:
            LinearGradient(colors: [Color(red: 0.22, green: 0.87, blue: 0.58), Color(red: 0.09, green: 0.72, blue: 0.44)], startPoint: .top, endPoint: .bottom)
        case .today:
            LinearGradient(colors: [Color(red: 1.00, green: 0.85, blue: 0.35), .openLARPYellow, .openLARPOrange], startPoint: .top, endPoint: .bottom)
        case .locked:
            LinearGradient(colors: [Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.91, green: 0.93, blue: 0.96)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var shadowColor: Color {
        switch step.state {
        case .done: Color(red: 0.05, green: 0.53, blue: 0.31)
        case .today: Color(red: 0.78, green: 0.47, blue: 0.09)
        case .locked: Color(red: 0.81, green: 0.85, blue: 0.89)
        }
    }
}

private struct RoadmapProjectionRow: View {
    let label: String
    let value: String
    let subtitle: String
    let index: Int

    private var isEven: Bool { index.isMultiple(of: 2) }

    var body: some View {
        HStack(spacing: 6) {
            if isEven {
                lockedNode
                note
                Spacer(minLength: 16)
            } else {
                Spacer(minLength: 16)
                note
                lockedNode
            }
        }
        .frame(minHeight: 68)
    }

    private var note: some View {
        VStack(alignment: isEven ? .leading : .trailing, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPBlueDark)
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
            Text(subtitle)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.openLARPBlueDark)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .multilineTextAlignment(isEven ? .leading : .trailing)
        .frame(maxWidth: 118, alignment: isEven ? .leading : .trailing)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [.white, Color(red: 0.93, green: 0.97, blue: 1.00)], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(red: 0.72, green: 0.86, blue: 1.00), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(red: 0.79, green: 0.87, blue: 0.96), radius: 0, x: 0, y: 4)
        .rotationEffect(.degrees(isEven ? 1 : -1))
    }

    private var lockedNode: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(Color(red: 0.65, green: 0.71, blue: 0.76))
            .frame(width: 62, height: 52)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.91, green: 0.93, blue: 0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .shadow(color: Color(red: 0.81, green: 0.85, blue: 0.89), radius: 0, x: 0, y: 8)
    }
}

private struct WindingPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: width * 0.16, y: height * 0.03))
        path.addCurve(to: CGPoint(x: width * 0.20, y: height * 0.34), control1: CGPoint(x: width * 0.90, y: height * 0.11), control2: CGPoint(x: width * 0.88, y: height * 0.23))
        path.addCurve(to: CGPoint(x: width * 0.78, y: height * 0.55), control1: CGPoint(x: width * 0.02, y: height * 0.42), control2: CGPoint(x: width * 0.10, y: height * 0.51))
        path.addCurve(to: CGPoint(x: width * 0.22, y: height * 0.78), control1: CGPoint(x: width * 1.03, y: height * 0.62), control2: CGPoint(x: width * 0.92, y: height * 0.72))
        path.addCurve(to: CGPoint(x: width * 0.86, y: height * 0.98), control1: CGPoint(x: width * 0.04, y: height * 0.84), control2: CGPoint(x: width * 0.20, y: height * 0.93))
        return path
    }
}

private struct GradientHeroCard: View {
    var icon: String?
    var mark: FeatureMarkKind?
    var customLeading: AnyView?
    let eyebrow: String?
    let title: String
    let copy: String
    let colors: [Color]

    init(icon: String?, mark: FeatureMarkKind? = nil, eyebrow: String?, title: String, copy: String, colors: [Color]) {
        self.icon = icon
        self.mark = mark
        self.customLeading = nil
        self.eyebrow = eyebrow
        self.title = title
        self.copy = copy
        self.colors = colors
    }

    init(customLeading: AnyView, eyebrow: String?, title: String, copy: String, colors: [Color]) {
        self.icon = nil
        self.mark = nil
        self.customLeading = customLeading
        self.eyebrow = eyebrow
        self.title = title
        self.copy = copy
        self.colors = colors
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let customLeading {
                customLeading
            } else if let mark {
                FeatureMarkView(kind: mark, size: 34)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 7) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.76))
                }
                Text(title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                Text(copy)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: colors.last?.opacity(0.9) ?? .black.opacity(0.2), radius: 0, x: 0, y: 6)
    }
}

private struct DesignCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(Color.openLARPLine, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .shadow(color: Color(red: 0.79, green: 0.85, blue: 0.91), radius: 0, x: 0, y: 5)
    }
}

private struct ChoiceRow: View {
    let title: String
    var trailing: String = ""
    let isOn: Bool
    let accent: Color
    var action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(isOn ? accent : Color.openLARPInk)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 50)
        .background(isOn ? accent.opacity(0.10) : .white)
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(isOn ? accent : Color.openLARPLine, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct GridChoice: View {
    let title: String
    let subtitle: String
    let isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isOn ? Color.openLARPGreen : Color.openLARPInk)
            Text(subtitle.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(isOn ? Color.openLARPGreen : Color.openLARPSoftInk)
        }
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .padding(.horizontal, 10)
        .background(isOn ? Color.openLARPGreen.opacity(0.10) : .white)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isOn ? Color.openLARPGreen : Color.openLARPLine, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum PillStyle {
    case neutral
    case warn
    case good
    case bad
}

private struct DesignPill: View {
    let title: String
    let style: PillStyle

    init(_ title: String, style: PillStyle = .neutral) {
        self.title = title
        self.style = style
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch style {
        case .neutral: .openLARPBlueDark
        case .warn: Color(red: 0.54, green: 0.32, blue: 0.00)
        case .good: Color(red: 0.04, green: 0.45, blue: 0.28)
        case .bad: Color(red: 0.64, green: 0.12, blue: 0.23)
        }
    }

    private var background: Color {
        switch style {
        case .neutral: Color(red: 0.94, green: 0.97, blue: 1.00)
        case .warn: Color(red: 1.00, green: 0.95, blue: 0.80)
        case .good: Color(red: 0.87, green: 0.97, blue: 0.92)
        case .bad: Color(red: 1.00, green: 0.90, blue: 0.93)
        }
    }
}

private struct MemeRow: View {
    let title: String
    let tag: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(tag.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Color.openLARPCoral)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.openLARPLine, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(red: 0.83, green: 0.88, blue: 0.93), radius: 0, x: 0, y: 5)
    }
}

private struct HeatMeter: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 2))
                Capsule()
                    .fill(
                        LinearGradient(colors: [.openLARPGreen, .openLARPYellow, .openLARPCoral], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: proxy.size.width * 0.64)
                    .padding(3)
            }
        }
        .frame(height: 18)
    }
}

private struct ProofTicket: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 48)
                .background(LinearGradient(colors: [.openLARPMint, .openLARPGreen], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color(red: 0.05, green: 0.53, blue: 0.31), radius: 0, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Project breakdown draft")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color.openLARPInk)
                Text("Problem, action, result - needs one outcome line")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(.white.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.openLARPGreen.opacity(0.38), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ReviewHeroCard: View {
    let grade: String
    let eyebrow: String
    let title: String
    let copy: String
    let score: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text(grade)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.45, blue: 0.28))
                    .frame(width: 74, height: 74)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.91, green: 1.00, blue: 0.95), Color(red: 0.79, green: 0.96, blue: 0.87)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(red: 0.78, green: 0.95, blue: 0.85), lineWidth: 4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color(red: 0.62, green: 0.85, blue: 0.72), radius: 0, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(copy)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProofBar(score: score)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [.openLARPMint, .openLARPGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(red: 0.05, green: 0.53, blue: 0.31), radius: 0, x: 0, y: 6)
    }
}

private struct ProofBar: View {
    let score: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.93, green: 0.97, blue: 0.95))
                    .overlay(Capsule().stroke(Color(red: 0.85, green: 0.92, blue: 0.87), lineWidth: 2))
                Capsule()
                    .fill(LinearGradient(colors: [.openLARPCoral, .openLARPYellow, .openLARPGreen], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * CGFloat(min(max(score, 0), 100)) / 100)
                    .padding(3)
            }
        }
        .frame(height: 14)
    }
}

private enum SignalState {
    case good
    case warn
}

private struct SignalRow: View {
    let title: String
    let tag: String
    let state: SignalState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state == .good ? "checkmark" : "circle.fill")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(state == .good ? .white : Color(red: 0.48, green: 0.28, blue: 0.00))
                .frame(width: 20, height: 20)
                .background(state == .good ? Color.openLARPGreen : Color.openLARPYellow)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
            Spacer()
            Text(tag.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(Color.openLARPSoftInk)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(red: 0.96, green: 0.98, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MetricMeter: View {
    let title: String
    let tag: String
    let value: CGFloat
    let color: Color

    var body: some View {
        DesignCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color.openLARPInk)
                    Spacer()
                    DesignPill(tag, style: tag == "Weak" ? .warn : .good)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(red: 0.90, green: 0.94, blue: 0.97))
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * value)
                    }
                }
                .frame(height: 10)
            }
        }
    }
}

private struct ReadinessRings: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.90, green: 0.94, blue: 0.97), lineWidth: 18)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(AngularGradient(colors: [.openLARPOrange, .openLARPPurple, .openLARPBlue], center: .center), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(Color(red: 0.90, green: 0.94, blue: 0.97), lineWidth: 12)
                .frame(width: 94, height: 94)
            Circle()
                .trim(from: 0, to: 0.58)
                .stroke(AngularGradient(colors: [.openLARPGreen, .openLARPMint], center: .center), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 94, height: 94)
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPBlueDark)
        }
        .frame(width: 142, height: 142)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct ActivityHeatmap: View {
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("")
                    .frame(width: 24)
                ForEach(["Mar", "Apr", "May", "Jun", "Jul"], id: \.self) { month in
                    Text(month)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(Color.openLARPSoftInk)

            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(Color.openLARPSoftInk)
                            .frame(width: 24, height: 13)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                    ForEach(0..<35, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(heatColor(for: index))
                            .frame(height: 13)
                    }
                }
            }
        }
    }

    private func heatColor(for index: Int) -> Color {
        if index.isMultiple(of: 7) { return .openLARPGreen }
        if index.isMultiple(of: 4) { return .openLARPBlue }
        if index.isMultiple(of: 3) { return Color(red: 0.61, green: 0.84, blue: 1.00) }
        if index.isMultiple(of: 11) { return Color(red: 0.49, green: 0.88, blue: 0.74) }
        return Color.openLARPLine
    }
}

private struct AvatarBadge: View {
    var body: some View {
        Text("OL")
            .font(.system(size: 20, weight: .black, design: .rounded))
            .tracking(-1.2)
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(
                LinearGradient(colors: [.openLARPCyan, .openLARPBlue, .openLARPPurple], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(red: 0.03, green: 0.33, blue: 0.82), radius: 0, x: 0, y: 6)
    }
}

private struct SummaryTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(color.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(color.opacity(0.28), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct VisualSignalCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Signal radar")
                .designHeadline(size: 12)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AngularGradient(colors: [.openLARPMint, .openLARPCyan, .openLARPBlue, .openLARPPurple, .openLARPMint], center: .center))
                .frame(width: 62, height: 62)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white, lineWidth: 10)
                )
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(LinearGradient(colors: [Color(red: 0.95, green: 1.00, blue: 0.97), .white], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color(red: 0.75, green: 0.91, blue: 0.82), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .shadow(color: Color(red: 0.72, green: 0.89, blue: 0.79), radius: 0, x: 0, y: 4)
    }
}

private struct VisualRoleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Sprint momentum")
                .designHeadline(size: 12)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array([0.42, 0.60, 0.54, 0.78, 0.90].enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill([Color.openLARPBlue, .openLARPGreen, .openLARPOrange, .openLARPPurple, .openLARPBlueDark][index])
                        .frame(height: 42 * height)
                }
            }
            .frame(height: 42)
            Text("Proof + network moved this week.")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.openLARPSoftInk)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(LinearGradient(colors: [Color(red: 1.00, green: 0.97, blue: 0.91), .white], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color(red: 1.00, green: 0.85, blue: 0.61), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .shadow(color: Color(red: 0.92, green: 0.80, blue: 0.58), radius: 0, x: 0, y: 4)
    }
}

private struct NativeRowModel: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let badge: String
    let color: Color
    let isDanger: Bool
    let action: () -> Void

    init(
        icon: String,
        title: String,
        subtitle: String,
        badge: String,
        color: Color,
        isDanger: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.color = color
        self.isDanger = isDanger
        self.action = action
    }
}

private struct NativeGroup: View {
    let rows: [NativeRowModel]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                NativeRow(model: row)
                if row.id != rows.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(7)
        .background(.white)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.openLARPLine, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color(red: 0.83, green: 0.88, blue: 0.93), radius: 0, x: 0, y: 5)
    }
}

private struct NativeRow: View {
    let model: NativeRowModel

    var body: some View {
        Button(action: model.action) {
            HStack(spacing: 10) {
                Image(systemName: model.icon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(LinearGradient(colors: [model.color.opacity(0.78), model.color], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: model.color.opacity(0.55), radius: 0, x: 0, y: 4)
                    .opacity(model.isDanger ? 0.62 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(model.isDanger ? Color.openLARPSoftInk : Color.openLARPInk)
                    Text(model.subtitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.isDanger {
                    Text(model.badge)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.74, green: 0.22, blue: 0.32))
                } else {
                    DesignPill(model.badge, style: model.badge == "Private" || model.badge == "On" ? .good : model.badge == "Manage" ? .warn : .neutral)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(model.isDanger ? Color.openLARPPanel : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsSection: View {
    let title: String
    let rows: [NativeRowModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .settingsLabel()
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    NativeRow(model: row)
                    if row.id != rows.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .settingsListStyle()
        }
    }
}

private struct ToggleNativeRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(LinearGradient(colors: [color.opacity(0.78), color], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.openLARPSoftInk)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.openLARPGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
    }
}

private struct SprintStrip: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(index < 2 ? LinearGradient(colors: [.openLARPMint, .openLARPGreen], startPoint: .top, endPoint: .bottom) : index == 2 ? LinearGradient(colors: [.openLARPYellow, .openLARPOrange], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color(red: 0.92, green: 0.95, blue: 0.98), Color(red: 0.92, green: 0.95, blue: 0.98)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 22)
            }
        }
    }
}

private extension View {
    func designHeadline(size: CGFloat = 24) -> some View {
        font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(Color.openLARPInk)
            .lineLimit(3)
            .minimumScaleFactor(0.78)
    }

    func designCopy() -> some View {
        font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.openLARPSoftInk)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    func eyebrow(color: Color) -> some View {
        font(.system(size: 13, weight: .black, design: .rounded))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    func settingsLabel() -> some View {
        font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(Color(red: 0.44, green: 0.50, blue: 0.58))
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    func settingsListStyle() -> some View {
        background(.white)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.openLARPLine, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(red: 0.83, green: 0.88, blue: 0.93), radius: 0, x: 0, y: 4)
    }
}
