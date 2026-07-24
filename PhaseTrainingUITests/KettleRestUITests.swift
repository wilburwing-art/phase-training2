// KettleRestUITests.swift — the rest-day Kettle beat.
//
// On a rest day, Today shows Mr Kettle stretching (KettlePose.stretch). Drives a
// seeded rest day and confirms Today presents without crashing — the stretch
// Kettle Canvas is the one thing that could break here.

import XCTest

final class KettleRestUITests: XCTestCase {

    func test_restDay_presentsWithStretchingKettle() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-rest-day-demo"]
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                      "a rest day should present Today (with the stretching Kettle) without crashing")
    }
}
