import XCTest

/// A skier's Progress tab: the season's days on snow, and logging a
/// pre-season ski test.
final class SkiCardsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func test_skiSeasonCountsTheLoggedDay_andATestLogs() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-ski-season",
                                "--ui-test-hold-seconds=1"]
        app.launch()
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        let days = app.staticTexts["progress-ski-days"]
        var swipes = 0
        while !(days.exists && days.isHittable) && swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertEqual(days.label, "1 day", "the seeded ski day, with no Health data in the simulator")

        let log = app.buttons["progress-ski-log"]
        swipes = 0
        while !(log.exists && log.isHittable) && swipes < 5 { app.swipeUp(); swipes += 1 }
        log.tap()
        let wallSit = app.textFields["ski-test-wall-sit"]
        XCTAssertTrue(wallSit.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ski-test-save"].isEnabled, "an empty test does not save")
        // The hold timer counts a balance test up and writes the seconds in.
        app.buttons["ski-test-balance-left-timer"].tap()
        let start = app.buttons["hold-timer-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let count = app.staticTexts["hold-timer-count"]
        let held = NSPredicate(format: "label == '1'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: held, evaluatedWith: count)], timeout: 6), .completed,
                       "the stopwatch counts up after the get-ready")
        app.buttons["hold-timer-stop"].tap()
        let balance = app.textFields["ski-test-balance-left"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertTrue(["1", "2"].contains(balance.value as? String ?? ""),
                      "Stop writes the seconds held into the field; got \(String(describing: balance.value))")

        wallSit.tap()
        wallSit.typeText("90")
        app.buttons["ski-test-keyboard-done"].tap()
        let hops = app.textFields["ski-test-hops"]
        hops.tap()
        hops.typeText("40")
        app.buttons["ski-test-save"].tap()

        let row = app.staticTexts["progress-ski-wallSit"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "90s")
        XCTAssertEqual(app.staticTexts["progress-ski-lateralHops"].label, "40 in 30s")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ski-cards"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
