import UIKit
import XCTest
@testable import OpenLARP

final class ProofImageProcessorTests: XCTestCase {
    func testProductionPolicyAllowsFourImagesUpToEightMiB() {
        XCTAssertEqual(ProofAttachmentPolicy.maximumCount, 4)
        XCTAssertEqual(ProofAttachmentPolicy.maximumBytes, 8 * 1_024 * 1_024)
        XCTAssertEqual(
            ProofAttachmentPolicy.allowedContentTypes,
            ["image/heic", "image/heif", "image/jpeg", "image/png"]
        )
    }

    func testProcessorPreservesSupportedImageWithinLimit() throws {
        let input = makePNG(size: CGSize(width: 12, height: 8))

        let processed = try OpenLARPProofImageProcessor().process(
            data: input,
            declaredContentType: "image/png"
        )

        XCTAssertEqual(processed.data, input)
        XCTAssertEqual(processed.contentType, "image/png")
        XCTAssertEqual(processed.fileExtension, "png")
        XCTAssertEqual(processed.byteCount, input.count)
    }

    func testProcessorUsesDecodedImageTypeInsteadOfMismatchedDeclaration() throws {
        let input = makePNG(size: CGSize(width: 10, height: 10))

        let processed = try OpenLARPProofImageProcessor().process(
            data: input,
            declaredContentType: "image/jpeg"
        )

        XCTAssertEqual(processed.contentType, "image/png")
        XCTAssertEqual(processed.fileExtension, "png")
    }

    func testProcessorRejectsUnsupportedDeclaredContentType() {
        let input = makePNG(size: CGSize(width: 10, height: 10))

        XCTAssertThrowsError(
            try OpenLARPProofImageProcessor().process(
                data: input,
                declaredContentType: "image/gif"
            )
        ) { error in
            XCTAssertEqual(error as? ProofImageProcessingError, .unsupportedContentType)
        }
    }

    func testProcessorRejectsCorruptImageBytes() {
        let corruptPNGHeader = Data([0x89, 0x50, 0x4E, 0x47])

        XCTAssertThrowsError(
            try OpenLARPProofImageProcessor().process(
                data: corruptPNGHeader,
                declaredContentType: "image/png"
            )
        ) { error in
            XCTAssertEqual(error as? ProofImageProcessingError, .corruptImage)
        }
    }

    func testProcessorRecompressesOversizedImageWithinConfiguredLimit() throws {
        let input = makePatternedPNG(size: CGSize(width: 320, height: 320))
        let maximumBytes = 18_000
        XCTAssertGreaterThan(input.count, maximumBytes)

        let processed = try OpenLARPProofImageProcessor(
            maximumBytes: maximumBytes,
            maximumOutputDimension: 320
        ).process(
            data: input,
            declaredContentType: "image/png"
        )

        XCTAssertLessThanOrEqual(processed.byteCount, maximumBytes)
        XCTAssertEqual(processed.contentType, "image/jpeg")
        XCTAssertEqual(processed.fileExtension, "jpg")
        XCTAssertNotEqual(processed.data, input)
    }

    func testProcessorAttemptsRecompressionForImageSmallerThanDefaultFloor() throws {
        let input = makeOneXNoisePNG(size: CGSize(width: 160, height: 160))
        let maximumBytes = input.count - 1

        let processed = try OpenLARPProofImageProcessor(
            maximumBytes: maximumBytes
        ).process(
            data: input,
            declaredContentType: "image/png"
        )

        XCTAssertLessThanOrEqual(processed.byteCount, maximumBytes)
        XCTAssertEqual(processed.contentType, "image/jpeg")
    }

    func testProcessorRejectsImageWhenNoEncodedCandidateFitsConfiguredLimit() {
        let input = makePatternedPNG(size: CGSize(width: 80, height: 80))

        XCTAssertThrowsError(
            try OpenLARPProofImageProcessor(
                maximumBytes: 16,
                maximumOutputDimension: 80,
                minimumOutputDimension: 64
            ).process(
                data: input,
                declaredContentType: "image/png"
            )
        ) { error in
            XCTAssertEqual(error as? ProofImageProcessingError, .imageTooLarge)
        }
    }

    private func makePNG(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makePatternedPNG(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            let cell = CGFloat(4)
            var y = CGFloat.zero
            var row = 0
            while y < size.height {
                var x = CGFloat.zero
                var column = 0
                while x < size.width {
                    let red = CGFloat((row * 37 + column * 17) % 255) / 255
                    let green = CGFloat((row * 11 + column * 43) % 255) / 255
                    let blue = CGFloat((row * 29 + column * 7) % 255) / 255
                    UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell
                    column += 1
                }
                y += cell
                row += 1
            }
        }
    }

    private func makeOneXNoisePNG(size: CGSize) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    let red = CGFloat((x * 73 + y * 19) % 255) / 255
                    let green = CGFloat((x * 31 + y * 47) % 255) / 255
                    let blue = CGFloat((x * 13 + y * 97) % 255) / 255
                    UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }
}
