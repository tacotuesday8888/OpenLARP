import CoreTransferable
import Foundation
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
