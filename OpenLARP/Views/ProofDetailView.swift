import SwiftUI

typealias EvidenceCardUpdateAction = (UUID, String, String, String, String) -> Bool
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
    let updateEvidenceCard: EvidenceCardUpdateAction?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var evidenceCard: EvidenceCard
    @State private var showingEvidenceEditor = false

    init(
        proof: ProofRecord,
        attachmentURL: @escaping (ProofAttachment) -> URL
    ) {
        self.proof = proof
        self.attachmentURL = attachmentURL
        updateEvidenceCard = nil
        _evidenceCard = State(initialValue: proof.evidenceCard)
    }

    init(
        proof: ProofRecord,
        attachmentURL: @escaping (ProofAttachment) -> URL,
        updateEvidenceCard: @escaping EvidenceCardUpdateAction
    ) {
        self.proof = proof
        self.attachmentURL = attachmentURL
        self.updateEvidenceCard = updateEvidenceCard
        _evidenceCard = State(initialValue: proof.evidenceCard)
    }

    private var content: ProofDetailContent {
        ProofDetailContent(proof: proof)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    evidenceCardView
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
        .sheet(isPresented: $showingEvidenceEditor) {
            EvidenceCardEditorView(card: evidenceCard) { updatedCard in
                guard updateEvidenceCard?(
                    proof.id,
                    updatedCard.actionCompleted,
                    updatedCard.userNote,
                    updatedCard.privateNote,
                    updatedCard.potentialCareerUse
                ) == true else {
                    return false
                }
                evidenceCard = updatedCard
                return true
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
                        Text("Submission review")
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

                ProofDetailTextBlock(title: "Assessment", bodyText: content.reason)
                ProofDetailTextBlock(title: "Next improvement", bodyText: content.improvement)
                if let coachingSource = proof.quality?.coachingSource {
                    Label(coachingSource.disclosure, systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ProofDetailTextBlock(title: "Reviewed", bodyText: content.reviewedText)
                ProofDetailTextBlock(title: "Not inspected", bodyText: content.notInspectedText)
            }
        }
    }

    private var evidenceCardView: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Evidence card")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                        Text(evidenceCard.confirmationState.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(evidenceCard.confirmationState == .userConfirmed ? Color.openLARPGreen : Color.openLARPCoral)
                            .textCase(.uppercase)
                    }

                    Spacer()

                    if updateEvidenceCard != nil {
                        Button {
                            showingEvidenceEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }

                ProofDetailTextBlock(title: "Action completed", bodyText: evidenceCard.actionCompleted)
                ProofDetailTextBlock(title: "Gap affected", bodyText: evidenceCard.gap.title)
                ProofDetailTextBlock(title: "Potential future use", bodyText: evidenceCard.potentialCareerUse)

                if !evidenceCard.userNote.isEmpty {
                    ProofDetailTextBlock(title: "Your note", bodyText: evidenceCard.userNote)
                }
                if !evidenceCard.privateNote.isEmpty {
                    ProofDetailTextBlock(title: "Private note", bodyText: evidenceCard.privateNote)
                }

                Label(
                    "\(evidenceCard.source.label) · \(evidenceCard.provenance.label)",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
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

private struct EvidenceCardEditorView: View {
    let originalCard: EvidenceCard
    let save: (EvidenceCard) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var actionCompleted: String
    @State private var userNote: String
    @State private var privateNote: String
    @State private var potentialCareerUse: String

    init(card: EvidenceCard, save: @escaping (EvidenceCard) -> Bool) {
        originalCard = card
        self.save = save
        _actionCompleted = State(initialValue: card.actionCompleted)
        _userNote = State(initialValue: card.userNote)
        _privateNote = State(initialValue: card.privateNote)
        _potentialCareerUse = State(initialValue: card.potentialCareerUse)
    }

    private var canSave: Bool {
        !actionCompleted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            actionCompleted.count <= 4_000 &&
            userNote.count <= 2_000 &&
            privateNote.count <= 4_000 &&
            !potentialCareerUse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            potentialCareerUse.count <= 1_000
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Completed action") {
                    TextEditor(text: $actionCompleted)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Completed action")
                }

                Section("How you may use it") {
                    TextEditor(text: $potentialCareerUse)
                        .frame(minHeight: 90)
                        .accessibilityLabel("Potential career use")
                }

                Section("Your note") {
                    TextEditor(text: $userNote)
                        .frame(minHeight: 90)
                        .accessibilityLabel("Evidence note")
                }

                Section("Private note") {
                    TextEditor(text: $privateNote)
                        .frame(minHeight: 90)
                        .accessibilityLabel("Private evidence note")
                    Text("Kept on this device unless you explicitly enable private-evidence sync.")
                        .font(.caption)
                }

                Section("Recorded provenance") {
                    LabeledContent("Quest", value: originalCard.relatedQuestTitle)
                    LabeledContent("Gap", value: originalCard.gap.title)
                    LabeledContent("Source", value: originalCard.source.label)
                    LabeledContent("Confirmation", value: originalCard.confirmationState.label)
                }
            }
            .navigationTitle("Edit evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = originalCard
                        updated.actionCompleted = actionCompleted.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.userNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.privateNote = privateNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.potentialCareerUse = potentialCareerUse.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.updatedAt = Date()
                        if save(updated) {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
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
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                } else if !didFinishLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 190)
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
        .accessibilityValue(didFinishLoading && image == nil ? "Missing from this device" : attachment.originalFileName)
        .task(id: fileURL) {
            image = nil
            didFinishLoading = false
            image = await ProofAttachmentImageLoader.load(
                from: fileURL,
                maximumPixelDimension: 1_280
            )
            didFinishLoading = true
        }
    }
}
