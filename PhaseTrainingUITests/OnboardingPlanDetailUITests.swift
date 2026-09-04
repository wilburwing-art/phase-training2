// OnboardingPlanDetailUITests.swift — tap a plan-preview day to see its detail.
//
// Before accepting the generated week, the user must be able to click into each
// lift/sport day and see the actual session (exercises for a lift). This drives
// onboarding to the plan-preview step, taps a lift day row, and confirms the
// read-only detail sheet lists exercises.

import XCTest

final class OnboardingPlanDetailUITests: XCTestCase {

    func test_planPreview_tapLiftDay_showsExercises() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset"]   // cold onboarding
        app.launch()

        step(app, "onboarding-continue-welcome", timeout: 10)
        let sport = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'onboarding-sport-'")).firstMatch
        XCTAssertTrue(sport.waitForExistence(timeout: 6), "a sport chip should appear")
        sport.tap()
        step(app, "onboarding-continue-sports")
        step(app, "onboarding-continue-sportSeasons")
        step(app, "onboarding-continue-availability")
        step(app, "onboarding-continue-equipment")
        step(app, "onboarding-continue-experience")
        step(app, "onboarding-continue-about")
        step(app, "onboarding-continue-eraAffinity")
        step(app, "onboarding-continue-constraints")
        // Consent is gated (T0-5): pick an option or Continue never enables.
        step(app, "onboarding-consent-off")
        step(app, "onboarding-continue-coachConsent")

        // On the plan preview. Wait for generation (the Accept button enables
        // and the rows appear together), then open a lift day.
        XCTAssertTrue(app.buttons["onboarding-continue-planPreview"].waitForExistence(timeout: 15),
                      "plan preview should present")
        let liftRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'plan-preview-day-lift-'")).firstMatch
        XCTAssertTrue(liftRow.waitForExistence(timeout: 10), "a lift day row should be tappable")
        liftRow.tap()

        // The read-only detail sheet lists the day's exercises.
        XCTAssertTrue(app.staticTexts["EXERCISES"].waitForExistence(timeout: 5),
                      "day detail should list exercises")
        XCTAssertTrue(app.buttons["day-detail-close"].exists, "detail should be dismissable")
    }

    private func step(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 8,
                      file: StaticString = #file, line: UInt = #line) {
        let b = app.buttons[id]
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "'\(id)' should appear", file: file, line: line)
        b.tap()
    }
}
