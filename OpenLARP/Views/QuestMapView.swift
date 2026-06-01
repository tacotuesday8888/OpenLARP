import SwiftUI

struct QuestMapView: View {
    let state: OpenLARPState
    let attachmentURL: (ProofAttachment) -> URL
    let viewToday: () -> Void
    @State private var selectedSheet: MapQuestSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .path,
                    eyebrow: "Week",
                    title: "Comeback Map",
                    subtitle: state.goal == nil ? "Set a goal first. The quest map appears after the cooked diagnostic." : "A short proof path keeps the goal visible without making the whole career feel impossible.",
                    stat: "\(state.progress.completedQuestCount)/7"
                )

                if state.plan.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No questline yet")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                            Text("The map is generated locally after goal setup and the Am I Cooked diagnostic.")
                                .font(.body)
                                .foregroundStyle(Color.openLARPSoftInk)
                            Button("View Today", action: viewToday)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(feature: .quest, eyebrow: "Proof Sprint", title: "Next 7 days")

                            SprintStrip(completed: state.progress.completedQuestCount)

                            HStack(spacing: 8) {
                                SummaryTile(value: "\(state.progress.streakCount)", label: "Streak", color: .openLARPCoral)
                                SummaryTile(value: "\(state.progress.completedQuestCount)/7", label: "Complete", color: .openLARPGreen)
                                SummaryTile(value: "\(state.progress.xp)", label: "XP", color: .openLARPBlue)
                            }

                            ProgressView(value: Double(state.progress.completedQuestCount), total: 7)
                                .tint(.openLARPGreen)

                            if let recovery = MissedDayRecoveryContent(state: state) {
                                Label("\(recovery.missedDaysText) Continue from Today to rebuild the active streak.", systemImage: "arrow.counterclockwise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.openLARPCoral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(state.plan) { quest in
                            QuestDayRow(
                                quest: quest,
                                openCompletedQuest: {
                                    selectedSheet = .completed(quest)
                                },
                                openPreviewQuest: {
                                    selectedSheet = .preview(quest)
                                }
                            )
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 88)
        }
        .background(Color.openLARPBackground)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSheet) { sheet in
            switch sheet {
            case .completed(let quest):
                CompletedQuestDetailView(
                    quest: quest,
                    proofs: state.progress.recentProof,
                    attachmentURL: attachmentURL
                )
            case .preview(let quest):
                QuestPreviewView(quest: quest, openToday: viewToday)
            }
        }
    }
}

private enum MapQuestSheet: Identifiable {
    case completed(Quest)
    case preview(Quest)

    var id: String {
        switch self {
        case .completed(let quest): "completed-\(quest.id.uuidString)"
        case .preview(let quest): "preview-\(quest.id.uuidString)"
        }
    }
}

private struct QuestDayRow: View {
    let quest: Quest
    let openCompletedQuest: () -> Void
    let openPreviewQuest: () -> Void

    var body: some View {
        Group {
            if quest.status == .completed {
                Button(action: openCompletedQuest) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else if quest.status == .available || quest.status == .inProgress {
                Button(action: openPreviewQuest) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .opacity(quest.status == .locked ? 0.72 : 1)
        .accessibilityHint(accessibilityHintText)
    }

    private var rowContent: some View {
        Card {
            HStack(spacing: 14) {
                dayBadge

                VStack(alignment: .leading, spacing: 8) {
                    titleRow

                    Text(quest.gap.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)

                    HStack {
                        Text("+\(quest.xpReward) XP")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPGreen)

                        Spacer()

                        if quest.status == .completed {
                            Label("Details", systemImage: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.openLARPGreen)
                        } else if quest.status == .available || quest.status == .inProgress {
                            Label("Preview", systemImage: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.openLARPGreen)
                        }
                    }
                }
            }
        }
    }

    private var dayBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [quest.status.color.opacity(0.22), quest.status.color.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(quest.status.color.opacity(0.30), lineWidth: 2)
                )
            Text("\(quest.day)")
                .font(.headline.weight(.black))
                .foregroundStyle(quest.status.color)
        }
        .frame(width: 48, height: 48)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(quest.title)
                .font(.headline)
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(quest.status.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(quest.status.color)
        }
    }

    private var accessibilityHintText: String {
        switch quest.status {
        case .completed:
            "Opens completed quest details"
        case .available, .inProgress:
            "Opens quest preview"
        case .locked, .skipped:
            ""
        }
    }
}
