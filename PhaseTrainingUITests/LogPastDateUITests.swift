import XCTest

/// Log a workout for an earlier time: the log screen takes the picked time,
/// and the saved workout keeps the picked length, not the seconds spent
/// logging it.
final class LogPastDateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_loggedForYesterday_savesWithThePickedLength() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        let chip = app.buttons["log-logged-for"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.label.contains("today"), chip.label)
        chip.tap()

        // The sheet opens on yesterday at 5:30 PM, 60 min.
        let save = app.buttons["logged-for-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.label.contains("60 min"), chip.label)

        let logAll = app.buttons["log-all-workout"]
        if logAll.exists { logAll.tap() }
        app.buttons["log-finish"].tap()

        // DURATION reads the picked hour, not the few seconds this test took.
        XCTAssertTrue(app.staticTexts["1:00:00"].waitForExistence(timeout: 8),
                      "Complete should show the picked 60 min")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "log-past-date-complete"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
