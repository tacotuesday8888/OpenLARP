import SwiftUI

struct CookedShareCardSheet: View {
    let privateContent: CookedShareCardContent
    let detailedContent: CookedShareCardContent
    @Environment(\.dismiss) private var dismiss
    @State private var hideDetails = true
    @State private var imageExport: CookedShareCardImageExport?
    @State private var exportErrorMessage: String?
    @State private var isRenderingExport = false

    private var activeContent: CookedShareCardContent {
        hideDetails ? privateContent : detailedContent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CookedShareCardPreview(content: activeContent)

                    Toggle(isOn: $hideDetails) {
                        Label("Hide Details", systemImage: "eye.slash.fill")
                            .font(.headline)
                            .foregroundStyle(Color.openLARPInk)
                    }
                    .tint(.openLARPGreen)
                    .padding(14)
                    .background(Color.openLARPPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    shareAction

                    if let exportErrorMessage {
                        Text(exportErrorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.openLARPCoral)

                        ShareLink(item: activeContent.shareText) {
                            Label("Share Text Instead", systemImage: "text.quote")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label("Not Now", systemImage: "xmark.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color.openLARPBackground)
            .navigationTitle("Cooked Card")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: activeContent.id) {
                await renderExport()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var shareAction: some View {
        if isRenderingExport {
            Label("Preparing Image", systemImage: "photo")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(Color.openLARPBlueDark)
                .background(Color.openLARPBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let imageExport {
            ShareLink(
                item: imageExport.shareItem,
                subject: Text(imageExport.subject),
                message: Text(imageExport.caption),
                preview: SharePreview("OpenLARP cooked card")
            ) {
                Label("Share Image", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            Button {
                Task {
                    await renderExport()
                }
            } label: {
                Label("Prepare Image", systemImage: "photo")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @MainActor
    private func renderExport() async {
        isRenderingExport = true
        exportErrorMessage = nil
        imageExport = nil

        do {
            let payload = CookedShareCardExportPayload(content: activeContent)
            imageExport = try CookedShareCardImageExportService().render(payload: payload)
        } catch {
            exportErrorMessage = "Image export failed. The text-only fallback keeps private details hidden."
        }

        isRenderingExport = false
    }
}

struct CookedShareCardPreview: View {
    let content: CookedShareCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenLARP")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.openLARPGreen)
                        .textCase(.uppercase)

                    Text(content.title)
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color.openLARPInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                CookedShareCardScoreRing(score: content.score)
                    .frame(width: 72, height: 72)
            }

            Text(content.cookedLabel)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPCoral)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Pill(title: content.scoreText, systemImage: "flame.fill", color: .openLARPCoral)
                Pill(title: content.readinessText, systemImage: "chart.line.uptrend.xyaxis", color: .openLARPGreen)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(content.publicGapText)
                    .font(.headline)
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.recoveryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailText = content.detailText {
                    Text(detailText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color.openLARPBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(content.footerText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.openLARPSoftInk)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.openLARPGray.opacity(0.16))
        )
    }
}

private struct CookedShareCardScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.openLARPCoral.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Color.openLARPCoral, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.title2.weight(.black))
                .foregroundStyle(Color.openLARPInk)
        }
        .frame(width: 82, height: 82)
    }
}
