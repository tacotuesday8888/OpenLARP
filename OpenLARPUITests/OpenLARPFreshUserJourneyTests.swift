import XCTest

final class OpenLARPFreshUserJourneyTests: XCTestCase {
    private var app: XCUIApplication!
    private let sprintStart = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testFreshUserCompletesFourteenDaySprintAndStartsAgain() throws {
        continueAfterFailure = false
        launch(day: 1, resettingLocalData: true)

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

        for day in 1...7 {
            if day > 1 {
                relaunch(day: day)
            }
            completeAvailableQuest(day: day)

            if day < 7 {
                XCTAssertTrue(
                    app.descendants(matching: .any)["today.tomorrowPreview"]
                        .waitForExistence(timeout: 10)
                )
            }
        }

        tapSprintAction(
            identifier: "sprint.chapterOneReview.action",
            expectedTitle: "Build Chapter Two"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["sprint.chapterTwo.waiting"]
                .waitForExistence(timeout: 10)
        )

        for day in 8...14 {
            relaunch(day: day)
            completeAvailableQuest(day: day)

            if day < 14 {
                XCTAssertTrue(
                    app.descendants(matching: .any)["today.tomorrowPreview"]
                        .waitForExistence(timeout: 10)
                )
            }
        }

        tapSprintAction(
            identifier: "sprint.finalReview.action",
            expectedTitle: "Create Sprint Report"
        )
        tapSprintAction(
            identifier: "sprint.completed.action",
            expectedTitle: "Start Another Sprint"
        )

        let startQuest = app.buttons["quest.start"]
        let startQuestExists = startQuest.waitForExistence(timeout: 10)
        XCTAssertTrue(startQuestExists)
        XCTAssertEqual(startQuest.label, "Start Quest")

        XCTAssertTrue(app.tabBars.buttons["Map"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
    }

    @MainActor
    private func launch(day: Int, resettingLocalData: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["OPENLARP_UI_TEST_RESET_LOCAL_DATA"] = resettingLocalData ? "1" : "0"
        app.launchEnvironment["OPENLARP_UI_TEST_NOW"] = String(
            sprintStart.addingTimeInterval(TimeInterval(day - 1) * 86_400).timeIntervalSince1970
        )
        app.launch()
    }

    @MainActor
    private func relaunch(day: Int) {
        app.terminate()
        launch(day: day, resettingLocalData: false)
    }

    @MainActor
    private func completeAvailableQuest(day: Int) {
        let startQuest = app.buttons["quest.start"]
        XCTAssertTrue(startQuest.waitForExistence(timeout: 10), "Day \(day) did not unlock")
        scrollToAndTap(startQuest)

        let proofText = app.textViews["proof.text"]
        let proofTextExists = proofText.waitForExistence(timeout: 10)
        XCTAssertTrue(proofTextExists)
        scrollToAndTap(proofText)
        proofText.typeText(
            "On day \(day), I completed the real career action, recorded what changed, and saved one truthful artifact or note that I can review and improve next."
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
    }

    @MainActor
    private func tapSprintAction(identifier: String, expectedTitle: String) {
        let action = app.buttons[identifier]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, expectedTitle)
        scrollToAndTap(action)
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
