import SwiftUI
import UIKit

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

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = UIImage(contentsOfFile: fileURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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
    }
}

private extension Int {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
