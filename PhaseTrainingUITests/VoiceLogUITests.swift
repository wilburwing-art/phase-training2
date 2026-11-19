import XCTest

final class VoiceLogUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_micTwiceShowsHeardCard() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded",
            "--ui-test-reset",
            "--seed-supersets-demo",
            "--ui-test-voice-transcript=185 for 5",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "should land in LogScreen with seeded session")

        let mic = app.descendants(matching: .any)["log-voice-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()
        XCTAssertTrue(app.descendants(matching: .any)["log-voice-listening"].waitForExistence(timeout: 5))
        mic.tap()

        let card = app.descendants(matching: .any)["log-voice-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("185"), "card label was: \(card.label)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "voice-heard-card"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
