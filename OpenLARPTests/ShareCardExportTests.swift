import UIKit
import XCTest
@testable import OpenLARP

@MainActor
final class ShareCardExportTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .student,
        targetRole: "AI product internship",
        timeline: "30 days",
        background: "Private background with langqi@example.com, visa concern, and campus office.",
        existingProof: "Secret Project Falcon, private repo, and https://private.example.com/proof.",
        confidence: 2,
        biggestBlocker: "Confidential blocker with family money stress."
    )

    func testShareCardExportPayloadUsesOnlyApprovedPublicFields() throws {
        var state = OpenLARPEngine.confirmGoal(goal, now: Date(timeIntervalSince1970: 20_000))
        state.progress.recentProof = [privateProof()]
        state.progress.proofCount = 1
        state.outcomeLog = [
            CareerOutcomeRecord(
                kind: .interview,
                title: "Private recruiter screen",
                organizationName: "Example Labs",
                note: "Sensitive recruiter note should stay private.",
                occurredAt: Date(timeIntervalSince1970: 20_500),
                targetRoleTitle: goal.targetRole,
                isPrivate: true
            )
        ]

        let content = try XCTUnwrap(CookedShareCardContent(state: state))
        let payload = CookedShareCardExportPayload(content: content)
        let exportedText = payload.searchableText

        XCTAssertTrue(exportedText.contains(content.title))
        XCTAssertTrue(exportedText.contains(content.cookedLabel))
        XCTAssertTrue(exportedText.contains(content.scoreText))
        XCTAssertTrue(exportedText.contains(content.readinessText))
        XCTAssertTrue(exportedText.contains(content.publicGapText))
        XCTAssertTrue(exportedText.contains(content.recoveryText))
        XCTAssertTrue(exportedText.contains(content.footerText))
        XCTAssertFalse(exportedText.contains("langqi@example.com"))
        XCTAssertFalse(exportedText.contains("visa"))
        XCTAssertFalse(exportedText.contains("Secret Project Falcon"))
        XCTAssertFalse(exportedText.contains("private.example.com"))
        XCTAssertFalse(exportedText.contains("F2F2F2F2-F2F2-F2F2-F2F2-F2F2F2F2F2F2"))
        XCTAssertFalse(exportedText.contains("ProofAttachments"))
        XCTAssertFalse(exportedText.contains("sk-test-secret"))
        XCTAssertFalse(exportedText.contains("Sensitive recruiter note"))
    }

    func testShareCardExportPayloadFallsBackForPrivateTargetRole() throws {
        let privateGoal = CareerGoal(
            currentStatus: .student,
            targetRole: "/Users/langqi/private/F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1/sk-test-secret-api-key.txt",
            timeline: "30 days",
            background: "",
            existingProof: "",
            confidence: 3,
            biggestBlocker: ""
        )
        let state = OpenLARPEngine.confirmGoal(privateGoal)

        let content = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))
        let payload = CookedShareCardExportPayload(content: content)
        let exportedText = payload.searchableText

        XCTAssertTrue(exportedText.contains("my career goal"))
        XCTAssertFalse(exportedText.contains("/Users"))
        XCTAssertFalse(exportedText.contains("F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1"))
        XCTAssertFalse(exportedText.contains("sk-test-secret"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(exportedText.contains(".txt"))
    }

    func testDetailedExportPayloadUsesGenericPublicDetailOnly() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state.plan[0].title = "Use private proof from /Users/langqi/SecretProject and sk-test-secret"
        state.plan[0].purpose = "Mention private.example.com and internal notes."

        let content = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))
        let payload = CookedShareCardExportPayload(content: content)
        let exportedText = payload.searchableText

        XCTAssertEqual(payload.detailText, "First move: start one proof-building quest.")
        XCTAssertFalse(exportedText.contains("/Users"))
        XCTAssertFalse(exportedText.contains("SecretProject"))
        XCTAssertFalse(exportedText.contains("private.example.com"))
        XCTAssertFalse(exportedText.contains("sk-test-secret"))
        XCTAssertFalse(exportedText.contains(state.plan[0].title))
        XCTAssertFalse(exportedText.contains(state.plan[0].purpose))
    }

    func testShareCardCaptionMatchesSafePayloadFacts() throws {
        let state = OpenLARPEngine.confirmGoal(goal)
        let content = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))
        let payload = CookedShareCardExportPayload(content: content)

        XCTAssertEqual(payload.caption, content.shareText)
        XCTAssertTrue(payload.caption.contains(payload.title))
        XCTAssertTrue(payload.caption.contains(payload.scoreText))
        XCTAssertTrue(payload.caption.contains(payload.publicGapText))
        XCTAssertFalse(payload.caption.contains(goal.background))
        XCTAssertFalse(payload.caption.contains(goal.existingProof))
        XCTAssertFalse(payload.caption.contains(goal.biggestBlocker))
    }

    func testShareCardPNGRenderProducesDecodableImageWithExpectedMetadata() throws {
        let state = OpenLARPEngine.confirmGoal(goal)
        let content = try XCTUnwrap(CookedShareCardContent(state: state))
        let payload = CookedShareCardExportPayload(content: content)

        let export = try CookedShareCardImageExportService().render(payload: payload)

        XCTAssertGreaterThan(export.pngData.count, 0)
        XCTAssertEqual(export.contentType, "image/png")
        XCTAssertEqual(export.fileExtension, "png")
        XCTAssertEqual(export.caption, payload.caption)
        XCTAssertEqual(export.filename, payload.suggestedFilename)
        let image = try XCTUnwrap(UIImage(data: export.pngData))
        XCTAssertEqual(Int(image.size.width), Int(payload.pixelSize.width))
        XCTAssertEqual(Int(image.size.height), Int(payload.pixelSize.height))
    }

    func testShareCardExportFilenameIsStableAndSafe() throws {
        let privateGoal = CareerGoal(
            currentStatus: .student,
            targetRole: "private.example.com/linkedin.com/in/langqi/sk-test-secret-api-key.txt",
            timeline: "30 days",
            background: "",
            existingProof: "",
            confidence: 3,
            biggestBlocker: ""
        )
        let state = OpenLARPEngine.confirmGoal(privateGoal)
        let content = try XCTUnwrap(CookedShareCardContent(state: state))
        let payload = CookedShareCardExportPayload(content: content)

        XCTAssertEqual(payload.suggestedFilename, "openlarp-cooked-card.png")
        XCTAssertFalse(payload.suggestedFilename.contains("/"))
        XCTAssertFalse(payload.suggestedFilename.contains("\\"))
        XCTAssertFalse(payload.suggestedFilename.contains(".com"))
        XCTAssertFalse(payload.suggestedFilename.contains("linkedin"))
        XCTAssertFalse(payload.suggestedFilename.contains("sk-test-secret"))
        XCTAssertTrue(payload.suggestedFilename.hasSuffix(".png"))
    }

    func testGeneratingShareCardDoesNotMutateCareerState() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state.userProfile?.privacy.shareWins = false
        let originalState = state

        let privateContent = try XCTUnwrap(CookedShareCardContent(state: state))
        let detailedContent = try XCTUnwrap(CookedShareCardContent(state: state, includeDetails: true))
        _ = CookedShareCardExportPayload(content: privateContent)
        let payload = CookedShareCardExportPayload(content: detailedContent)
        _ = try CookedShareCardImageExportService().render(payload: payload)

        XCTAssertEqual(state, originalState)
        XCTAssertEqual(state.userProfile?.privacy.shareWins, false)
    }

    private func privateProof() -> ProofRecord {
        let now = Date(timeIntervalSince1970: 20_250)
        let attachment = ProofAttachment(
            id: UUID(uuidString: "F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1")!,
            fileName: "local-private-proof.png",
            originalFileName: "private-screenshot.png",
            contentType: "image/png",
            byteCount: 40_000,
            createdAt: now,
            localRelativePath: "ProofAttachments/private-device-path.png"
        )
        return ProofRecord(
            id: UUID(uuidString: "F2F2F2F2-F2F2-F2F2-F2F2-F2F2F2F2F2F2")!,
            questID: UUID(uuidString: "F3F3F3F3-F3F3-F3F3-F3F3-F3F3F3F3F3F3")!,
            questTitle: "Private proof quest",
            kind: .proof,
            text: "Sensitive proof text with sk-test-secret and internal recruiter notes.",
            link: "https://private.example.com/proof",
            attachments: [attachment],
            submittedAt: now,
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "Concrete enough to count.",
                improvement: "Tie it to one role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )
    }
}
