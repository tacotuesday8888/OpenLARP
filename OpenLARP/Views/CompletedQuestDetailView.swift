import SwiftUI

struct CompletedQuestDetailView: View {
    let quest: Quest
    let proofs: [ProofRecord]
    let attachmentURL: (ProofAttachment) -> URL

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProof: ProofRecord?

    private var content: CompletedQuestDetailContent {
        CompletedQuestDetailContent(quest: quest, proofs: proofs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    questCard
                    proofCard
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Completed quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedProof) { proof in
                ProofDetailView(proof: proof, attachmentURL: attachmentURL)
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

                CompletedQuestDetailTextBlock(title: "Objective", bodyText: content.objectiveText)
                if !content.stepTexts.isEmpty {
                    CompletedQuestStepsBlock(steps: content.stepTexts)
                }
                CompletedQuestDetailTextBlock(title: "Proof required", bodyText: content.proofRequiredText)

                HStack(spacing: 10) {
                    CompletedQuestMetric(title: "Gap", value: content.gapText, systemImage: "target")
                    CompletedQuestMetric(title: "Reward", value: content.xpRewardText, systemImage: "sparkles")
                }
            }
        }
    }

    private var proofCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Attached proof")
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)

                if let proof = content.savedProof {
                    Button {
                        selectedProof = proof
                    } label: {
                        ProofReceiptRow(
                            proof: proof,
                            showsMetadata: true,
                            attachmentURL: attachmentURL
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(content.noProofMessage)
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CompletedQuestMetric: View {
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

private struct CompletedQuestDetailTextBlock: View {
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

private struct CompletedQuestStepsBlock: View {
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
