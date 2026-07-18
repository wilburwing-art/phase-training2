// OnboardingSportGateUITests.swift — the outdoor sport gate opened.
//
// After opening onboarding to authored-served outdoor sports, the Sports step
// must offer snowboarding + mountain biking (distilled authored coverage) while
// still hiding non-outdoor authored sports like golf. Launches into a fresh
// onboarding (reset, no --ui-test-onboarded) and inspects the Sports screen.

import XCTest

final class OnboardingSportGateUITests: XCTestCase {

    func test_outdoor_authored_sports_are_selectable_in_onboarding() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset"]
        app.launch()

        // Welcome → Sports.
        let welcomeNext = app.buttons["onboarding-continue-welcome"]
        XCTAssertTrue(welcomeNext.waitForExistence(timeout: 10), "onboarding should present")
        welcomeNext.tap()

        // Newly-plannable outdoor sports appear as primary-sport options.
        XCTAssertTrue(app.buttons["onboarding-sport-snowboarding"].waitForExistence(timeout: 5),
                      "snowboarding should be selectable")
        XCTAssertTrue(app.buttons["onboarding-sport-mountain-biking"].exists,
                      "mountain biking should be selectable")
        // Engine-supported sports are still there.
        XCTAssertTrue(app.buttons["onboarding-sport-climbing"].exists, "climbing should still be selectable")
        // A non-outdoor authored sport must NOT leak in.
        XCTAssertFalse(app.buttons["onboarding-sport-golf"].exists, "golf must not be offered")
    }
}
