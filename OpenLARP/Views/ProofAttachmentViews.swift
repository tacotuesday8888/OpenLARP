import ImageIO
import SwiftUI
import UIKit

enum ProofAttachmentImageLoader {
    static func load(
        from fileURL: URL,
        maximumPixelDimension: Int
    ) async -> UIImage? {
        let path = fileURL.path
        let boundedDimension = max(1, maximumPixelDimension)
        let loaded: SendableProofAttachmentImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                nil
            ) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: boundedDimension
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                return nil
            }
            return SendableProofAttachmentImage(image: UIImage(cgImage: thumbnail))
        }.value
        return loaded?.image
    }
}

private struct SendableProofAttachmentImage: @unchecked Sendable {
    let image: UIImage
}

struct ProofAttachmentStrip: View {
    let attachments: [ProofAttachment]
    let attachmentURL: (ProofAttachment) -> URL

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(attachments) { attachment in
                        ProofAttachmentThumbnail(
                            attachment: attachment,
                            fileURL: attachmentURL(attachment)
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct ProofAttachmentThumbnail: View {
    let attachment: ProofAttachment
    let fileURL: URL
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if !didFinishLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.openLARPBackground)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.title2)
                        Text("Missing")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Color.openLARPSoftInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.openLARPBackground)
                }
            }
            .frame(width: 96, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(attachment.byteCount.formattedByteCount)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(6)
        }
        .accessibilityLabel("Proof image attachment")
        .accessibilityValue(didFinishLoading && image == nil ? "Missing from this device" : attachment.originalFileName)
        .task(id: fileURL) {
            image = nil
            didFinishLoading = false
            image = await ProofAttachmentImageLoader.load(
                from: fileURL,
                maximumPixelDimension: 192
            )
            didFinishLoading = true
        }
    }
}

private extension Int {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
