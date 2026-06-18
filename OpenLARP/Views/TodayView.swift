import PhotosUI
import SwiftUI

struct TodayView: View {
    let store: OpenLARPStore
    @State private var showingAgent = false
    @State private var showingSkipConfirmation = false
    @State private var showingOutcomeLog = false
    @State private var lastLoggedOutcomeCount = 0
    @State private var selectedProof: ProofRecord?
    @State private var pendingDiagnosticResult: CookedDiagnosticResultContent?
    @State private var selectedCookedShareCard: CookedShareCardContent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.state.needsGoalSetup {
                    GoalSetupView(store: store) { content in
                        pendingDiagnosticResult = content
                    }
                } else {
                    header
                    subscriptionAccessCard
                    questCard
                    diagnosticCard
                    progressStrip
                    dailyAgentBrief
                    Button {
                        showingAgent = true
                    } label: {
                        Label("Ask Agent about this quest", systemImage: "sparkles")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    logOutcomeAction
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAgent) {
            NavigationStack {
                AgentChatView(store: store)
            }
        }
        .sheet(item: $selectedProof) { proof in
            ProofDetailView(proof: proof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .sheet(item: $pendingDiagnosticResult) { content in
            DiagnosticResultBridgeView(
                content: content,
                privateShareContent: CookedShareCardContent(state: store.state),
                detailedShareContent: CookedShareCardContent(state: store.state, includeDetails: true),
                startQuest: {
                    store.startCurrentQuest()
                },
                adjustGoal: {
                    store.resetGoal()
                },
                recordCookedCardPrepared: {
                    store.recordCookedCardPrepared()
                }
            )
        }
        .sheet(item: $selectedCookedShareCard) { content in
            CookedShareCardSheet(
                privateContent: content,
                detailedContent: CookedShareCardContent(state: store.state, includeDetails: true) ?? content,
                onImagePrepared: {
                    store.recordCookedCardPrepared()
                }
            )
        }
        .sheet(isPresented: $showingOutcomeLog) {
            OutcomeLogSheet { kind, title, organizationName, note, occurredAt, isPrivate in
                store.logOutcome(
                    kind: kind,
                    title: title,
                    organizationName: organizationName,
                    note: note,
                    occurredAt: occurredAt,
                    isPrivate: isPrivate
                )
            }
        }
        .confirmationDialog(
            "Skip today?",
            isPresented: $showingSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Skip Today", role: .destructive) {
                if !store.isProofChecking {
                    store.skipCurrentQuest()
                }
            }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("This resets the active streak to 0, keeps your earlier XP and proof receipts, and locks the next quest until tomorrow.")
        }
        .onAppear {
            lastLoggedOutcomeCount = store.state.outcomeLog.count
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpenLARPHeroCard(
                feature: .quest,
                eyebrow: "Proof Sprint",
                title: store.state.goal?.targetRole ?? "Today quest",
                subtitle: "One concrete action that creates real proof for the target role.",
                stat: "\(store.state.progress.streakCount) streak"
            )

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SprintStrip(completed: store.state.progress.completedQuestCount)

                    HStack(spacing: 8) {
                        SummaryTile(value: "\(store.state.progress.xp)", label: "XP", color: .openLARPBlue)
                        SummaryTile(value: "\(store.state.progress.proofCount)", label: "Proof", color: .openLARPGreen)
                        SummaryTile(value: store.state.goal?.timeline ?? "Sprint", label: "Timeline", color: .openLARPCoral)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionAccessCard: some View {
        let access = store.subscriptionAccess()
        if access.shouldShowPaywall {
            let decision = store.subscriptionGateDecision(for: .startQuest)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(feature: .profile, eyebrow: "Access", title: decision.title)

                    Text(decision.message)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await store.restorePurchases()
                            }
                        } label: {
                            if store.isRestoringPurchases {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Restoring")
                                }
                            } else {
                                Label("Restore Purchases", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(store.isRestoringPurchases)

                        Pill(title: access.status.label, systemImage: "lock.fill", color: .openLARPCoral)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticCard: some View {
        if let content = CookedDiagnosticResultContent(state: store.state) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(feature: .cooked, eyebrow: content.eyebrow, title: "The roast report")

                            Text(content.title)
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(Color.openLARPCoral)
                        }

                        Spacer()

                        ScoreRing(score: content.score)
                    }

                    Text(content.mainGap)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Strongest signal: \(content.strongestSignal)", systemImage: "checkmark.seal.fill")
                        Label("Fastest fix: \(content.fastestFix)", systemImage: "bolt.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Pill(title: content.scoreText, systemImage: "flame.fill", color: .openLARPCoral)
                        Pill(title: content.readinessText, systemImage: "chart.line.uptrend.xyaxis", color: .openLARPGreen)
                    }

                    if store.state.currentQuest?.status == .available {
                        HStack(spacing: 10) {
                            Button {
                                store.startCurrentQuest()
                            } label: {
                                Label(content.primaryActionTitle, systemImage: "play.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())

                            Button {
                                selectedCookedShareCard = CookedShareCardContent(state: store.state)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.headline)
                                    .foregroundStyle(Color.openLARPInk)
                                    .frame(width: 48, height: 48)
                                    .background(Color.openLARPBlue.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .accessibilityLabel(content.shareActionTitle)
                        }
                    } else {
                        Button {
                            selectedCookedShareCard = CookedShareCardContent(state: store.state)
                        } label: {
                            Label(content.shareActionTitle, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var questCard: some View {
        if let recovery = MissedDayRecoveryContent(state: store.state) {
            MissedDayRecoveryCard(content: recovery) {
                store.startCurrentQuest()
            }
        } else if let skipped = SkippedTodayContent(state: store.state) {
            SkippedTodayCard(content: skipped)
        } else if let completion = TodayCompletionContent(state: store.state) {
            DoneForTodayCard(
                content: completion,
                attachmentURL: { attachment in
                    store.localURL(for: attachment)
                },
                openProof: { proof in
                    selectedProof = proof
                }
            )
        } else if let quest = store.state.currentQuest {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(feature: .quest, eyebrow: "Private proof", title: "Today quest")

                    HStack {
                        Pill(title: quest.timeEstimate, systemImage: "timer", color: .openLARPGreen)
                        Pill(title: "+\(quest.xpReward) XP", systemImage: "bolt.fill", color: .openLARPYellow)
                        Pill(title: quest.gap.title, systemImage: "scope", color: .openLARPCoral)
                    }

                    Text(quest.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(quest.purpose)
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(quest.proofRequired, systemImage: "checkmark.seal")
                        Label("Difficulty: \(quest.difficulty)", systemImage: "gauge.with.dots.needle.50percent")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)

                    switch quest.status {
                    case .available:
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                Button {
                                    store.startCurrentQuest()
                                } label: {
                                    Label("Start Quest", systemImage: "play.fill")
                                }
                                .buttonStyle(PrimaryButtonStyle())

                                Button {
                                    store.swapCurrentQuest()
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.headline)
                                        .foregroundStyle(Color.openLARPInk)
                                        .frame(width: 48, height: 48)
                                        .background(Color.openLARPYellow.opacity(0.24))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .accessibilityLabel("Swap quest")
                            }

                            skipTodayButton
                        }
                    case .inProgress:
                        questSteps(quest.steps)
                        if let result = store.pendingQualityResult {
                            QualityResultCard(result: result, store: store)
                        } else {
                            ProofComposer(store: store, draft: store.pendingProof)
                        }
                        skipTodayButton
                    case .completed:
                        Label("Quest complete. Your next quest is ready on the map.", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPGreen)
                    case .locked:
                        Label("This quest unlocks after today's proof.", systemImage: "lock.fill")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPSoftInk)
                    case .skipped:
                        Label("Skipped. Use a recovery quest to protect your streak.", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sprint complete")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                    Text("You finished the local seven-day path. Change your goal or wait for the next sprint version.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                }
            }
        }
    }

    private var skipTodayButton: some View {
        Button {
            showingSkipConfirmation = true
        } label: {
            Label("Skip Today", systemImage: "forward.end")
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.isProofChecking)
        .opacity(store.isProofChecking ? 0.45 : 1)
    }

    private var logOutcomeAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showingOutcomeLog = true
            } label: {
                Label("Log Outcome", systemImage: "flag.fill")
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("Save applications, interviews, rejections, offers, or changed goals as private local career history.")
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)

            if didSaveOutcome, let latestOutcome = OutcomeLogContent(outcomes: store.state.outcomeLog).outcomes.first {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.openLARPGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Latest outcome saved")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPInk)
                        Text(latestOutcome.displayTitle)
                            .font(.caption)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .background(Color.openLARPGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 2)
    }

    private var didSaveOutcome: Bool {
        store.state.outcomeLog.count > lastLoggedOutcomeCount
    }

    private func questSteps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quest steps")
                .font(.headline)
                .foregroundStyle(Color.openLARPInk)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.openLARPGreen)
                        .clipShape(Circle())

                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var progressStrip: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .stats, eyebrow: "Less cooked", title: "Goal readiness")

                HStack(alignment: .center, spacing: 14) {
                    ReadinessRings(value: store.state.progress.readiness.overall)
                    Spacer()

                    VStack(spacing: 8) {
                        SummaryTile(value: "\(store.state.progress.xp)", label: "XP", color: .openLARPBlue)
                        SummaryTile(value: "\(store.state.progress.completedQuestCount)", label: "Quests", color: .openLARPPurple)
                        SummaryTile(value: "\(store.state.progress.badges.count)", label: "Badges", color: .openLARPOrange)
                    }
                    .frame(maxWidth: 138)
                }

                ProgressView(value: Double(store.state.progress.readiness.overall), total: 100)
                    .tint(.openLARPGreen)
            }
        }
    }

    @ViewBuilder
    private var dailyAgentBrief: some View {
        if !store.state.needsGoalSetup {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(feature: .agent, eyebrow: "Agent brief", title: "While you are away")

                    Text(store.state.agentBrief.summary)
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let opportunity = store.state.agentBrief.opportunities.first {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: opportunity.type.systemImage)
                                .foregroundStyle(Color.openLARPPurple)
                                .frame(width: 30, height: 30)
                                .background(Color.openLARPPurple.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text("#\(opportunity.rank) \(opportunity.title)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.openLARPInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(opportunity.recommendedAction)
                                    .font(.caption)
                                    .foregroundStyle(Color.openLARPSoftInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(Color.openLARPBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct SkippedTodayCard: View {
    let content: SkippedTodayContent

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label(content.title, systemImage: "forward.end.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPCoral)

                Text(content.skippedQuestTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.bodyText)
                    .font(.body)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Pill(title: content.previousStreakText, systemImage: "flame", color: .openLARPCoral)
                    Pill(title: content.activeStreakText, systemImage: "flame.fill", color: .openLARPGreen)
                }

                Text(content.preservedProgressText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 9) {
                    Text(content.nextQuestTitle == nil ? "Track status" : "Tomorrow preview")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.openLARPGreen)
                        .textCase(.uppercase)

                    if let nextQuestTitle = content.nextQuestTitle {
                        Text(nextQuestTitle)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                            .fixedSize(horizontal: false, vertical: true)

                        if let nextQuestObjectiveText = content.nextQuestObjectiveText {
                            Text(nextQuestObjectiveText)
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let nextQuestMetaText = content.nextQuestMetaText {
                            Text(nextQuestMetaText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.openLARPSoftInk)
                        }
                    } else {
                        Text(content.nextQuestStatusText)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                    }

                    Label(content.unlockMessage, systemImage: content.nextQuestTitle == nil ? "checkmark.seal.fill" : "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.openLARPBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct MissedDayRecoveryCard: View {
    let content: MissedDayRecoveryContent
    let continueQuest: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label(content.title, systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPCoral)

                Text(content.missedDaysText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.bodyText)
                    .font(.body)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Pill(title: content.previousStreakText, systemImage: "flame", color: .openLARPCoral)
                    Pill(title: content.activeStreakText, systemImage: "flame.fill", color: .openLARPGreen)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Next quest")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.openLARPGreen)
                        .textCase(.uppercase)

                    Text(content.nextQuestTitle)
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(content.nextQuestObjectiveText)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(content.nextQuestMetaText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                }
                .padding(12)
                .background(Color.openLARPBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    continueQuest()
                } label: {
                    Label(content.primaryActionTitle, systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

private struct DoneForTodayCard: View {
    let content: TodayCompletionContent
    let attachmentURL: (ProofAttachment) -> URL
    let openProof: (ProofRecord) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Done for today", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPGreen)

                Text(content.completedQuestTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.resultSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Pill(title: content.xpText, systemImage: "bolt.fill", color: .openLARPYellow)
                    Pill(title: content.streakText, systemImage: "flame.fill", color: .openLARPCoral)
                }

                if let proofRecord = content.proofRecord {
                    Button {
                        openProof(proofRecord)
                    } label: {
                        ProofReceiptRow(
                            proof: proofRecord,
                            showsMetadata: true,
                            attachmentURL: attachmentURL
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Tomorrow preview")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.openLARPGreen)
                        .textCase(.uppercase)

                    if let nextQuestTitle = content.nextQuestTitle {
                        Text(nextQuestTitle)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                            .fixedSize(horizontal: false, vertical: true)

                        if let nextQuestObjectiveText = content.nextQuestObjectiveText {
                            Text(nextQuestObjectiveText)
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let nextQuestMetaText = content.nextQuestMetaText {
                            Text(nextQuestMetaText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.openLARPSoftInk)
                        }
                    } else {
                        Text(content.nextQuestStatusText)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                    }

                    Label(content.unlockMessage, systemImage: content.nextQuestTitle == nil ? "checkmark.seal.fill" : "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.openLARPBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct GoalSetupView: View {
    let store: OpenLARPStore
    let onGoalConfirmed: (CookedDiagnosticResultContent) -> Void
    @State private var currentStatus: CurrentStatus = .student
    @State private var targetRole = ""
    @State private var timeline = "30 days"
    @State private var background = ""
    @State private var existingProof = ""
    @State private var confidence = 3.0
    @State private var biggestBlocker = ""

    private var canSubmit: Bool {
        !targetRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OpenLARPHeroCard(
                feature: .path,
                eyebrow: "Setup",
                title: "Set your goal",
                subtitle: "Pick one honest target. OpenLARP will diagnose the gap and build the first proof sprint locally.",
                stat: "1/4"
            )

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Current status", selection: $currentStatus) {
                        ForEach(CurrentStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target role or field")
                            .font(.subheadline.weight(.semibold))
                        TextField("Entry-level product designer", text: $targetRole)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Target role")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Timeline")
                            .font(.subheadline.weight(.semibold))
                        TextField("30 days", text: $timeline)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Timeline")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current background")
                            .font(.subheadline.weight(.semibold))
                        TextField("Student, new grad, project work, current role...", text: $background, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Current background")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Existing proof")
                            .font(.subheadline.weight(.semibold))
                        TextField("Projects, coursework, links, shipped work...", text: $existingProof, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Existing proof")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confidence: \(Int(confidence)) / 5")
                            .font(.subheadline.weight(.semibold))
                        Slider(value: $confidence, in: 1...5, step: 1)
                            .tint(.openLARPGreen)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Biggest blocker")
                            .font(.subheadline.weight(.semibold))
                        TextField("What makes this goal feel risky?", text: $biggestBlocker, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Biggest blocker")
                    }
                }
            }

            Button {
                let goal = CareerGoal(
                    currentStatus: currentStatus,
                    targetRole: targetRole.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeline: timeline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "30 days" : timeline,
                    background: background,
                    existingProof: existingProof,
                    confidence: Int(confidence),
                    biggestBlocker: biggestBlocker
                )
                Task {
                    await store.confirmGoal(goal)
                    if let content = CookedDiagnosticResultContent(state: store.state) {
                        onGoalConfirmed(content)
                    }
                }
            } label: {
                Label(store.isGoalSetupRunning ? "Checking Goal" : "Check If I'm Cooked", systemImage: "flame.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit || store.isGoalSetupRunning)
            .opacity(canSubmit && !store.isGoalSetupRunning ? 1 : 0.5)
        }
    }
}

private struct DiagnosticResultBridgeView: View {
    let content: CookedDiagnosticResultContent
    let privateShareContent: CookedShareCardContent?
    let detailedShareContent: CookedShareCardContent?
    let startQuest: () -> Void
    let adjustGoal: () -> Void
    let recordCookedCardPrepared: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShareCard: CookedShareCardContent?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionHeader(feature: .cooked, eyebrow: content.eyebrow, title: "The roast report")

                                    Text(content.title)
                                        .font(.system(size: 40, weight: .black, design: .rounded))
                                        .foregroundStyle(Color.openLARPCoral)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()
                                ScoreRing(score: content.score)
                            }

                            HStack {
                                Pill(title: content.scoreText, systemImage: "flame.fill", color: .openLARPCoral)
                                Pill(title: content.readinessText, systemImage: "chart.line.uptrend.xyaxis", color: .openLARPGreen)
                            }

                            Text(content.mainGap)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.openLARPInk)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 9) {
                                ResultSignalRow(
                                    title: "Strongest signal",
                                    bodyText: content.strongestSignal,
                                    systemImage: "checkmark.seal.fill",
                                    color: .openLARPGreen
                                )
                                ResultSignalRow(
                                    title: "Fastest fix",
                                    bodyText: content.fastestFix,
                                    systemImage: "bolt.fill",
                                    color: .openLARPYellow
                                )
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(feature: .quest, eyebrow: "First move", title: "Start with proof")

                            Text(content.firstQuestTitle)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(content.firstQuestPurpose)
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)

                            Pill(title: content.firstQuestMetaText, systemImage: "timer", color: .openLARPGreen)

                            Button {
                                startQuest()
                                dismiss()
                            } label: {
                                Label(content.primaryActionTitle, systemImage: "play.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }

                    DisclosureGroup {
                        Text(content.explanationText)
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    } label: {
                        Label("Why am I cooked?", systemImage: "questionmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                    }
                    .padding(14)
                    .background(Color.openLARPPaper.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 10) {
                        Button {
                            selectedShareCard = privateShareContent
                        } label: {
                            Label(content.shareActionTitle, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(privateShareContent == nil)
                        .opacity(privateShareContent == nil ? 0.5 : 1)

                        Button {
                            adjustGoal()
                            dismiss()
                        } label: {
                            Label(content.adjustGoalActionTitle, systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Diagnostic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedShareCard) { shareContent in
                CookedShareCardSheet(
                    privateContent: shareContent,
                    detailedContent: detailedShareContent ?? shareContent,
                    onImagePrepared: recordCookedCardPrepared
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ResultSignalRow: View {
    let title: String
    let bodyText: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .textCase(.uppercase)

                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum ProofImageContentPolicy {
    static let allowedContentTypes = Set([
        "image/png",
        "image/jpeg",
        "image/heic",
        "image/heif"
    ])

    static func supportedContentType(for item: PhotosPickerItem) -> String? {
        item.supportedContentTypes
            .compactMap(\.preferredMIMEType)
            .first { allowedContentTypes.contains($0.lowercased()) }
    }
}

private struct ProofComposer: View {
    let store: OpenLARPStore
    @State private var kind: ProofKind = .proof
    @State private var text = ""
    @State private var link = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachments: [ProofAttachment] = []
    @State private var isSavingAttachments = false

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !attachments.isEmpty
    }

    init(store: OpenLARPStore, draft: ProofSubmission? = nil) {
        self.store = store
        _kind = State(initialValue: draft?.kind ?? .proof)
        _text = State(initialValue: draft?.text ?? "")
        _link = State(initialValue: draft?.link ?? "")
        _attachments = State(initialValue: draft?.attachments ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(feature: .proof, eyebrow: "Private proof", title: "Add evidence")

            Picker("Proof type", selection: $kind) {
                ForEach(ProofKind.allCases) { proofKind in
                    Text(proofKind.label).tag(proofKind)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $text)
                .frame(minHeight: 116)
                .padding(8)
                .background(Color.openLARPBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.openLARPGray.opacity(0.25))
                )
                .accessibilityLabel("Proof text")

            TextField("Optional proof link", text: $link)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            if kind == .proof {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Label("Add Screenshot or Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSavingAttachments)
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task {
                        await saveSelectedPhotos(newItems)
                    }
                }

                if isSavingAttachments {
                    Label("Saving proof images locally...", systemImage: "arrow.down.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                }

                if !attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved locally")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPGreen)
                            .textCase(.uppercase)

                        ProofAttachmentStrip(attachments: attachments) { attachment in
                            store.localURL(for: attachment)
                        }

                        ForEach(attachments) { attachment in
                            Button {
                                remove(attachment)
                            } label: {
                                Label("Remove \(attachment.originalFileName.isEmpty ? "image" : attachment.originalFileName)", systemImage: "xmark.circle")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color.openLARPCoral)
                        }
                    }
                }
            }

            Button {
                Task {
                    await store.checkProof(kind: kind, text: text, link: link, attachments: kind == .proof ? attachments : [])
                }
            } label: {
                Label(store.isProofChecking ? "Checking Proof" : "Check My Proof", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit || isSavingAttachments || store.isProofChecking)
            .opacity(canSubmit && !isSavingAttachments && !store.isProofChecking ? 1 : 0.5)

            Text(kind == .selfReport ? "Self-report keeps momentum, but earns less than real evidence." : "Links, screenshots, notes, and artifacts are saved locally as private evidence.")
                .font(.caption)
                .foregroundStyle(Color.openLARPSoftInk)
        }
    }

    @MainActor
    private func saveSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isSavingAttachments = true
        defer { isSavingAttachments = false }

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }
                guard let contentType = ProofImageContentPolicy.supportedContentType(for: item) else {
                    store.errorMessage = OpenLARPError.unsupportedProofImageType.localizedDescription
                    continue
                }
                let originalFileName = item.itemIdentifier ?? "selected-proof-image"
                let attachment = try store.saveProofImage(
                    data: data,
                    contentType: contentType,
                    originalFileName: originalFileName
                )
                if !attachments.contains(attachment) {
                    attachments.append(attachment)
                }
            } catch {
                store.errorMessage = OpenLARPError.attachmentStorageFailed.localizedDescription
            }
        }
        selectedPhotoItems = []
    }

    private func remove(_ attachment: ProofAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        store.deleteProofImage(attachment)
    }
}

private struct QualityResultCard: View {
    let result: QualityCheckResult
    let store: OpenLARPStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                feature: result.isAccepted ? .proof : .cooked,
                eyebrow: "Review result",
                title: result.label
            )

            Text(result.reason)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)

            Text("Coach note: \(result.improvement)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Pill(title: "+\(result.xpEarned) XP", systemImage: "bolt.fill", color: .openLARPYellow)
                Pill(title: "+\(result.readinessDelta) proof", systemImage: "chart.line.uptrend.xyaxis", color: .openLARPGreen)
                Pill(title: "\(result.qualityScore)/100", systemImage: "gauge", color: .openLARPCoral)
            }

            if result.isAccepted {
                Button {
                    store.claimPendingQualityResult()
                } label: {
                    Label("Claim XP", systemImage: "bolt.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    store.improvePendingProofDraft()
                } label: {
                    Label("Improve Proof", systemImage: "pencil")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    store.claimPendingQualityResult()
                } label: {
                    Label("Accept Lower XP", systemImage: "bolt.circle.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct ScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.openLARPCoral.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Color.openLARPCoral, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.openLARPInk)
        }
        .frame(width: 82, height: 82)
    }
}
