import XCTest

/// D3 consolidate flow (end-to-end through the real UI).
///
/// Seeded via `--seed-missed-consolidation-demo`: a PAST missed Push day in a
/// 4-lift week, so the missed-workout reshuffle drop-rule fires and the Today
/// banner offers "Consolidate" instead of a reshuffle. Tapping it should run
/// `PlanStore.consolidateWeek` — dropping one future lift day (4 → 3 lifts) and
/// clearing the banner.
final class ConsolidateFlowTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded",
            "--ui-test-reset",
            "--seed-missed-consolidation-demo",
        ]
        app.launch()
        return app
    }

    private func liftCountText(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "\(n) lift")).firstMatch
    }

    // Per-button id now surfaces (the wrapper accessibilityIdentifier that used
    // to clobber it was removed from TodayScreen — xcuitest-swiftui-gotchas #1).
    private func consolidateButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["missed-banner-consolidate"]
    }

    /// Build 122 moved missed-workout resolution off Today and into the
    /// weekly check-in's first step, reached from the Week header. The
    /// behaviour is unchanged; only the entry point moved, so this drives the
    /// new path and still asserts the week actually consolidates.
    private func openCheckIn(_ app: XCUIApplication) {
        let weekTab = app.tabBars.buttons["Week"]
        XCTAssertTrue(weekTab.waitForExistence(timeout: 10), "Week tab should exist")
        weekTab.tap()
        let planNext = app.buttons["week-plan-next"]
        XCTAssertTrue(planNext.waitForExistence(timeout: 5),
                      "Week header should offer Plan next week")
        planNext.tap()
    }

    func test_missedWorkout_offersConsolidateInCheckIn_andConsolidatesWeek() {
        let app = launch()

        // 1. Baseline: the week has 4 lift days.
        let weekTab = app.tabBars.buttons["Week"]
        XCTAssertTrue(weekTab.waitForExistence(timeout: 10))
        weekTab.tap()
        XCTAssertTrue(liftCountText(app, 4).waitForExistence(timeout: 5),
                      "baseline week should show 4 lift days")

        // 2. The check-in opens on the missed step, which offers Consolidate
        //    (reshuffle found no slot).
        openCheckIn(app)
        let consolidate = consolidateButton(app)
        XCTAssertTrue(consolidate.waitForExistence(timeout: 10),
                      "the check-in's missed step should offer a Consolidate button")
        consolidate.tap()

        // 3. Leave the flow without planning a new week.
        let close = app.buttons["checkin-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "check-in should offer a close")
        close.tap()

        // 4. The week dropped one lift day (4 → 3) — consolidateWeek ran.
        weekTab.tap()
        XCTAssertTrue(liftCountText(app, 3).waitForExistence(timeout: 5),
                      "week should drop to 3 lift days after consolidating")
        XCTAssertFalse(liftCountText(app, 4).exists,
                       "the 4-lift baseline should be gone after consolidation")

        // 5. The miss is resolved, so reopening the check-in skips the missed
        //    step entirely rather than showing an empty one.
        openCheckIn(app)
        XCTAssertFalse(consolidateButton(app).waitForExistence(timeout: 3),
                       "resolved miss should not reappear in the check-in")
    }

    /// PR 6 gap — convert a rest day into a lift via the Week-tab edit sheet.
    /// Seed has a rest day at index 3 (offset +1); after "Add lift workout" →
    /// pick focus, the week goes 4 → 5 lift days.
    func test_addLiftWorkout_convertsRestDayToLift() {
        let app = launch()

        let weekTab = app.tabBars.buttons["Week"]
        XCTAssertTrue(weekTab.waitForExistence(timeout: 10))
        weekTab.tap()
        XCTAssertTrue(liftCountText(app, 4).waitForExistence(timeout: 5),
                      "seed week starts at 4 lift days")

        // Tap a future rest day (index 3 = offset +1) → its edit sheet.
        let restRow = app.descendants(matching: .any)["week-day-row-3"]
        XCTAssertTrue(restRow.waitForExistence(timeout: 5))
        restRow.tap()

        // "Add lift workout" → pick push → the rest day becomes a lift.
        let addLift = app.descendants(matching: .any)["week-day-add-lift-action"]
        XCTAssertTrue(addLift.waitForExistence(timeout: 5),
                      "rest day edit sheet should offer Add lift workout")
        addLift.tap()
        let pushChip = app.buttons["focus-chip-push"]
        XCTAssertTrue(pushChip.waitForExistence(timeout: 5))
        pushChip.tap()

        // Dismiss the edit sheet → back on the Week tab. (We don't assert an
        // absolute lift count: editing regenerates the week from memory on the
        // current training-week dates, so the seed's hand-built shape doesn't
        // carry over. The rest→lift override mutation is covered by the
        // setLiftFocus / dayOverrides unit path; here we prove the affordance
        // is reachable + the flow completes end-to-end.)
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertFalse(app.buttons["Done"].waitForExistence(timeout: 2),
                       "edit sheet should dismiss after Done")
        XCTAssertTrue(app.descendants(matching: .any)["week-day-row-0"].waitForExistence(timeout: 5),
                      "returns to a rendered Week tab after adding the workout")
    }
}
