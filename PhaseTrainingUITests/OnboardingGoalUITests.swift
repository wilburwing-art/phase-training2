import XCTest

/// The goal is offered on the onboarding seasons step. Picking one carries
/// into the first plan and retires the Week goal chip; leaving the default
/// keeps the chip (covered by SetupGoalHistoryUITests).
final class OnboardingGoalUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_pickingGoalInOnboarding_retiresGoalChip() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset"]
        app.launch()
        step(app, "onboarding-continue-welcome", timeout: 10)
        let sport = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding-sport-'")).firstMatch
        XCTAssertTrue(sport.waitForExistence(timeout: 6))
        sport.tap()
        step(app, "onboarding-continue-sports")

        let strength = app.buttons["onboarding-goal-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 6), "the seasons step offers the goal")
        var swipes = 0
        while !strength.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "onboarding-goal"
        shot.lifetime = .keepAlways
        add(shot)
        strength.tap()

        step(app, "onboarding-continue-sportSeasons")
        step(app, "onboarding-health-off")
        step(app, "onboarding-continue-health")
        step(app, "onboarding-consent-off")
        step(app, "onboarding-continue-coachConsent", timeout: 15)

        let week = app.tabBars.buttons["Week"]
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.tap()
        XCTAssertTrue(app.buttons["assumption-chip-availability"].waitForExistence(timeout: 10),
                      "the assumption chips render")
        XCTAssertFalse(app.buttons["assumption-chip-goal"].exists, "a goal picked in onboarding is stated")
    }

    private func step(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 8) {
        let b = app.buttons[id]
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "'\(id)' should appear")
        b.tap()
    }
}
