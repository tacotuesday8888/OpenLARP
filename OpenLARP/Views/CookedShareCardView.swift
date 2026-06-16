import SwiftUI

@MainActor
struct CookedShareCardImageExportService {
    let scale: CGFloat

    init(scale: CGFloat = 1) {
        self.scale = scale
    }

    func render(payload: CookedShareCardExportPayload) throws -> CookedShareCardImageExport {
        let exportView = CookedShareCardExportImage(payload: payload)
            .frame(width: payload.pixelSize.width, height: payload.pixelSize.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: exportView)
        renderer.proposedSize = ProposedViewSize(payload.pixelSize)
        renderer.scale = scale

        guard let image = renderer.uiImage else {
            throw CookedShareCardExportError.renderingFailed
        }
        guard let data = image.pngData(), !data.isEmpty else {
            throw CookedShareCardExportError.emptyPNGData
        }

        return CookedShareCardImageExport(
            pngData: data,
            filename: payload.suggestedFilename,
            caption: payload.caption,
            subject: payload.subject,
            pixelSize: image.size
        )
    }
}

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

private struct CookedShareCardExportImage: View {
    let payload: CookedShareCardExportPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 52) {
            header

            Text(payload.cookedLabel)
                .font(.system(size: 106, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPCoral)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                exportPill(payload.scoreText, systemImage: "flame.fill", color: .openLARPCoral)
                exportPill(payload.readinessText, systemImage: "chart.line.uptrend.xyaxis", color: .openLARPGreen)
            }

            VStack(alignment: .leading, spacing: 24) {
                Text(payload.publicGapText)
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Color.openLARPInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(payload.recoveryText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.openLARPSoftInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let detailText = payload.detailText {
                    Text(detailText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.openLARPSoftInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.openLARPPaper)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Spacer(minLength: 0)

            Text(payload.footerText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.openLARPSoftInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(68)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.openLARPBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 18) {
                Text("OpenLARP")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.openLARPGreen)
                    .textCase(.uppercase)

                Text(payload.title)
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(Color.openLARPInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.62)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            exportScoreRing
        }
    }

    private var exportScoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color.openLARPCoral.opacity(0.18), lineWidth: 20)
            Circle()
                .trim(from: 0, to: CGFloat(payload.score) / 100)
                .stroke(Color.openLARPCoral, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(payload.score)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Color.openLARPInk)
        }
        .frame(width: 154, height: 154)
        .accessibilityHidden(true)
    }

    private func exportPill(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 27, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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
