import SwiftUI

struct ProofArchiveView: View {
    let proofs: [ProofRecord]
    let attachmentURL: (ProofAttachment) -> URL
    let updateEvidenceCard: EvidenceCardUpdateAction?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProof: ProofRecord?

    private var content: ProofArchiveContent {
        ProofArchiveContent(proofs: proofs)
    }

    private var heroStat: String {
        let count = content.receipts.count
        return count == 1 ? "1 proof" : "\(count) proofs"
    }

    init(
        proofs: [ProofRecord],
        attachmentURL: @escaping (ProofAttachment) -> URL
    ) {
        self.proofs = proofs
        self.attachmentURL = attachmentURL
        updateEvidenceCard = nil
    }

    init(
        proofs: [ProofRecord],
        attachmentURL: @escaping (ProofAttachment) -> URL,
        updateEvidenceCard: @escaping EvidenceCardUpdateAction
    ) {
        self.proofs = proofs
        self.attachmentURL = attachmentURL
        self.updateEvidenceCard = updateEvidenceCard
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OpenLARPHeroCard(
                        feature: .proof,
                        eyebrow: "Proof",
                        title: "Evidence library",
                        subtitle: "Editable evidence cards backed by saved quest receipts.",
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
                if let updateEvidenceCard {
                    ProofDetailView(
                        proof: proof,
                        attachmentURL: attachmentURL,
                        updateEvidenceCard: updateEvidenceCard
                    )
                } else {
                    ProofDetailView(proof: proof, attachmentURL: attachmentURL)
                }
            }
        }
    }

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(feature: .proof, eyebrow: "Library", title: "Evidence and receipts")

                Text(content.countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.openLARPGreen)

                Text("Open a card to edit your notes and future use without changing its source or receipt history.")
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
                    Text("No evidence cards yet")
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
