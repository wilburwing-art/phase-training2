import XCTest

/// A 900 lb typo among 225 lb imported squats: History check lists it, and
/// the "from history" suggestion stays at 225.
final class HistoryCheckUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_typoSetIsListed_andKeptOutOfTheSuggestion() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset",
                                "--seed-supersets-demo", "--seed-history-typo"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        let pill = app.staticTexts["SUGGESTED · 225 lbs · from history"]
        var swipes = 0
        while !(pill.exists && pill.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(pill.exists, "the 900 lb typo must not lift the suggestion")
    }

    func test_historyCheckListsTheTypo() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-history-typo"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let health = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Health & Imports")).firstMatch
        var swipes = 0
        while !health.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        health.tap()

        let row = app.buttons["history-check-row"]
        swipes = 0
        while !(row.exists && row.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("1 set that looks like a typo"), row.label)
        row.tap()

        let flag = app.staticTexts.matching(identifier: "history-check-flag").firstMatch
        XCTAssertTrue(flag.waitForExistence(timeout: 5))
        XCTAssertTrue(flag.label.contains("900 lb"), flag.label)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-check"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
