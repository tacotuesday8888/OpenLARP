import SwiftUI

struct QuestPreviewView: View {
    let quest: Quest
    let openToday: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var content: QuestPreviewContent {
        QuestPreviewContent(quest: quest)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    questCard
                    if content.canOpenToday, let todayCTATitle = content.todayCTATitle {
                        Button {
                            dismiss()
                            openToday()
                        } label: {
                            Label(
                                todayCTATitle,
                                systemImage: quest.status == .available ? "play.fill" : "arrow.right.circle.fill"
                            )
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Quest preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var questCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(content.dayText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPGreen)
                            .textCase(.uppercase)

                        Text(content.title)
                            .font(.title3.weight(.black))
                            .foregroundStyle(Color.openLARPInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(content.statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(quest.status.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(quest.status.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                QuestPreviewTextBlock(title: "Objective", bodyText: content.objectiveText)

                if !content.stepTexts.isEmpty {
                    QuestPreviewStepsBlock(steps: content.stepTexts)
                }

                QuestPreviewTextBlock(title: "Proof required", bodyText: content.proofRequiredText)

                HStack(spacing: 10) {
                    QuestPreviewMetric(title: "Time", value: content.timeEstimateText, systemImage: "timer")
                    QuestPreviewMetric(title: "Difficulty", value: content.difficultyText, systemImage: "gauge.with.dots.needle.50percent")
                }

                HStack(spacing: 10) {
                    QuestPreviewMetric(title: "Gap", value: content.gapText, systemImage: "target")
                    QuestPreviewMetric(title: "Reward", value: content.xpRewardText, systemImage: "sparkles")
                }
            }
        }
    }
}

private struct QuestPreviewMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.openLARPBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct QuestPreviewTextBlock: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct QuestPreviewStepsBlock: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action steps")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPGreen)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.openLARPGreen)
                            .frame(width: 20, alignment: .trailing)

                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
