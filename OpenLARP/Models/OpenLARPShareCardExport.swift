import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CookedShareCardExportPayload: Equatable {
    static let defaultPixelSize = CGSize(width: 1080, height: 1350)

    let title: String
    let targetRole: String
    let cookedLabel: String
    let score: Int
    let scoreText: String
    let readinessText: String
    let publicGapText: String
    let recoveryText: String
    let detailText: String?
    let footerText: String
    let caption: String
    let subject: String
    let suggestedFilename: String
    let contentType: String
    let fileExtension: String
    let pixelSize: CGSize

    var searchableText: String {
        [
            title,
            targetRole,
            cookedLabel,
            "\(score)",
            scoreText,
            readinessText,
            publicGapText,
            recoveryText,
            detailText,
            footerText,
            caption,
            subject,
            suggestedFilename,
            contentType,
            fileExtension
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    init(content: CookedShareCardContent) {
        title = content.title
        targetRole = content.targetRole
        cookedLabel = content.cookedLabel
        score = content.score
        scoreText = content.scoreText
        readinessText = content.readinessText
        publicGapText = content.publicGapText
        recoveryText = content.recoveryText
        detailText = content.detailText
        footerText = content.footerText
        caption = content.shareText
        subject = "OpenLARP cooked card"
        suggestedFilename = "openlarp-cooked-card.png"
        contentType = "image/png"
        fileExtension = "png"
        pixelSize = Self.defaultPixelSize
    }
}

struct CookedShareCardImageExport: Equatable {
    let pngData: Data
    let filename: String
    let caption: String
    let subject: String
    let pixelSize: CGSize
    let contentType = "image/png"
    let fileExtension = "png"

    var shareItem: CookedShareCardImageShareItem {
        CookedShareCardImageShareItem(data: pngData, filename: filename)
    }
}

struct CookedShareCardImageShareItem: Transferable, Equatable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.data
        }
        .suggestedFileName { item in
            item.filename
        }
    }
}

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

enum CookedShareCardExportError: LocalizedError {
    case renderingFailed
    case emptyPNGData

    var errorDescription: String? {
        switch self {
        case .renderingFailed:
            "Could not render the cooked card image."
        case .emptyPNGData:
            "The cooked card image rendered without PNG data."
        }
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
