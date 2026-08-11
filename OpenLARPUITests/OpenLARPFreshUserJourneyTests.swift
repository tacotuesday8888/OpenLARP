import XCTest

final class OpenLARPFreshUserJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    func testFreshUserCompletesFirstTruthfulProofLoop() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["OPENLARP_UI_TEST_RESET_LOCAL_DATA"] = "1"
        app.launch()

        let targetOutcome = app.textFields["onboarding.targetOutcome"]
        let targetOutcomeExists = targetOutcome.waitForExistence(timeout: 10)
        XCTAssertTrue(targetOutcomeExists)
        targetOutcome.tap()
        targetOutcome.typeText("Entry-level iOS engineer")
        dismissKeyboardIfAvailable()

        tapPrimaryAction(expectedTitle: "Describe My Current Reality")
        tapPrimaryAction(expectedTitle: "Set My Daily Commitment")
        tapPrimaryAction(expectedTitle: "Review OpenLARP's Understanding")
        tapPrimaryAction(expectedTitle: "Confirm Facts & Personalize My Check")

        let keepUnknown = app.buttons["onboarding.keepUnknown"]
        let keepUnknownExists = keepUnknown.waitForExistence(timeout: 10)
        XCTAssertTrue(keepUnknownExists)
        scrollToAndTap(keepUnknown)
        tapPrimaryAction(expectedTitle: "Approve Understanding & Check My Readiness")

        let diagnosticAction = app.buttons["diagnostic.primaryAction"]
        let diagnosticActionExists = diagnosticAction.waitForExistence(timeout: 10)
        XCTAssertTrue(diagnosticActionExists)
        scrollToAndTap(diagnosticAction)

        let approveMission = app.buttons["mission.approve"]
        let approveMissionExists = approveMission.waitForExistence(timeout: 10)
        XCTAssertTrue(approveMissionExists)
        scrollToAndTap(approveMission)

        let startQuest = app.buttons["quest.start"]
        let startQuestExists = startQuest.waitForExistence(timeout: 10)
        XCTAssertTrue(startQuestExists)
        scrollToAndTap(startQuest)

        let proofText = app.textViews["proof.text"]
        let proofTextExists = proofText.waitForExistence(timeout: 10)
        XCTAssertTrue(proofTextExists)
        scrollToAndTap(proofText)
        proofText.typeText(
            "I reviewed three real iOS job descriptions, recorded the repeated SwiftUI and testing requirements, and saved a role-specific checklist with one honest gap to address next."
        )
        dismissKeyboardIfAvailable()

        let checkProof = app.buttons["proof.check"]
        let checkProofExists = checkProof.waitForExistence(timeout: 5)
        XCTAssertTrue(checkProofExists)
        scrollToAndTap(checkProof)

        let claimXP = app.buttons["proof.claim"]
        let claimXPExists = claimXP.waitForExistence(timeout: 10)
        XCTAssertTrue(claimXPExists)
        scrollToAndTap(claimXP)

        let doneForTodayExists = app.descendants(matching: .any)["today.done"]
            .waitForExistence(timeout: 10)
        let tomorrowPreviewExists = app.staticTexts["Tomorrow preview"].exists
        let mapTabExists = app.tabBars.buttons["Map"].exists
        let progressTabExists = app.tabBars.buttons["Progress"].exists
        let profileTabExists = app.tabBars.buttons["Profile"].exists
        XCTAssertTrue(doneForTodayExists)
        XCTAssertTrue(tomorrowPreviewExists)
        XCTAssertTrue(mapTabExists)
        XCTAssertTrue(progressTabExists)
        XCTAssertTrue(profileTabExists)
    }

    @MainActor
    private func tapPrimaryAction(expectedTitle: String) {
        let action = app.buttons["onboarding.primaryAction"]
        let actionExists = action.waitForExistence(timeout: 10)
        let actionLabel = action.label
        XCTAssertTrue(actionExists)
        XCTAssertEqual(actionLabel, expectedTitle)
        scrollToAndTap(action)
    }

    @MainActor
    private func dismissKeyboardIfAvailable() {
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 1) {
            done.tap()
        }
    }

    @MainActor
    private func scrollToAndTap(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            if element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            attempts += 1
        }
        let isHittable = element.isHittable
        XCTAssertTrue(isHittable)
        guard isHittable else { return }
        element.tap()
    }
}
