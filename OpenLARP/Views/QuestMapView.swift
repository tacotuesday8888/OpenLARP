import SwiftUI

struct QuestMapView: View {
    let state: OpenLARPState
    let attachmentURL: (ProofAttachment) -> URL
    let updateEvidenceCard: EvidenceCardUpdateAction
    let viewToday: () -> Void
    @State private var selectedSheet: MapQuestSheet?

    private var journeyContent: QuestJourneyContent {
        QuestJourneyContent(plan: state.plan, sprint: state.activeSprint)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OpenLARPHeroCard(
                    feature: .path,
                    eyebrow: "14 days",
                    title: "Comeback Map",
                    subtitle: state.goal == nil ? "Set a goal first. The quest map appears after the cooked diagnostic." : "Chapter One builds real proof. Chapter Two adapts days 8–14 from the first checkpoint.",
                    stat: "\(state.currentSprintCompletedQuestCount)/14"
                )

                if state.plan.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(state.needsMissionApproval ? "Mission approval comes first" : "No questline yet")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                            Text(state.needsMissionApproval
                                 ? "Review and approve the editable mission on Today. OpenLARP will create the first chapter only after that decision."
                                 : "The map appears after goal setup, the Am I Cooked diagnostic, and mission approval.")
                                .font(.body)
                                .foregroundStyle(Color.openLARPSoftInk)
                            Button("View Today", action: viewToday)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(feature: .quest, eyebrow: "Proof Sprint", title: "Two focused chapters")

                            SprintStrip(completed: state.currentSprintCompletedQuestCount, total: 14)

                            HStack(spacing: 8) {
                                SummaryTile(value: "\(state.progress.streakCount)", label: "Streak", color: .openLARPCoral)
                                SummaryTile(value: "\(state.currentSprintCompletedQuestCount)/14", label: "Complete", color: .openLARPGreen)
                                SummaryTile(value: "\(state.progress.xp)", label: "XP", color: .openLARPBlue)
                            }

                            ProgressView(value: Double(state.currentSprintCompletedQuestCount), total: 14)
                                .tint(.openLARPGreen)

                            if let recovery = MissedDayRecoveryContent(state: state) {
                                Label("\(recovery.missedDaysText) Continue from Today to rebuild the active streak.", systemImage: "arrow.counterclockwise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.openLARPAttentionText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(spacing: 24) {
                        ForEach(journeyContent.chapters) { chapter in
                            QuestJourneyChapterSection(
                                chapter: chapter,
                                openCompletedQuest: { quest in
                                    selectedSheet = .completed(quest)
                                },
                                openPreviewQuest: { quest in
                                    selectedSheet = .preview(quest)
                                },
                                openReview: viewToday
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
                    attachmentURL: attachmentURL,
                    updateEvidenceCard: updateEvidenceCard
                )
            case .preview(let quest):
                QuestPreviewView(quest: quest, openToday: viewToday)
            }
        }
    }
}

private struct QuestJourneyChapterSection: View {
    let chapter: QuestJourneyChapter
    let openCompletedQuest: (Quest) -> Void
    let openPreviewQuest: (Quest) -> Void
    let openReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestJourneyChapterHeader(chapter: chapter)

            if let lockedExplanation = chapter.lockedExplanation {
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.openLARPBlueDark)
                            .frame(width: 32, height: 32)
                            .background(Color.openLARPBlue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adaptive chapter")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.openLARPInk)
                            Text(lockedExplanation)
                                .font(.subheadline)
                                .foregroundStyle(Color.openLARPSoftInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                ForEach(chapter.quests) { quest in
                    QuestDayRow(
                        quest: quest,
                        openCompletedQuest: { openCompletedQuest(quest) },
                        openPreviewQuest: { openPreviewQuest(quest) }
                    )
                }
            }

            QuestJourneyMilestoneCard(milestone: chapter.milestone, openReview: openReview)
        }
    }
}

private struct QuestJourneyChapterHeader: View {
    let chapter: QuestJourneyChapter

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Chapter \(chapter.number) · \(chapter.questRangeText)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .textCase(.uppercase)

                    Spacer()

                    Text(chapter.status.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(chapter.status.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(chapter.status.color.opacity(0.12))
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title)
                        .font(.title3.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                    Text(chapter.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !chapter.focusGaps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(chapter.focusGaps) { gap in
                                Label(gap.title, systemImage: "scope")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.openLARPSuccessText)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(Color.openLARPGreen.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    ProgressView(
                        value: Double(chapter.completedQuestCount),
                        total: Double(chapter.totalQuestCount)
                    )
                    .tint(chapter.status.color)

                    Text("\(chapter.completedQuestCount)/\(chapter.totalQuestCount) actions")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.openLARPSoftInk)
                }
            }
        }
    }
}

private struct QuestJourneyMilestoneCard: View {
    let milestone: QuestJourneyMilestone
    let openReview: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: milestone.state.systemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(milestone.state.color)
                        .frame(width: 38, height: 38)
                        .background(milestone.state.color.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(milestone.title)
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                        Text(milestone.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if milestone.state == .ready {
                    Button("Open review", action: openReview)
                        .buttonStyle(PrimaryButtonStyle())
                }
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

                    Text(quest.purpose)
                        .font(.subheadline)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Label(quest.timeEstimate, systemImage: "timer")
                        Label(quest.difficulty, systemImage: "gauge.with.dots.needle.50percent")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)

                    HStack {
                        Label(quest.gap.title, systemImage: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.openLARPBlueDark)

                        Text("+\(quest.xpReward) XP")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPSuccessText)

                        Spacer()

                        if quest.status == .completed {
                            Label("Details", systemImage: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.openLARPSuccessText)
                        } else if quest.status == .available || quest.status == .inProgress {
                            Label("Preview", systemImage: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.openLARPSuccessText)
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

private extension QuestJourneyChapterStatus {
    var label: String {
        switch self {
        case .active: "In progress"
        case .locked: "Adapts later"
        case .reviewReady: "Review ready"
        case .complete: "Complete"
        }
    }

    var color: Color {
        switch self {
        case .active: .openLARPCoral
        case .locked: .openLARPGray
        case .reviewReady: .openLARPYellow
        case .complete: .openLARPGreen
        }
    }
}

private extension QuestJourneyMilestoneState {
    var color: Color {
        switch self {
        case .locked: .openLARPGray
        case .ready: .openLARPYellow
        case .complete: .openLARPGreen
        }
    }

    var systemImage: String {
        switch self {
        case .locked: "lock.fill"
        case .ready: "flag.checkered"
        case .complete: "checkmark.seal.fill"
        }
    }
}
