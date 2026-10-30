import XCTest

/// Progress opens an exercise's strength card from TOP EXERCISES, and See all
/// lifts lists every lift.
final class YourLiftsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_topExerciseOpensStrength_andSeeAllListsLifts() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-imported-history"]
        app.launch()

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        let row = app.buttons["progress-top-exercise-Barbell Back Squat"]
        var swipes = 0
        while !row.isHittable && swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.isHittable, "the top exercise row is a button")
        XCTAssertTrue(row.label.contains("est max"), "row meta carries the estimate: \(row.label)")
        row.tap()
        XCTAssertTrue(app.otherElements["exercise-strength"].waitForExistence(timeout: 5)
                        || app.staticTexts["strength-estimate"].waitForExistence(timeout: 2),
                      "the row opens the strength card")
        app.buttons["Done"].firstMatch.tap()

        let seeAll = app.buttons["progress-see-all-lifts"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5))
        seeAll.tap()
        XCTAssertTrue(app.buttons["your-lifts-row-Barbell Back Squat"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "your-lifts"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
