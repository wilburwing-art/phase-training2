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
