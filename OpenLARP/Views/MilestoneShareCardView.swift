import SwiftUI

@MainActor
enum MilestoneShareCardImageRenderer {
    static func render(_ card: MilestoneShareCard) throws -> ShareCardImageExport {
        try ShareCardImageExport.render(
            MilestoneArtwork(card: card),
            size: CGSize(width: 360, height: 450),
            scale: 3,
            filename: MilestoneShareCard.filename,
            caption: card.caption,
            subject: card.title
        )
    }
}

struct MilestoneShareCardSheet: View {
    let card: MilestoneShareCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MilestoneSharePreview(card: card)
                .id(card.caption)
                .navigationTitle("Share milestone")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .accessibilityIdentifier("milestone.dismiss")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct MilestoneSharePreview: View {
    private enum Preparation {
        case preparing
        case ready(ShareCardImageExport, UIImage)
        case failed
    }

    let card: MilestoneShareCard
    @State private var preparation = Preparation.preparing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch preparation {
                case .preparing:
                    ProgressView("Preparing your card…")
                        .frame(maxWidth: .infinity)
                case .ready(let export, let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(card.title)
                        .accessibilityValue("\(card.category). \(card.detail)")
                        .accessibilityIdentifier("milestone.preview")

                    caption
                    ShareLink(
                        item: export.shareItem,
                        subject: Text(export.subject),
                        message: Text(export.caption),
                        preview: SharePreview(export.subject, image: Image(uiImage: image))
                    ) {
                        Label("Share image", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("milestone.shareImage")
                case .failed:
                    Text("The image couldn’t be prepared. You can still share the caption.")
                        .font(.body)
                        .foregroundStyle(Color.openLARPInk)
                    caption
                    ShareLink(item: card.caption) {
                        Label("Share text", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Color.openLARPBackground)
        .task {
            // Display the actual exported PNG so the preview matches the system share item.
            if let export = try? MilestoneShareCardImageRenderer.render(card),
               let image = UIImage(data: export.pngData) {
                preparation = .ready(export, image)
            } else {
                preparation = .failed
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Caption")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.openLARPSoftInk)
            Text(card.caption)
                .font(.body)
                .foregroundStyle(Color.openLARPInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MilestoneArtwork: View {
    let card: MilestoneShareCard

    private var accent: Color {
        switch card.kind {
        case .streak: .openLARPYellow
        case .badge: .openLARPMint
        case .outcome: .openLARPCyan
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                accent
                Circle()
                    .strokeBorder(Color.openLARPInk.opacity(0.11), lineWidth: 1)
                    .frame(width: 245, height: 245)
                Circle()
                    .strokeBorder(Color.openLARPInk.opacity(0.12), lineWidth: 1)
                    .frame(width: 300, height: 300)
                ZStack {
                    Circle()
                        .strokeBorder(Color.openLARPInk, style: StrokeStyle(lineWidth: 5, dash: [2, 8]))
                    Circle()
                        .fill(Color.openLARPInk)
                        .padding(10)
                    Image(systemName: card.systemImage)
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 122, height: 122)
            }
            .frame(height: 214)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text("OpenLARP")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Color.openLARPInk)
                    .padding(17)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(card.category.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(accent)
                Text(card.title)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(-1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
                Spacer(minLength: 6)
                Rectangle()
                    .fill(.white.opacity(0.28))
                    .frame(height: 1)
                Text(card.detail)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.openLARPInk)
        }
    }
}
