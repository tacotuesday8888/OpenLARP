import XCTest

final class OpenLARPAccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private let sprintStart = Date(timeIntervalSince1970: 1_800_000_000)
    private let scalableChoiceLabelIdentifier = "onboarding.scalableChoiceLabel"

    @MainActor
    func testCoreCareerJourneyPassesAccessibilityAudit() throws {
        continueAfterFailure = false
        verifyLargestAccessibilityTextLayout()
        launchFreshApp()

        let targetOutcome = app.textFields["onboarding.targetOutcome"]
        XCTAssertTrue(targetOutcome.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Target outcome")

        targetOutcome.tap()
        targetOutcome.typeText("Entry-level iOS engineer")
        dismissKeyboardIfAvailable()

        tapPrimaryAction(expectedTitle: "Describe My Current Reality")
        try auditOnboardingScreen(
            named: "Current reality",
            expectedAction: "Set My Daily Commitment"
        )

        tapPrimaryAction(expectedTitle: "Set My Daily Commitment")
        try auditOnboardingScreen(
            named: "Daily commitment",
            expectedAction: "Review OpenLARP's Understanding"
        )

        tapPrimaryAction(expectedTitle: "Review OpenLARP's Understanding")
        try auditOnboardingScreen(
            named: "Understanding review",
            expectedAction: "Confirm Facts & Personalize My Check"
        )

        tapPrimaryAction(expectedTitle: "Confirm Facts & Personalize My Check")
        let keepUnknown = app.buttons["onboarding.keepUnknown"]
        XCTAssertTrue(keepUnknown.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Fact confirmation")
        scrollToAndTap(keepUnknown)

        tapPrimaryAction(expectedTitle: "Approve Understanding & Check My Readiness")
        let diagnosticAction = app.buttons["diagnostic.primaryAction"]
        XCTAssertTrue(diagnosticAction.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Cooked evaluation")
        scrollToAndTap(diagnosticAction)

        let approveMission = app.buttons["mission.approve"]
        XCTAssertTrue(approveMission.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Mission review")
        scrollToAndTap(approveMission)

        let startQuest = app.buttons["quest.start"]
        XCTAssertTrue(startQuest.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Daily quest")
        scrollToAndTap(startQuest)

        let proofText = app.textViews["proof.text"]
        XCTAssertTrue(proofText.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Proof preparation")
        scrollToAndTap(proofText)
        proofText.typeText(
            "I completed the real career action and saved a truthful note about what changed."
        )
        dismissKeyboardIfAvailable()

        let checkProof = app.buttons["proof.check"]
        XCTAssertTrue(checkProof.waitForExistence(timeout: 5))
        scrollToAndTap(checkProof)

        let claimXP = app.buttons["proof.claim"]
        XCTAssertTrue(claimXP.waitForExistence(timeout: 10))
        try auditCurrentScreen(named: "Proof feedback")
        scrollToAndTap(claimXP)

        XCTAssertTrue(
            app.descendants(matching: .any)["today.tomorrowPreview"]
                .waitForExistence(timeout: 10)
        )
        try auditCurrentScreen(named: "Completed quest")
    }

    @MainActor
    private func launchFreshApp(dynamicTypeSize: String? = nil) {
        app = XCUIApplication()
        app.launchEnvironment["OPENLARP_UI_TEST_RESET_LOCAL_DATA"] = "1"
        app.launchEnvironment["OPENLARP_UI_TEST_NOW"] = String(sprintStart.timeIntervalSince1970)
        if let dynamicTypeSize {
            app.launchEnvironment["OPENLARP_UI_TEST_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize
        }
        app.launch()
    }

    @MainActor
    private func verifyLargestAccessibilityTextLayout() {
        launchFreshApp(dynamicTypeSize: "accessibility5")

        let job = app.buttons["Job"]
        let internship = app.buttons["Internship"]
        XCTAssertTrue(job.waitForExistence(timeout: 10))
        XCTAssertTrue(internship.waitForExistence(timeout: 5))

        XCTAssertGreaterThan(job.frame.width, 250)
        XCTAssertGreaterThan(internship.frame.width, 250)
        XCTAssertGreaterThanOrEqual(job.frame.height, 44)
        XCTAssertGreaterThanOrEqual(internship.frame.height, 44)
        XCTAssertLessThan(abs(job.frame.minX - internship.frame.minX), 2)
        XCTAssertGreaterThan(internship.frame.minY, job.frame.maxY)

        scrollToAndTap(internship)
        XCTAssertTrue(internship.isSelected)
        app.terminate()
    }

    @MainActor
    private func auditOnboardingScreen(named name: String, expectedAction: String) throws {
        let action = app.buttons["onboarding.primaryAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, expectedAction)
        try auditCurrentScreen(named: name)
    }

    @MainActor
    private func auditCurrentScreen(named name: String) throws {
        try XCTContext.runActivity(named: "Accessibility audit: \(name)") { _ in
            try app.performAccessibilityAudit { issue in
                print(
                    """
                    Accessibility audit issue on \(name):
                    Type: \(issue.auditType.rawValue)
                    Summary: \(issue.compactDescription)
                    Details: \(issue.detailedDescription)
                    Element: \(issue.element?.debugDescription ?? "none")
                    """
                )
                let isKnownXcodeDynamicTypeFalsePositive =
                    issue.auditType == .dynamicType &&
                    issue.element?.identifier == scalableChoiceLabelIdentifier
                if isKnownXcodeDynamicTypeFalsePositive {
                    print(
                        "Ignoring Xcode 26.6 Dynamic Type false positive for the " +
                        "separately verified scalable onboarding choice label."
                    )
                }
                return isKnownXcodeDynamicTypeFalsePositive
            }
        }
    }

    @MainActor
    private func tapPrimaryAction(expectedTitle: String) {
        let action = app.buttons["onboarding.primaryAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, expectedTitle)
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
        XCTAssertTrue(element.isHittable)
        guard element.isHittable else { return }
        element.tap()
    }
}
