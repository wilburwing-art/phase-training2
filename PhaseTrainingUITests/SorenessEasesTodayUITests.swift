import XCTest

/// End to end: a mild soreness check-in on Progress reshapes today's lift day and
/// Today says why. Seeds a ski athlete whose whole week is lift days, so today
/// is a lift day on any weekday.
final class SorenessEasesTodayUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_soreQuadsCheckIn_easesToday() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset",
                                "--seed-ski-primary", "--seed-plan-demo"]
        app.launch()

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        let pill = app.buttons["progress-soreness-checkin"]
        var swipes = 0
        while !pill.exists && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()

        app.buttons["soreness-energy-normal"].tap()
        app.buttons["soreness-severity-mild"].tap()
        let quads = app.buttons["soreness-area-quads"]
        swipes = 0
        while !quads.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
        quads.tap()
        app.buttons["soreness-save"].tap()

        app.tabBars.buttons["Today"].tap()
        let caption = app.staticTexts["Eased for sore quads."]
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "Today should say the workout was eased")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "soreness-eased-today"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
