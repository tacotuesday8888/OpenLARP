import CoreTransferable
import SwiftUI
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

struct ShareCardImageExport: Equatable {
    let pngData: Data
    let filename: String
    let caption: String
    let subject: String
    let pixelSize: CGSize
    let contentType = "image/png"
    let fileExtension = "png"

    var shareItem: ShareCardImageItem {
        ShareCardImageItem(data: pngData, filename: filename)
    }

    @MainActor
    static func render(
        _ artwork: some View,
        size: CGSize,
        scale: CGFloat = 1,
        filename: String,
        caption: String,
        subject: String
    ) throws -> Self {
        let content = artwork
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale

        guard let image = renderer.uiImage else { throw ShareCardExportError.renderingFailed }
        guard let data = image.pngData(), !data.isEmpty else { throw ShareCardExportError.emptyPNGData }
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return Self(pngData: data, filename: filename, caption: caption, subject: subject, pixelSize: pixelSize)
    }
}

struct ShareCardImageItem: Transferable, Equatable {
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

enum ShareCardExportError: LocalizedError {
    case renderingFailed
    case emptyPNGData

    var errorDescription: String? {
        switch self {
        case .renderingFailed:
            "Could not render the card image."
        case .emptyPNGData:
            "The card image rendered without PNG data."
        }
    }
}
