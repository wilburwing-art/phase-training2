import XCTest

/// An exercise with imported history and no native log gets a weight from
/// proven strength: 100 kg x 5 (220.5 lb) maps to 5 reps as 220 lb.
final class ImportedHistorySuggestionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_importedOnlyExercise_showsAFromHistorySuggestion() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset",
                                "--seed-supersets-demo", "--seed-imported-history"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        let pill = app.staticTexts["SUGGESTED · 220 lbs · from history"]
        var swipes = 0
        while !(pill.exists && pill.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(pill.waitForExistence(timeout: 5),
                      "Back Squat should show the history suggestion")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "log-from-history"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
