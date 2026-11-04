import XCTest

/// Gap pass 2026-10-31, phase 2: the history check without an import, and the
/// plate calculator from a barbell exercise in Log.
final class Phase2ReachUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Native sessions only, one of them 100 days back: a break, no import.
    func test_historyCheckShowsOnProgressWithoutAnImport() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-progress-demo"]
        app.launch()
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        let link = app.buttons["progress-history-check"]
        var swipes = 0
        while !(link.exists && link.isHittable) && swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(link.exists, "a native-only history with a break shows the check")
        XCTAssertTrue(link.label.contains("break"), link.label)
        link.tap()
        XCTAssertTrue(app.staticTexts["BREAKS OVER 8 WEEKS"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-check-from-progress"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_plateCalculatorOpensFromABarbellExerciseInLog() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        app.staticTexts["log-exercise-name-0"].press(forDuration: 1.0)
        let item = app.buttons["Plate calculator"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Bench Press is a barbell lift")
        item.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "135", "the next set's weight is pre-filled")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "plate-from-log"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Done"].tap()

        // DB Row needs no bar, so its menu has no plate calculator. Checked
        // last: an open context menu covers the rows around it.
        let row = app.staticTexts["log-exercise-name-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Show details"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Plate calculator"].exists)
    }
}
