// StoreScreenshotUITests.swift — the App Store listing's screenshots.
//
// Run on a 6.9 inch simulator (iPhone 17 Pro Max) and export the
// attachments; docs/store/README.md has the command. Each test seeds one
// state and attaches the screens that sell it, so the set is reproducible
// after any UI change rather than hand-captured once.

import XCTest

final class StoreScreenshotUITests: XCTestCase {

    /// Today, Week, Library and an exercise detail, from a seeded lift day.
    func test_planScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-plan-demo"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        attach(app, "01-today")

        app.tabBars.buttons["Week"].tap()
        XCTAssertTrue(app.tabBars.buttons["Week"].isSelected)
        attach(app, "02-week")

        app.tabBars.buttons["Library"].tap()
        let core = app.buttons["library-tile-core"]
        XCTAssertTrue(core.waitForExistence(timeout: 5))
        attach(app, "03-library")
        core.tap()
        let rollout = app.staticTexts["Ab Wheel Rollout"].firstMatch
        XCTAssertTrue(rollout.waitForExistence(timeout: 5))
        attach(app, "04-library-core")
        rollout.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "05-exercise-detail")
    }

    /// The Log screen mid-session with the Apple Music card.
    func test_logScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo",
                                "--ui-test-fake-now-playing"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["now-playing-toggle"].waitForExistence(timeout: 5))
        attach(app, "06-log")
    }

    /// A populated Progress tab.
    func test_progressScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-progress-demo"]
        app.launch()
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        XCTAssertTrue(progress.isSelected)
        attach(app, "07-progress")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
