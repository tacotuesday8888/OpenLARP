import SwiftUI
import UIKit

struct ProofReceiptRow: View {
    let proof: ProofRecord
    let showsMetadata: Bool
    let attachmentURL: (ProofAttachment) -> URL

    init(
        proof: ProofRecord,
        showsMetadata: Bool = false,
        attachmentURL: @escaping (ProofAttachment) -> URL
    ) {
        self.proof = proof
        self.showsMetadata = showsMetadata
        self.attachmentURL = attachmentURL
    }

    private var content: ProofDetailContent {
        ProofDetailContent(proof: proof)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(content.questTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsMetadata {
                        HStack(spacing: 8) {
                            Label(content.proofType, systemImage: "checkmark.seal")
                            Label(submittedDateText, systemImage: "calendar")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                    }

                    HStack(spacing: 8) {
                        Text(content.qualityLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle((proof.quality?.isAccepted ?? false) ? Color.openLARPGreen : Color.openLARPCoral)

                        Text(content.xpText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.openLARPSoftInk)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .padding(.top, 3)
            }

            if let proofText = content.proofText {
                Text(proofText)
                    .font(.caption)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .lineLimit(3)
            }

            if let proofLinkText = content.proofLinkText {
                Label(proofLinkText, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(Color.openLARPGreen)
                    .lineLimit(1)
            }

            if !proof.attachments.isEmpty {
                Text(proof.attachmentSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)

                ProofAttachmentStrip(
                    attachments: proof.attachments,
                    attachmentURL: attachmentURL
                )
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens proof receipt details")
    }

    private var submittedDateText: String {
        content.submittedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct ProofDetailView: View {
    let proof: ProofRecord
    let attachmentURL: (ProofAttachment) -> URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var content: ProofDetailContent {
        ProofDetailContent(proof: proof)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    qualityCard
                    proofTextCard
                    proofLinkCard
                    attachmentsCard
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Proof receipt")
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

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text(content.questTitle)
                    .font(.title3.weight(.black))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    ProofDetailMetric(title: "Type", value: content.proofType, systemImage: "checkmark.seal")
                    ProofDetailMetric(title: "Submitted", value: submittedDateText, systemImage: "calendar")
                }
            }
        }
    }

    private var qualityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Quality check")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)

                        Text(content.qualityLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle((proof.quality?.isAccepted ?? false) ? Color.openLARPGreen : Color.openLARPCoral)
                    }

                    Spacer()

                    Text(content.xpText)
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color.openLARPGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.openLARPGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                ProofDetailTextBlock(title: "Why it counted", bodyText: content.reason)
                ProofDetailTextBlock(title: "Next improvement", bodyText: content.improvement)
            }
        }
    }

    @ViewBuilder
    private var proofTextCard: some View {
        if let proofText = content.proofText {
            Card {
                ProofDetailTextBlock(title: "Proof text", bodyText: proofText)
            }
        }
    }

    @ViewBuilder
    private var proofLinkCard: some View {
        if let proofLinkText = content.proofLinkText {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Proof link")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)

                    if let proofURL = content.proofURL {
                        Button {
                            openURL(proofURL)
                        } label: {
                            Label(proofLinkText, systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Label(proofLinkText, systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(Color.openLARPSoftInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Saved as text because it is not an openable web URL.")
                            .font(.caption)
                            .foregroundStyle(Color.openLARPSoftInk)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentsCard: some View {
        if !proof.attachments.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Screenshot and photo proof")
                        .font(.headline)
                        .foregroundStyle(Color.openLARPInk)

                    ForEach(proof.attachments) { attachment in
                        ProofAttachmentLargePreview(
                            attachment: attachment,
                            fileURL: attachmentURL(attachment)
                        )
                    }
                }
            }
        }
    }

    private var submittedDateText: String {
        content.submittedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ProofDetailMetric: View {
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
    }
}

private struct ProofDetailTextBlock: View {
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

private struct ProofAttachmentLargePreview: View {
    let attachment: ProofAttachment
    let fileURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                if let image = UIImage(contentsOfFile: fileURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("Image missing from this device")
                            .font(.subheadline.weight(.bold))
                        Text("The receipt metadata is still saved locally.")
                            .font(.caption)
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.openLARPSoftInk)
                    .frame(maxWidth: .infinity, minHeight: 190)
                }
            }
            .background(Color.openLARPBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text(attachment.originalFileName.isEmpty ? attachment.fileName : attachment.originalFileName)
                    .lineLimit(1)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
            }
            .font(.caption)
            .foregroundStyle(Color.openLARPSoftInk)
        }
        .accessibilityLabel("Proof image preview")
    }
}
