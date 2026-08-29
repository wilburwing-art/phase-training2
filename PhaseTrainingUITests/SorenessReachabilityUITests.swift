// SorenessReachabilityUITests.swift — the soreness check-in has exactly one
// entry point, so a test guards it.
//
// Build 122 stripped Today down to the workout, which removed the pill that
// used to open SorenessCheckInSheet. That pill was the ONLY way into the
// sheet anywhere in the app, so removing it made a whole screen unreachable
// with nothing failing. The entry now lives on Progress under RECOVERY; this
// test exists so the same thing cannot happen again quietly.

import XCTest

final class SorenessReachabilityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSorenessCheckInIsReachableFromProgress() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "Progress tab should exist")
        progress.tap()

        // The pill sits under the RECOVERY header, below the fold on most
        // devices, so scroll it into view before asserting.
        let pill = app.buttons["progress-soreness-checkin"]
        var swipes = 0
        while !pill.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(pill.waitForExistence(timeout: 5),
                      "soreness check-in should be reachable from Progress")

        pill.tap()

        // The sheet is the thing we are proving reachable, so assert on its
        // own content rather than on the pill disappearing.
        let sheetMarker = app.staticTexts["OVERALL SORENESS"]
        let anySheet = app.sheets.firstMatch
        XCTAssertTrue(sheetMarker.waitForExistence(timeout: 5) || anySheet.waitForExistence(timeout: 5),
                      "tapping the pill should present SorenessCheckInSheet")
    }

    /// The populated branch. Progress renders `emptyState` until a session
    /// exists, and the two branches are separate view trees, so passing in one
    /// says nothing about the other. The first version of this change put the
    /// pill only in the populated branch and a new user could not reach it.
    func testSorenessCheckInIsReachableAfterASessionExists() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-plan-demo"]
        app.launch()

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "Progress tab should exist")
        progress.tap()

        let pill = app.buttons["progress-soreness-checkin"]
        var swipes = 0
        while !pill.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(pill.waitForExistence(timeout: 5),
                      "soreness check-in should be reachable on a populated Progress tab")
    }
}
