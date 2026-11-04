import XCTest

/// Timed prescriptions show as written in Log, the hold timer runs a set,
/// and the finger-strength card logs a max-hang test.
final class HoldTimerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_holdTimerRunsASetAndMarksItDone() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-hang-demo",
                                "--ui-test-hold-seconds=1", "--ui-test-suppress-auto-rest"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        let label = app.staticTexts["log-reps-label-0"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.label, "Target: 8s hold", "the hold reads as a hold, not 8 reps")
        XCTAssertEqual(app.staticTexts["log-reps-label-1"].label, "Target: 6 hangs (7s on / 3s off)")

        app.buttons["log-hold-timer-0"].tap()
        let start = app.buttons["hold-timer-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["HOLD"].waitForExistence(timeout: 4), "get ready hands over to the hold")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "hold-timer-hang"
        shot.lifetime = .keepAlways
        add(shot)
        let done = app.buttons["hold-timer-mark-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 6))
        done.tap()

        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1/8 sets logged"].exists
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1/8 sets")).firstMatch.exists,
                      "the timer marked one set done")
    }

    func test_fingerCardLogsAMaxHang() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-climber"]
        app.launch()
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        let latest = app.staticTexts["progress-finger-latest"]
        var swipes = 0
        while !(latest.exists && latest.isHittable) && swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertEqual(latest.label, "129% of body weight")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "finger-card"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["progress-finger-log"].tap()
        let added = app.textFields["max-hang-added"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        // The seeded climber uses pounds: 62 lb is 28.1 kg, so (70 + 28.1) / 70.
        added.typeText("62")
        XCTAssertTrue(app.staticTexts["max-hang-preview"].waitForExistence(timeout: 3))
        app.buttons["max-hang-save"].tap()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertEqual(latest.label, "140% of body weight", "the new test is the latest")
    }
}
