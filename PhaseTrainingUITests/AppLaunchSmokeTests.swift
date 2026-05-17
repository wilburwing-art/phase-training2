// AppLaunchSmokeTests.swift — minimal UI test so the bundle has an
// executable. Replace with real flows when there are coverage targets
// worth automating.

import XCTest

final class AppLaunchSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesWithoutCrash() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8),
                      "app should reach foreground within 8s")
    }
}
