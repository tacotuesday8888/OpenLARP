import XCTest
@testable import OpenLARP

final class V0EngineTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .student,
        targetRole: "iOS engineering internship",
        timeline: "30 days",
        background: "Second-year CS student with one class project and no shipped app yet.",
        existingProof: "Class project, SwiftUI tutorial clone",
        confidence: 3,
        biggestBlocker: "I do not have strong proof that I can build production-quality apps."
    )

    func testGoalSetupCreatesDiagnosticAndSevenDayPlan() {
        let state = OpenLARPEngine.confirmGoal(goal)

        XCTAssertEqual(state.goal, goal)
        XCTAssertEqual(state.diagnostic?.label, "Medium Cooked")
        XCTAssertEqual(state.plan.count, 7)
        XCTAssertEqual(state.currentQuest?.status, .available)
        XCTAssertEqual(state.currentQuest?.gap, .proofStrength)
        XCTAssertEqual(state.progress.readiness.overall, 42)
    }

    func testStrongProofAwardsFullXPStreakReadinessAndBadges() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let proof = ProofSubmission(
            kind: .proof,
            text: "I built a small SwiftUI screen for the target app, tested the empty and completed states, wrote notes about the tradeoffs, and saved the code in a repo.",
            link: "https://example.com/proof",
            submittedAt: Date(timeIntervalSince1970: 1_800)
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.xpEarned, 120)
        XCTAssertEqual(state.progress.xp, 120)
        XCTAssertEqual(state.progress.streakCount, 1)
        XCTAssertEqual(state.progress.proofCount, 1)
        XCTAssertEqual(state.progress.completedQuestCount, 1)
        XCTAssertEqual(state.progress.readiness.proofStrength, 49)
        XCTAssertTrue(state.progress.badges.contains(.firstProof))
        XCTAssertEqual(state.plan[0].status, .completed)
        XCTAssertEqual(state.plan[1].status, .available)
    }

    func testSelfReportAwardsPartialCreditWithoutPretendingProofIsStrong() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let proof = ProofSubmission(
            kind: .selfReport,
            text: "I looked at two job posts and wrote down a few repeated skills.",
            link: "",
            submittedAt: Date(timeIntervalSince1970: 2_400)
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        XCTAssertFalse(result.isAccepted)
        XCTAssertEqual(result.xpEarned, 45)
        XCTAssertEqual(result.readinessDelta, 2)
        XCTAssertEqual(state.progress.xp, 45)
        XCTAssertEqual(state.progress.streakCount, 1)
        XCTAssertEqual(state.progress.proofCount, 1)
        XCTAssertEqual(state.progress.readiness.proofStrength, 44)
        XCTAssertEqual(state.progress.recentProof.first?.quality?.label, "Needs stronger proof")
    }

    func testImageAttachmentProofAwardsFullCreditWithoutTextOrLink() throws {
        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)

        let attachment = ProofAttachment(
            fileName: "proof-image.png",
            originalFileName: "whiteboard.png",
            contentType: "image/png",
            byteCount: 128,
            createdAt: Date(timeIntervalSince1970: 2_800)
        )
        let proof = ProofSubmission(
            kind: .proof,
            text: "",
            link: "",
            attachments: [attachment],
            submittedAt: Date(timeIntervalSince1970: 2_900)
        )

        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.xpEarned, 120)
        XCTAssertEqual(result.label, "Strong proof")
        XCTAssertEqual(state.progress.xp, 120)
        XCTAssertEqual(state.progress.proofCount, 1)
        XCTAssertEqual(state.progress.recentProof.first?.attachments, [attachment])
    }

    func testPersistenceRoundTripKeepsProofAttachmentMetadata() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)

        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let attachment = ProofAttachment(
            fileName: "proof-image.jpg",
            originalFileName: "screenshot.jpg",
            contentType: "image/jpeg",
            byteCount: 256,
            createdAt: Date(timeIntervalSince1970: 3_200)
        )
        let proof = ProofSubmission(
            kind: .proof,
            text: "This screenshot shows the requirement map I made.",
            link: "",
            attachments: [attachment],
            submittedAt: Date(timeIntervalSince1970: 3_300)
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        try persistence.save(state)
        let reloaded = try persistence.load()

        XCTAssertEqual(reloaded.progress.recentProof.first?.attachments, [attachment])
        XCTAssertEqual(reloaded.progress.recentProof.first?.attachmentSummary, "1 image")
    }

    func testAttachmentStoreWritesAndDeletesImageData() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OpenLARPAttachmentStore(directory: directory)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        let attachment = try store.saveImage(
            data: imageData,
            contentType: "image/png",
            originalFileName: "proof.png",
            now: Date(timeIntervalSince1970: 3_600)
        )

        XCTAssertEqual(attachment.contentType, "image/png")
        XCTAssertEqual(attachment.byteCount, imageData.count)
        XCTAssertEqual(try store.data(for: attachment), imageData)

        try store.delete(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: attachment).path))
    }

    func testProofDetailContentTrimsProofMetadataAndKeepsQualityFields() {
        let proof = ProofRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            questID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            questTitle: "Build a target-role proof map",
            kind: .proof,
            text: "  I made a requirements map from three internship posts.  ",
            link: " https://example.com/proof-map ",
            submittedAt: Date(timeIntervalSince1970: 4_200),
            quality: QualityCheckResult(
                isAccepted: true,
                qualityScore: 88,
                label: "Strong proof",
                reason: "This includes a concrete artifact.",
                improvement: "Tie the artifact to one target-role requirement.",
                xpEarned: 120,
                readinessDelta: 7
            )
        )

        let content = ProofDetailContent(proof: proof)

        XCTAssertEqual(content.questTitle, "Build a target-role proof map")
        XCTAssertEqual(content.proofType, "Proof")
        XCTAssertEqual(content.submittedAt, Date(timeIntervalSince1970: 4_200))
        XCTAssertEqual(content.qualityLabel, "Strong proof")
        XCTAssertEqual(content.xpText, "120 XP")
        XCTAssertEqual(content.reason, "This includes a concrete artifact.")
        XCTAssertEqual(content.improvement, "Tie the artifact to one target-role requirement.")
        XCTAssertEqual(content.proofText, "I made a requirements map from three internship posts.")
        XCTAssertEqual(content.proofLinkText, "https://example.com/proof-map")
        XCTAssertEqual(content.proofURL, URL(string: "https://example.com/proof-map"))
    }

    func testProofDetailContentUsesFallbacksWhenQualityIsMissing() {
        let proof = ProofRecord(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            questID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            questTitle: "Reflect on outreach",
            kind: .selfReport,
            text: "   ",
            link: "not a url",
            submittedAt: Date(timeIntervalSince1970: 4_800),
            quality: nil
        )

        let content = ProofDetailContent(proof: proof)

        XCTAssertEqual(content.qualityLabel, "Self-report")
        XCTAssertEqual(content.xpText, "0 XP")
        XCTAssertEqual(content.reason, "No quality check is attached to this receipt yet.")
        XCTAssertEqual(content.improvement, "Submit stronger proof on the next quest to get sharper feedback.")
        XCTAssertNil(content.proofText)
        XCTAssertEqual(content.proofLinkText, "not a url")
        XCTAssertNil(content.proofURL)
    }

    func testPersistenceRoundTripKeepsGoalProgressAndQuestStatuses() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = OpenLARPPersistence(directory: directory)

        var state = OpenLARPEngine.confirmGoal(goal)
        state = try OpenLARPEngine.startCurrentQuest(in: state)
        let proof = ProofSubmission(
            kind: .proof,
            text: "I created a target-role requirements map with six repeated skills, picked one proof-building app idea, and wrote the first implementation checklist.",
            link: "https://example.com/checklist",
            submittedAt: Date(timeIntervalSince1970: 3_000)
        )
        let result = try OpenLARPEngine.checkProof(proof, in: state)
        state = try OpenLARPEngine.claim(result, proof: proof, in: state)

        try persistence.save(state)
        let reloaded = try persistence.load()

        XCTAssertEqual(reloaded.goal, goal)
        XCTAssertEqual(reloaded.progress.xp, 120)
        XCTAssertEqual(reloaded.progress.streakCount, 1)
        XCTAssertEqual(reloaded.plan[0].status, .completed)
        XCTAssertEqual(reloaded.progress.recentProof.count, 1)
        XCTAssertEqual(reloaded.progress.recentProof.first?.text, proof.text)
    }
}
