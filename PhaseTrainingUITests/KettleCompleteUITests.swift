// KettleCompleteUITests.swift — Mr Kettle's debut beat.
//
// The flex loop lands on CompleteScreen. Drives a seeded session -> Finish ->
// complete, confirming the screen presents (the mascot is a TimelineView-driven
// Canvas, the one place a paint/loop bug would surface) and grabbing a frame.

import XCTest

final class KettleCompleteUITests: XCTestCase {

    func test_completeScreen_presentsWithKettle() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo"]
        app.launch()

        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8),
                      "seeded session should land in the log")
        app.buttons["log-finish"].tap()

        // T1-3: Finish confirms while sets are still open, and the supersets
        // seed leaves 13 of 15 undone. Alert buttons are keyed by label.
        // Scope to the alert: LogScreen's own Finish button is still behind
        // it, so an app-wide query matches two.
        let finishConfirm = app.alerts.buttons["Finish"]
        XCTAssertTrue(finishConfirm.waitForExistence(timeout: 5),
                      "open sets should raise the finish confirm")
        finishConfirm.tap()

        XCTAssertTrue(app.buttons["complete-done"].waitForExistence(timeout: 8),
                      "finishing should present the complete screen (with Mr Kettle) without crashing")

        // Let a couple of loop frames render, then capture.
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "complete-kettle-flex"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
