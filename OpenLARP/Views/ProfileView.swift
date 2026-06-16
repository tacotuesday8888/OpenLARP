import SwiftUI

struct ProfileView: View {
    let store: OpenLARPStore
    @State private var showingResetConfirmation = false
    @State private var selectedProof: ProofRecord?
    @State private var showingProofArchive = false
    @State private var outcomeSheetDestination: OutcomeSheetDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .profile,
                    eyebrow: "Me",
                    title: "Career Hub",
                    subtitle: store.state.goal?.currentStatus.rawValue ?? "Set a goal to start the first proof sprint.",
                    stat: "L\(max(1, store.state.progress.completedQuestCount + 1))"
                )

                careerSummaryCard
                accountProfileCard
                careerGraphSetupStatusCard
                activeGoalCard
                recentOutcomesCard
                streakCard
                privacyCard
                badgeCard
                proofCard
                rulesCard
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProof) { proof in
            ProofDetailView(proof: proof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .sheet(isPresented: $showingProofArchive) {
            ProofArchiveView(proofs: store.state.progress.recentProof) { attachment in
                store.localURL(for: attachment)
            }
        }
        .sheet(item: $outcomeSheetDestination) { destination in
            outcomeSheet(for: destination)
        }
        .confirmationDialog(
            "Change goal?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Goal And Local Plan", role: .destructive) {
                store.resetGoal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local diagnostic and questline so you can set a new target.")
        }
    }

    @ViewBuilder
    private func outcomeSheet(for destination: OutcomeSheetDestination) -> some View {
        switch destination {
        case .log:
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
        case .detail(let outcome):
            OutcomeDetailView(
                outcome: outcome,
                isEditable: !store.state.needsGoalSetup,
                edit: {
                    outcomeSheetDestination = .edit(outcome)
                },
                delete: {
                    store.deleteOutcome(id: outcome.id)
                }
            )
        case .edit(let outcome):
            OutcomeLogSheet(outcome: outcome) { kind, title, organizationName, note, occurredAt, isPrivate in
                store.updateOutcome(
                    id: outcome.id,
                    kind: kind,
                    title: title,
                    organizationName: organizationName,
                    note: note,
                    occurredAt: occurredAt,
                    isPrivate: isPrivate
                )
            }
        }
    }

    private var careerSummaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .quest, eyebrow: "Sprint", title: "Momentum")

                SprintStrip(completed: store.state.progress.completedQuestCount)

                HStack(spacing: 8) {
                    SummaryTile(value: "\(store.state.progress.proofCount)", label: "Proof", color: .openLARPGreen)
                    SummaryTile(value: "\(store.state.progress.streakCount)", label: "Streak", color: .openLARPCoral)
                    SummaryTile(value: "\(store.state.progress.readiness.overall)%", label: "Ready", color: .openLARPBlue)
                }
            }
        }
    }

    private var accountProfileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .profile, eyebrow: "Account-ready", title: "User profile")

                if let profile = store.state.userProfile {
                    HStack(spacing: 8) {
                        SummaryTile(value: profile.segment.rawValue, label: "Segment", color: .openLARPBlue)
                        SummaryTile(value: "\(profile.minutesPerDay)m", label: "Daily", color: .openLARPGreen)
                    }

                    ProfileDetailRow(title: "Display name", value: profile.displayName)
                    ProfileDetailRow(title: "Memory mode", value: profile.privacy.memoryMode.label)
                    ProfileDetailRow(title: "Account sync", value: profile.accountID == nil ? "Not connected yet" : "Linked")
                    ProfileDetailRow(title: "Profile record", value: "Saved on this device")
                } else {
                    Text("A local user profile is created after goal setup and can be linked to account sync later.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var careerGraphSetupStatusCard: some View {
        let content = CareerGraphSetupStatusContent(
            state: store.state,
            session: BackendUserSession.localOnly(for: store.state)
        )

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .agent, eyebrow: "Account-ready", title: content.summaryTitle)

                Text(content.summarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(content.nextActionTitle, systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPBlue)
                    Pill(title: "Local only", systemImage: "lock.fill", color: .openLARPGreen)
                }

                Text(content.nextActionDetail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(content.rows) { row in
                        CareerGraphStatusRow(row: row)
                    }
                }

                if let preview = store.careerGraphSyncPreview {
                    CareerGraphSyncPreviewSummary(content: CareerGraphSyncPreviewContent(preview: preview))
                }

                Button {
                    Task {
                        await store.prepareCareerGraphSyncPreview()
                    }
                } label: {
                    if store.isPreparingCareerGraphSyncPreview {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Building Preview")
                        }
                    } else {
                        Label("Preview Saved Career Graph", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isPreparingCareerGraphSyncPreview || store.state.needsGoalSetup)
                .opacity(store.state.needsGoalSetup ? 0.45 : 1)

                Text(store.state.needsGoalSetup
                    ? "Set a career goal before previewing your career graph."
                    : "This prepares a local preview only. It does not upload or sync anything.")
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var recentOutcomesCard: some View {
        let content = OutcomeLogContent(outcomes: store.state.outcomeLog)
        if !content.outcomes.isEmpty {
            OutcomeLogCard(
                content: content,
                feature: .profile,
                eyebrow: "Private history",
                title: "Recent outcomes",
                recentLimit: 2,
                availability: store.state.needsGoalSetup
                    ? .readOnly("Set a new career goal before logging more outcomes. Existing outcomes stay saved as private history.")
                    : .available
            ) { outcome in
                outcomeSheetDestination = .detail(outcome)
            } logOutcome: {
                outcomeSheetDestination = .log
            }
        }
    }

    private var activeGoalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .profile, eyebrow: "Goal", title: "Active goal")

                if let goal = store.state.goal {
                    Text(goal.targetRole)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Pill(title: goal.timeline, systemImage: "calendar", color: .openLARPCoral)
                        Pill(title: "\(store.state.progress.proofCount) proof items", systemImage: "checkmark.seal", color: .openLARPGreen)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let targetRole = store.state.targetRoles.first {
                            ProfileDetailRow(title: "Role family", value: targetRole.roleFamily.rawValue)
                            ProfileDetailRow(title: "Seniority", value: targetRole.seniority.rawValue)
                            ProfileDetailRow(title: "Keywords", value: targetRole.keywords.joined(separator: ", "))
                        }
                        ProfileDetailRow(title: "Background", value: goal.background.isEmpty ? "Not provided yet" : goal.background)
                        ProfileDetailRow(title: "Existing proof", value: goal.existingProof.isEmpty ? "Thin or not provided yet" : goal.existingProof)
                        ProfileDetailRow(title: "Biggest blocker", value: goal.biggestBlocker.isEmpty ? "Not provided yet" : goal.biggestBlocker)
                    }

                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Change goal", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Text("Set a career target from Today to unlock the diagnostic, quest map, and progress baseline.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                }
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(feature: .privacy, eyebrow: "Private by default", title: "Memory and sharing")

                if store.state.userProfile == nil {
                    Text("Set a goal first to create local privacy controls for memory and sharing.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PrivacyToggleRow(
                        title: "Long-term memory",
                        detail: "Keep local context on this device.",
                        isOn: memoryBinding
                    )
                    PrivacyToggleRow(
                        title: "Shareable wins",
                        detail: "Allow proof wins to be shared later.",
                        isOn: shareWinsBinding
                    )

                    Text(memoryEnabled ? "Local memory is on for this device. Real cloud memory is not built yet." : "Memory is off for future sensitive chats on this device.")
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("External actions always require approval.", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var memoryEnabled: Bool {
        store.state.userProfile?.privacy.memoryMode != .off
    }

    private var memoryBinding: Binding<Bool> {
        Binding(
            get: { memoryEnabled },
            set: { isOn in
                store.updateProfilePrivacy(memoryMode: isOn ? .localOnly : .off)
            }
        )
    }

    private var shareWinsBinding: Binding<Bool> {
        Binding(
            get: { store.state.userProfile?.privacy.shareWins ?? false },
            set: { isOn in
                store.updateProfilePrivacy(shareWins: isOn)
            }
        )
    }

    @ViewBuilder
    private var streakCard: some View {
        if !store.state.needsGoalSetup {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(feature: .recovery, eyebrow: "Not over", title: "Active streak")

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(store.state.progress.streakCount)")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(Color.openLARPCoral)

                        Text(store.state.progress.streakCount == 1 ? "day" : "days")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }

                    if let recovery = MissedDayRecoveryContent(state: store.state) {
                        Text("\(recovery.previousStreakText). \(recovery.missedDaysText) Continue from Today to rebuild the active streak.")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let skipped = SkippedTodayContent(state: store.state) {
                        Text("\(skipped.previousStreakText). \(skipped.unlockMessage)")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("This is the current live streak for the local quest track.")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var badgeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Proof wins", title: "Badges")

                if store.state.progress.badges.isEmpty {
                    Text("Lock a goal and submit proof to earn the first badges.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    FlowLayout(items: store.state.progress.badges.map(\.rawValue))
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(feature: .proof, eyebrow: "Evidence bank", title: "Proof receipts")

                Button {
                    showingProofArchive = true
                } label: {
                    Label("Proof archive", systemImage: "archivebox")
                }
                .buttonStyle(SecondaryButtonStyle())

                if store.state.progress.recentProof.isEmpty {
                    Text("Recent proof will show up here after you complete a quest.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                } else {
                    ForEach(store.state.progress.recentProof.prefix(3)) { proof in
                        Button {
                            selectedProof = proof
                        } label: {
                            ProofReceiptRow(proof: proof) { attachment in
                                store.localURL(for: attachment)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(feature: .privacy, eyebrow: "Rules", title: "Product guardrails")

                Label("Package real experience aggressively.", systemImage: "sparkles")
                Label("Never invent employers, schools, certificates, titles, dates, projects, or ownership.", systemImage: "checkmark.shield")
                Label("The agent drafts. You approve external actions.", systemImage: "hand.tap")
            }
            .font(.subheadline)
            .foregroundStyle(Color.openLARPSoftInk)
        }
    }
}

private struct CareerGraphStatusRow: View {
    let row: CareerGraphSetupStatusRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.systemImage)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(statusColor)
                .frame(width: 25, height: 25)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Text(row.value)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        if row.isComplete {
            return .openLARPGreen
        }

        let normalized = row.value.lowercased()
        if normalized.contains("local") || normalized.contains("mock") {
            return .openLARPPurple
        }

        if normalized.contains("missing") || normalized.contains("not connected") {
            return .openLARPCoral
        }

        return .openLARPSoftInk
    }
}

private struct CareerGraphSyncPreviewSummary: View {
    let content: CareerGraphSyncPreviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Label(content.title, systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.openLARPGreen)

                Text(content.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(content.rows) { row in
                    CareerGraphStatusRow(row: row)
                }
            }

            Text(content.nextStep)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PrivacyToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.openLARPInk)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(.openLARPBlue)
        }
        .padding(12)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProfileDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.openLARPGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.openLARPGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
