import XCTest

final class OpenLARPFreshUserJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["OPENLARP_UI_TEST_RESET_LOCAL_DATA"] = "1"
        app.launch()
    }

    func testFreshUserCompletesFirstTruthfulProofLoop() throws {
        let targetOutcome = app.textFields["onboarding.targetOutcome"]
        XCTAssertTrue(targetOutcome.waitForExistence(timeout: 10))
        targetOutcome.tap()
        targetOutcome.typeText("Entry-level iOS engineer")
        dismissKeyboardIfAvailable()

        tapPrimaryAction(expectedTitle: "Describe My Current Reality")
        tapPrimaryAction(expectedTitle: "Set My Daily Commitment")
        tapPrimaryAction(expectedTitle: "Review OpenLARP's Understanding")
        tapPrimaryAction(expectedTitle: "Confirm Facts & Personalize My Check")

        let keepUnknown = app.buttons["onboarding.keepUnknown"]
        XCTAssertTrue(keepUnknown.waitForExistence(timeout: 10))
        scrollToAndTap(keepUnknown)
        tapPrimaryAction(expectedTitle: "Approve Understanding & Check My Readiness")

        let diagnosticAction = app.buttons["diagnostic.primaryAction"]
        XCTAssertTrue(diagnosticAction.waitForExistence(timeout: 10))
        scrollToAndTap(diagnosticAction)

        let approveMission = app.buttons["mission.approve"]
        XCTAssertTrue(approveMission.waitForExistence(timeout: 10))
        scrollToAndTap(approveMission)

        let startQuest = app.buttons["quest.start"]
        XCTAssertTrue(startQuest.waitForExistence(timeout: 10))
        scrollToAndTap(startQuest)

        let proofText = app.textViews["proof.text"]
        XCTAssertTrue(proofText.waitForExistence(timeout: 10))
        scrollToAndTap(proofText)
        proofText.typeText(
            "I reviewed three real iOS job descriptions, recorded the repeated SwiftUI and testing requirements, and saved a role-specific checklist with one honest gap to address next."
        )
        dismissKeyboardIfAvailable()

        let checkProof = app.buttons["proof.check"]
        XCTAssertTrue(checkProof.waitForExistence(timeout: 5))
        scrollToAndTap(checkProof)

        let claimXP = app.buttons["proof.claim"]
        XCTAssertTrue(claimXP.waitForExistence(timeout: 10))
        scrollToAndTap(claimXP)

        XCTAssertTrue(app.staticTexts["today.done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tomorrow preview"].exists)
        XCTAssertTrue(app.tabBars.buttons["Map"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
    }

    private func tapPrimaryAction(expectedTitle: String) {
        let action = app.buttons["onboarding.primaryAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, expectedTitle)
        scrollToAndTap(action)
    }

    private func dismissKeyboardIfAvailable() {
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 1) {
            done.tap()
        }
    }

    private func scrollToAndTap(_ element: XCUIElement) {
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}
