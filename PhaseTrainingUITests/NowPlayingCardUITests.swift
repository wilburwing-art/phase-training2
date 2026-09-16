import XCTest

/// The media card above the tab bar on the Log screen. The simulator has no
/// Music app, so `--ui-test-fake-now-playing` injects a playing, authorised
/// fake; this proves the card lays out over the log and that the toggle
/// flips. Device behaviour against Apple Music is checked by hand.
final class NowPlayingCardUITests: XCTestCase {

    func test_cardShowsAboveTheLogAndToggles() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo",
                                "--ui-test-fake-now-playing"]
        app.launch()

        // The supersets seed is an ACTIVE session, so TodayTab routes
        // straight to the Log screen on launch (same landing LogFlowTests uses).
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 10),
                      "should land in LogScreen with the seeded session")

        let toggle = app.buttons["now-playing-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "media card should be on the Log screen")
        XCTAssertEqual(toggle.label, "Pause")
        XCTAssertTrue(app.staticTexts["Blinding Lights"].firstMatch.exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "log-now-playing"
        shot.lifetime = .keepAlways
        add(shot)

        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        XCTAssertTrue(app.buttons["now-playing-next"].exists)
    }
}
