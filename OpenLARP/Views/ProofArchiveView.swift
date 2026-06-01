import SwiftUI

struct ProofArchiveView: View {
    let proofs: [ProofRecord]
    let attachmentURL: (ProofAttachment) -> URL

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProof: ProofRecord?

    private var content: ProofArchiveContent {
        ProofArchiveContent(proofs: proofs)
    }

    private var heroStat: String {
        let count = content.receipts.count
        return count == 1 ? "1 proof" : "\(count) proofs"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OpenLARPHeroCard(
                        feature: .proof,
                        eyebrow: "Proof",
                        title: "Evidence bank",
                        subtitle: "Saved receipts from completed quests, newest first.",
                        stat: heroStat
                    )
                    headerCard
                    archiveContent
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Proof archive")
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

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(feature: .proof, eyebrow: "Archive", title: "All proof receipts")

                Text(content.countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.openLARPGreen)

                Text("Saved quest proof, newest first.")
                    .font(.body)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var archiveContent: some View {
        if content.receipts.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No proof receipts yet")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)

                    Text(content.emptyMessage)
                        .font(.body)
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(content.receipts) { proof in
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

                        if proof.id != content.receipts.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
