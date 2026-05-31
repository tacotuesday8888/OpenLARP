import SwiftUI

struct ProofArchiveView: View {
    let proofs: [ProofRecord]
    let attachmentURL: (ProofAttachment) -> URL

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProof: ProofRecord?

    private var content: ProofArchiveContent {
        ProofArchiveContent(proofs: proofs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("All proof receipts")
                    .font(.title3.weight(.black))
                    .foregroundStyle(Color.openLARPInk)

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
