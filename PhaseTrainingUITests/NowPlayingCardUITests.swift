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

    /// The last thing in the scroll content ends above the card's dock, so no
    /// set row or button is left under the card or the tab bar.
    func test_lastLogRowClearsTheCard() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo",
                                "--ui-test-fake-now-playing"]
        app.launch()

        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any)["now-playing-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "media card should show")

        let last = app.buttons["log-add-exercise"]
        let scroll = app.scrollViews.firstMatch
        var previousY = CGFloat.nan
        for _ in 0..<12 {
            let y = last.exists ? last.frame.minY : -1
            if y == previousY { break }
            previousY = y
            scroll.swipeUp()
        }

        XCTAssertTrue(last.exists && last.isHittable, "last scroll element should be hittable")
        XCTAssertLessThanOrEqual(last.frame.maxY, card.frame.minY,
                                 "last row maxY \(last.frame.maxY) should clear card minY \(card.frame.minY)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "log-now-playing-scrolled"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
