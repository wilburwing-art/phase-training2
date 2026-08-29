// WorkoutWheelUITests.swift — Today's title is the workout switcher.
//
// Asserts on the EXERCISE LIST rather than on the title, because a title that
// changes proves only that a label moved. The list changing proves the
// override actually reached PlanStore, regenerated the plan, and re-composed
// the day's workout — the whole path.

import XCTest

final class WorkoutWheelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded", "--ui-test-reset",
            "--seed-plan-demo",        // 5-exercise planned push day
            "--seed-saved-workouts",   // 3 saved routines to switch to
        ]
        app.launch()
        return app
    }

    /// A BUTTON, not an otherElement: the wheel carries an adjustable action
    /// plus a default action, so XCUITest types it as interactive.
    private func wheel(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["today-workout-wheel"]
    }

    func testSwipingTheTitleSwitchesTodaysWorkout() {
        let app = launch()

        // Planned: the seeded push day, 5 exercises.
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 10),
                      "planned workout should be showing")
        XCTAssertTrue(app.staticTexts["Lateral Raise"].exists,
                      "planned workout has a 4th exercise")
        XCTAssertTrue(app.staticTexts["Tricep Pushdown"].exists,
                      "planned workout has a 5th exercise")

        // Swipe the title to the first saved workout ("Quick Push", 3 lifts).
        let w = wheel(app)
        XCTAssertTrue(w.waitForExistence(timeout: 5),
                      "the title wheel should exist when saved workouts are present")
        w.swipeLeft()

        // The override took effect: the 4th exercise is gone, and the three
        // from the saved routine are showing.
        XCTAssertTrue(app.staticTexts["Overhead Press"].waitForExistence(timeout: 5))
        let laterals = app.staticTexts["Lateral Raise"]
        XCTAssertFalse(laterals.waitForExistence(timeout: 3),
                       "the planned workout's 4th exercise should be gone after switching")

        // Swipe back to the planned session: the override clears and the
        // original workout returns.
        w.swipeRight()
        XCTAssertTrue(app.staticTexts["Lateral Raise"].waitForExistence(timeout: 5),
                      "swiping back to the planned stop should restore the plan exactly")
        XCTAssertTrue(app.staticTexts["Tricep Pushdown"].exists,
                      "the whole planned workout should be back, not a re-derived one")
    }

    /// With nothing to switch to, the wheel is not rendered at all — a scroll
    /// gesture that cannot go anywhere is worse than a plain title.
    func testNoWheelWhenThereAreNoSavedWorkouts() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-plan-demo"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 10))
        XCTAssertFalse(wheel(app).exists,
                       "a single-stop wheel should not render")
    }
}
