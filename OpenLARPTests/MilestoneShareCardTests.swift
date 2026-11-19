import UIKit
import XCTest
@testable import OpenLARP

final class MilestoneShareCardTests: XCTestCase {
    private let goal = CareerGoal(
        currentStatus: .student,
        targetRole: "Product design intern",
        timeline: "30 days",
        background: "Design student",
        existingProof: "One class project",
        confidence: 3,
        biggestBlocker: "Finding a portfolio story"
    )

    func testShareWinsIsRequiredForEveryKindAndIsNeverChangedByPreviewing() {
        var state = OpenLARPEngine.confirmGoal(goal)
        let record = outcome(.interview)
        state.outcomeLog = [record]
        state.progress.streakCount = 1
        let selections: [MilestoneShareSelection] = [.streak, .badge(.firstGoal), .outcome(record.id)]
        for selection in selections {
            XCTAssertNil(MilestoneShareCard(selection: selection, state: state))
        }

        state.userProfile?.privacy.shareWins = true
        let original = state
        for selection in selections {
            XCTAssertNotNil(MilestoneShareCard(selection: selection, state: state))
        }
        XCTAssertEqual(state, original)

        state.userProfile = nil
        for selection in selections {
            XCTAssertNil(MilestoneShareCard(selection: selection, state: state))
        }
    }

    func testStreakUsesCurrentCountWhileEarnedStreakBadgesSurviveAReset() throws {
        var state = sharingState()
        XCTAssertNil(MilestoneShareCard(selection: .streak, state: state))
        state.progress.streakCount = 1
        XCTAssertEqual(MilestoneShareCard(selection: .streak, state: state)?.title, "1-day streak")
        state.progress.streakCount = 7
        XCTAssertNil(MilestoneShareCard(selection: .badge(.weeklyStreak), state: state))
        state.progress.badges += [.threeDayStreak, .weeklyStreak]
        state.dailyCadence.streakCountAfterCompletion = 7
        state.progress.streakCount = 0
        XCTAssertNil(MilestoneShareCard(selection: .streak, state: state))
        for badge in [Badge.threeDayStreak, .weeklyStreak] {
            let card = try XCTUnwrap(MilestoneShareCard(selection: .badge(badge), state: state))
            XCTAssertEqual(card.kind, .badge)
            XCTAssertEqual(card.title, badge.rawValue)
        }
    }

    @MainActor
    func testRenderedMilestoneIsA1080By1350PNGWithThePreviewedCaption() throws {
        var state = sharingState()
        state.progress.streakCount = 3
        let card = try XCTUnwrap(MilestoneShareCard(selection: .streak, state: state))
        let export = try MilestoneShareCardImageRenderer.render(card)
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(export.pngData.prefix(8)), pngSignature)
        let pixels = try XCTUnwrap(UIImage(data: export.pngData)?.cgImage)
        XCTAssertEqual(pixels.width, 1080)
        XCTAssertEqual(pixels.height, 1350)
        XCTAssertEqual(export.filename, "openlarp-milestone.png")
        XCTAssertEqual(export.subject, card.title)
        XCTAssertEqual(export.caption, card.caption)
    }

    func testSelfReportCanShareAFirstEntryAndLegacyStrongProofNeedsDocumentedInspection() throws {
        let state = sharingState()
        let submission = ProofSubmission(kind: .selfReport, text: "I wrote down one thing I learned.")
        let result = try OpenLARPEngine.checkProof(submission, in: state)
        var claimed = try OpenLARPEngine.claim(result, proof: submission, in: state)
        let firstEntry = try XCTUnwrap(MilestoneShareCard(selection: .badge(.firstProof), state: claimed))
        XCTAssertEqual(firstEntry.title, "First quest entry")
        XCTAssertFalse(firstEntry.caption.localizedCaseInsensitiveContains("proof"))
        XCTAssertNil(MilestoneShareCard(selection: .badge(.strongProof), state: claimed))

        claimed.progress.badges.append(.strongProof)
        claimed.progress.recentProof[0].kind = .proof
        claimed.progress.recentProof[0].quality?.isAccepted = true
        claimed.progress.recentProof[0].quality?.inspectionScope = .notDocumented
        XCTAssertNil(MilestoneShareCard(selection: .badge(.strongProof), state: claimed))
        claimed.progress.recentProof[0].quality?.inspectionScope.didInspectAttachmentContents = true
        XCTAssertNotNil(MilestoneShareCard(selection: .badge(.strongProof), state: claimed))
    }

    func testOutcomeCardContainsOnlyKindAndSelfReportedProvenance() throws {
        var state = sharingState()
        for kind in CareerOutcomeKind.allCases {
            let first = outcome(kind)
            var second = outcome(kind)
            second.title = "A different title"
            second.organizationName = "A different organization"
            second.note = "A different note"
            second.targetRoleTitle = "A different career goal"
            state.outcomeLog = [first, second]
            let card = try XCTUnwrap(MilestoneShareCard(selection: .outcome(first.id), state: state))
            XCTAssertEqual(card, MilestoneShareCard(selection: .outcome(second.id), state: state))
            XCTAssertEqual(card.kind, .outcome)
            XCTAssertEqual(card.category, "Self-reported outcome")
            XCTAssertTrue(card.caption.contains(card.category))
            let publicText = [card.title, card.detail, card.systemImage, card.caption, MilestoneShareCard.filename].joined()
            for value in [first.title, first.organizationName, first.note, first.targetRoleTitle, first.id.uuidString] {
                XCTAssertFalse(publicText.contains(value))
            }
        }
    }

    func testEditedPrivateAndDeletedOutcomesCannotLeakThroughAwardsOrRecordIDs() {
        var state = sharingState()
        let interview = outcome(.interview)
        let offer = outcome(.offer)
        state = OpenLARPEngine.logOutcome(interview, in: state)
        state = OpenLARPEngine.logOutcome(offer, in: state)
        XCTAssertNotNil(MilestoneShareCard(selection: .badge(.firstInterview), state: state))
        XCTAssertNotNil(MilestoneShareCard(selection: .badge(.firstOffer), state: state))

        var nowPrivate = interview
        nowPrivate.isPrivate = true
        state = OpenLARPEngine.updateOutcome(nowPrivate, in: state)
        state = OpenLARPEngine.deleteOutcome(id: offer.id, in: state)
        XCTAssertNil(MilestoneShareCard(selection: .outcome(UUID()), state: state))
        for selection in [MilestoneShareSelection.outcome(interview.id), .outcome(offer.id),
                          .badge(.firstInterview), .badge(.firstOffer), .badge(.firstOutcome)] {
            XCTAssertNil(MilestoneShareCard(selection: selection, state: state))
        }

        var corrected = interview
        corrected.kind = .applied
        state = OpenLARPEngine.updateOutcome(corrected, in: state)
        XCTAssertNil(MilestoneShareCard(selection: .badge(.firstInterview), state: state))
        XCTAssertNotNil(MilestoneShareCard(selection: .badge(.firstOutcome), state: state))
        XCTAssertEqual(MilestoneShareCard(selection: .outcome(corrected.id), state: state)?.title, "Application logged")
    }

    private func sharingState() -> OpenLARPState {
        var state = OpenLARPEngine.confirmGoal(goal)
        state.userProfile?.privacy.shareWins = true
        return state
    }

    private func outcome(_ kind: CareerOutcomeKind) -> CareerOutcomeRecord {
        CareerOutcomeRecord(
            kind: kind,
            title: "Private recruiter thread",
            organizationName: "Private company",
            note: "Private contact information",
            occurredAt: Date(timeIntervalSince1970: 100_000),
            targetRoleTitle: "Private role",
            isPrivate: false
        )
    }
}
