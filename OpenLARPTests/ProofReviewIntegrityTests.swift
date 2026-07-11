import XCTest
@testable import OpenLARP

final class ProofReviewIntegrityTests: XCTestCase {
    private let quest = Quest(
        id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!,
        day: 1,
        title: "Document one concrete career step",
        purpose: "Turn real work into reusable career context.",
        timeEstimateMinutes: 25,
        proofRequired: "Describe what you did and what changed.",
        xpReward: 120,
        status: .available
    )

    func testURLOnlySubmissionIsNotReviewableOrClaimable() {
        XCTAssertThrowsError(
            try OpenLARPEngine.checkProof(
                ProofSubmission(kind: .proof, text: "", link: "https://example.com/work"),
                for: quest
            )
        ) { error in
            XCTAssertEqual(error as? OpenLARPError, .emptyProof)
        }
    }

    func testImageOnlySubmissionIsNotReviewableOrClaimable() {
        let attachment = ProofAttachment(
            fileName: "proof.png",
            contentType: "image/png",
            byteCount: 1_024
        )

        XCTAssertThrowsError(
            try OpenLARPEngine.checkProof(
                ProofSubmission(kind: .proof, text: "", attachments: [attachment]),
                for: quest
            )
        ) { error in
            XCTAssertEqual(error as? OpenLARPError, .emptyProof)
        }
    }

    func testUninspectedURLAndImageDoNotChangeWrittenReviewOutcome() throws {
        let detailedText = "I compared three internship descriptions, recorded six repeated Swift skills, and mapped each skill to one specific project improvement for this week."
        let attachment = ProofAttachment(
            fileName: "comparison.png",
            contentType: "image/png",
            byteCount: 2_048
        )
        let textOnly = try OpenLARPEngine.checkProof(
            ProofSubmission(kind: .proof, text: detailedText),
            for: quest
        )
        let withUninspectedMetadata = try OpenLARPEngine.checkProof(
            ProofSubmission(
                kind: .proof,
                text: detailedText,
                link: "https://example.com/comparison",
                attachments: [attachment]
            ),
            for: quest
        )

        XCTAssertEqual(withUninspectedMetadata.isAccepted, textOnly.isAccepted)
        XCTAssertEqual(withUninspectedMetadata.qualityScore, textOnly.qualityScore)
        XCTAssertEqual(withUninspectedMetadata.xpEarned, textOnly.xpEarned)
        XCTAssertEqual(withUninspectedMetadata.readinessDelta, textOnly.readinessDelta)
        XCTAssertEqual(withUninspectedMetadata.label, textOnly.label)
        XCTAssertTrue(withUninspectedMetadata.inspectionScope.didInspectWrittenText)
        XCTAssertTrue(withUninspectedMetadata.inspectionScope.didInspectLinkFormat)
        XCTAssertFalse(withUninspectedMetadata.inspectionScope.didInspectLinkedDestination)
        XCTAssertTrue(withUninspectedMetadata.inspectionScope.didInspectAttachmentMetadata)
        XCTAssertFalse(withUninspectedMetadata.inspectionScope.didInspectAttachmentContents)
    }

    func testSelfReportRequiresWrittenReflectionEvenWhenMetadataIsPresent() {
        let attachment = ProofAttachment(
            fileName: "activity.png",
            contentType: "image/png",
            byteCount: 512
        )
        let submission = ProofSubmission(
            kind: .selfReport,
            text: "  \n ",
            link: "https://example.com/activity",
            attachments: [attachment]
        )

        XCTAssertThrowsError(try OpenLARPEngine.checkProof(submission, for: quest)) { error in
            XCTAssertEqual(error as? OpenLARPError, .emptyProof)
        }
    }

    func testLocalWrittenReviewDoesNotAwardStrongProofBadge() throws {
        let goal = CareerGoal(
            currentStatus: .student,
            targetRole: "iOS engineer",
            timeline: "30 days",
            background: "Learning Swift through real projects.",
            existingProof: "One class project.",
            confidence: 3,
            biggestBlocker: "Need clearer written proof of progress."
        )
        var state = OpenLARPEngine.confirmGoal(goal)
        let submission = ProofSubmission(
            kind: .proof,
            text: "I compared three internship descriptions, recorded six repeated Swift skills, and mapped each skill to one specific project improvement for this week."
        )
        let result = try OpenLARPEngine.checkProof(submission, in: state)

        state = try OpenLARPEngine.claim(result, proof: submission, in: state)

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.label, "Well-documented submission")
        XCTAssertTrue(state.progress.badges.contains(.firstProof))
        XCTAssertFalse(state.progress.badges.contains(.strongProof))
    }

    func testExplicitlyInspectedEvidenceCanAwardStrongProofBadge() throws {
        let goal = CareerGoal(
            currentStatus: .student,
            targetRole: "iOS engineer",
            timeline: "30 days",
            background: "Learning Swift through real projects.",
            existingProof: "One class project.",
            confidence: 3,
            biggestBlocker: "Need clearer written proof of progress."
        )
        var state = OpenLARPEngine.confirmGoal(goal)
        let attachment = ProofAttachment(
            fileName: "inspected.png",
            contentType: "image/png",
            byteCount: 2_048
        )
        let submission = ProofSubmission(
            kind: .proof,
            text: "I compared three internship descriptions and mapped the repeated requirements to concrete project work.",
            attachments: [attachment]
        )
        let result = QualityCheckResult(
            isAccepted: true,
            qualityScore: 90,
            label: "Strong proof",
            reason: "The submitted artifact was inspected and supports the written account.",
            improvement: "Connect it to one more role requirement.",
            xpEarned: 120,
            readinessDelta: 7,
            inspectionScope: ProofInspectionScope(
                didInspectWrittenText: true,
                didInspectLinkFormat: false,
                didInspectLinkedDestination: false,
                didInspectAttachmentMetadata: true,
                didInspectAttachmentContents: true
            )
        )

        state = try OpenLARPEngine.claim(result, proof: submission, in: state)

        XCTAssertTrue(state.progress.badges.contains(.strongProof))
    }

    func testLegacyQualityResultDecodesWithInspectionNotDocumented() throws {
        let data = Data(
            #"{"isAccepted":true,"qualityScore":88,"label":"Strong proof","reason":"Legacy result","improvement":"Add detail","xpEarned":120,"readinessDelta":7}"#.utf8
        )

        let result = try JSONDecoder().decode(QualityCheckResult.self, from: data)

        XCTAssertEqual(result.inspectionScope, .notDocumented)
        XCTAssertFalse(result.inspectionScope.didInspectWrittenText)
        XCTAssertFalse(result.inspectionScope.didInspectLinkFormat)
        XCTAssertFalse(result.inspectionScope.didInspectLinkedDestination)
        XCTAssertFalse(result.inspectionScope.didInspectAttachmentMetadata)
        XCTAssertFalse(result.inspectionScope.didInspectAttachmentContents)
    }

    func testReviewDisclosureSeparatesReviewedMetadataFromUninspectedContent() throws {
        let attachment = ProofAttachment(
            fileName: "context.png",
            contentType: "image/png",
            byteCount: 512
        )
        let proof = ProofSubmission(
            kind: .proof,
            text: "I documented the concrete work and the result for this target-role quest.",
            link: "https://example.com/context",
            attachments: [attachment]
        )
        let result = try OpenLARPEngine.checkProof(proof, for: quest)

        let disclosure = ProofReviewDisclosure(result: result, proof: proof)

        XCTAssertEqual(
            disclosure.reviewedText,
            "Reviewed: written description, link format, and image metadata."
        )
        XCTAssertEqual(
            disclosure.notInspectedText,
            "Not inspected: linked page or image contents."
        )
    }

    func testLegacyReviewDisclosureNeverImpliesInspection() {
        let result = QualityCheckResult(
            isAccepted: true,
            qualityScore: 88,
            label: "Legacy result",
            reason: "Old review",
            improvement: "Add detail",
            xpEarned: 100,
            readinessDelta: 5
        )
        let proof = ProofSubmission(
            kind: .proof,
            text: "Old proof text",
            link: "https://example.com/old",
            attachments: [
                ProofAttachment(
                    fileName: "old.png",
                    contentType: "image/png",
                    byteCount: 128
                )
            ]
        )

        let disclosure = ProofReviewDisclosure(result: result, proof: proof)

        XCTAssertEqual(
            disclosure.reviewedText,
            "Inspection scope was not recorded for this earlier review."
        )
        XCTAssertEqual(
            disclosure.notInspectedText,
            "Do not assume that linked pages or image contents were inspected."
        )
    }
}
