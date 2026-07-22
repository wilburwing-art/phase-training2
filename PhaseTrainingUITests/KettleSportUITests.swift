// KettleSportUITests.swift — the sport-matched Kettle beat.
//
// On a sport day, the Today card shows Mr Kettle doing the user's actual sport
// (KettlePose.forSport). This drives a seeded SNOWBOARDING day and confirms
// Today presents with its log CTA — i.e. the sport-matched Kettle Canvas
// renders without crashing.

import XCTest

final class KettleSportUITests: XCTestCase {

    func test_snowSportDay_presentsWithCarvingKettle() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-snow-sport-demo"]
        app.launch()

        XCTAssertTrue(app.buttons["today-log-sport"].waitForExistence(timeout: 10),
                      "a snow sport day should present the log CTA (with the carving Kettle above it)")
    }
}
