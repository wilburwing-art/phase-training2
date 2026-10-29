import XCTest

/// Last time 185 x 10, today 5 reps: the pill remaps proven strength to 5
/// reps (about 210 lb) instead of adding 5 lb to 185.
final class RepAwareSuggestionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_repGap_pillSuggestsALoadForTodaysReps() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset",
                                "--seed-rep-gap", "--seed-supersets-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        let pill = app.staticTexts["SUGGESTED · 210 lbs · for 5 reps"]
        var swipes = 0
        while !(pill.exists && pill.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(pill.exists, "the old rule would say 190 lbs (+5)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "rep-aware-pill"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
