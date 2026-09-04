// BuildAndStartWorkoutUITests.swift — Phase 1 verification.
//
// Proves the manual "build a workout → Start" path lands in the live log:
// Library → Workouts → Build a workout → add exercises → Start workout must
// create today's active session, switch to the Today tab, and route TodayTab
// to the log step (cross-tab routing). This is the wiring added in Phase 1.

import XCTest

final class BuildAndStartWorkoutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBuildAndStartWorkoutRoutesIntoLiveLog() throws {
        let app = XCUIApplication()
        // Onboarded + clean state, NO seed — so there are no saved workouts and
        // we exercise the fresh "Build a workout" path.
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()

        // Library tab → Workouts segment.
        let library = app.tabBars.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10), "Library tab should exist")
        library.tap()

        let workoutsSegment = app.buttons["Workouts"]
        XCTAssertTrue(workoutsSegment.waitForExistence(timeout: 5), "Workouts segment should exist")
        workoutsSegment.tap()

        // Build a workout (fresh blank routine → CustomRoutineEditSheet).
        let buildCTA = app.buttons["library-create-custom"]
        XCTAssertTrue(buildCTA.waitForExistence(timeout: 5), "Build a workout CTA should exist")
        buildCTA.tap()

        // Add two exercises via the picker (picker auto-dismisses on pick).
        for i in 0..<2 {
            let addButton = app.buttons["Add exercise"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add exercise button should exist (iteration \(i))")
            addButton.tap()

            let firstPickerRow = app.staticTexts
                .matching(NSPredicate(format: "identifier BEGINSWITH 'picker-row-name-'"))
                .firstMatch
            XCTAssertTrue(firstPickerRow.waitForExistence(timeout: 5), "Picker should show at least one exercise (iteration \(i))")
            firstPickerRow.tap()
        }

        // Start workout — the Phase 1 action under test.
        let startButton = app.buttons["custom-routine-start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start workout button should exist")
        startButton.tap()

        // Proof of the full chain: the live LogScreen's finish control appears.
        // That only happens if the active session was created, the sheet
        // dismissed, the tab switched to Today, and TodayTab routed to .log.
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 10),
                      "Starting a built workout should route into the live log (cross-tab)")
    }
}
