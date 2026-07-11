import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProofAttachmentPolicy {
    static let maximumCount = 4
    static let maximumBytes = 8 * 1_024 * 1_024
    static let allowedContentTypes: Set<String> = [
        "image/heic",
        "image/heif",
        "image/jpeg",
        "image/png"
    ]
}

enum ProofImageProcessingError: Error, Equatable, LocalizedError {
    case unsupportedContentType
    case corruptImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedContentType:
            "Use a PNG, JPEG, HEIC, or HEIF screenshot or photo."
        case .corruptImage:
            "That image could not be read. Try exporting or selecting it again."
        case .imageTooLarge:
            "That image could not be reduced below the 8 MB proof-image limit."
        }
    }
}

enum OpenLARPProofDraftError: Error, Equatable, LocalizedError {
    case noActiveQuest
    case staleDraft
    case attachmentLimitReached
    case attachmentsRequireProofKind
    case storageFailed
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .noActiveQuest:
            "Start an available quest before creating proof."
        case .staleDraft:
            "That proof draft is no longer active. Start again from today's quest."
        case .attachmentLimitReached:
            "A proof draft can include up to four images. Remove one before adding another."
        case .attachmentsRequireProofKind:
            "Switch to Proof before adding a screenshot or photo."
        case .storageFailed:
            "That image could not be saved safely on this device."
        case .persistenceFailed:
            "The proof draft could not be saved. Your previous draft is still available."
        }
    }
}

struct ProcessedProofImage: Equatable, Sendable {
    let data: Data
    let contentType: String
    let fileExtension: String

    var byteCount: Int { data.count }
}

struct OpenLARPProofImageProcessor: Sendable {
    private let maximumBytes: Int
    private let maximumOutputDimension: Int
    private let minimumOutputDimension: Int

    init(
        maximumBytes: Int = ProofAttachmentPolicy.maximumBytes,
        maximumOutputDimension: Int = 4_096,
        minimumOutputDimension: Int = 640
    ) {
        self.maximumBytes = max(1, maximumBytes)
        self.maximumOutputDimension = max(1, maximumOutputDimension)
        self.minimumOutputDimension = max(1, min(minimumOutputDimension, maximumOutputDimension))
    }

    func process(
        data: Data,
        declaredContentType: String
    ) throws -> ProcessedProofImage {
        let normalizedDeclaration = declaredContentType.lowercased()
        guard ProofAttachmentPolicy.allowedContentTypes.contains(normalizedDeclaration) else {
            throw ProofImageProcessingError.unsupportedContentType
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let decodedFormat = decodedFormat(for: source),
              canDecode(source)
        else {
            throw ProofImageProcessingError.corruptImage
        }

        guard data.count > maximumBytes else {
            return ProcessedProofImage(
                data: data,
                contentType: decodedFormat.contentType,
                fileExtension: decodedFormat.fileExtension
            )
        }

        guard let recompressed = recompressedJPEG(from: source) else {
            throw ProofImageProcessingError.imageTooLarge
        }
        return recompressed
    }

    private func canDecode(_ source: CGImageSource) -> Bool {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options) != nil
    }

    private func decodedFormat(for source: CGImageSource) -> (contentType: String, fileExtension: String)? {
        guard let sourceType = CGImageSourceGetType(source),
              let type = UTType(sourceType as String)
        else {
            return nil
        }

        if type.conforms(to: .png) {
            return ("image/png", "png")
        }
        if type.conforms(to: .jpeg) {
            return ("image/jpeg", "jpg")
        }
        if type.conforms(to: .heic) {
            return ("image/heic", "heic")
        }
        if type.conforms(to: .heif) {
            return ("image/heif", "heif")
        }
        return nil
    }

    private func recompressedJPEG(from source: CGImageSource) -> ProcessedProofImage? {
        let sourceDimension = pixelDimension(of: source) ?? maximumOutputDimension
        var dimension = min(sourceDimension, maximumOutputDimension)
        let minimumDimension = min(dimension, minimumOutputDimension)
        let qualities: [CGFloat] = [0.86, 0.74, 0.62, 0.5, 0.38, 0.28]

        while true {
            guard let image = thumbnail(from: source, maximumPixelDimension: dimension) else {
                return nil
            }

            for quality in qualities {
                guard let encoded = encodeJPEG(image, quality: quality) else { continue }
                if encoded.count <= maximumBytes {
                    return ProcessedProofImage(
                        data: encoded,
                        contentType: "image/jpeg",
                        fileExtension: "jpg"
                    )
                }
            }

            if dimension == minimumDimension {
                break
            }
            dimension = max(minimumDimension, Int(Double(dimension) * 0.75))
        }

        return nil
    }

    private func pixelDimension(of source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }
        return max(width.intValue, height.intValue)
    }

    private func thumbnail(
        from source: CGImageSource,
        maximumPixelDimension: Int
    ) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
