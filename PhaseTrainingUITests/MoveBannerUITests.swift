import XCTest

/// Moving a workout keeps it and offers "Re-plan week" in a banner, through
/// the day editor's "Move workout to another day" (the drag gesture calls the
/// same PlanStore.swap and is not drivable from XCUITest).
final class MoveBannerUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded",
            "--ui-test-reset",
            "--seed-missed-consolidation-demo",
            // A supported primary sport, as every onboarded user has. Without
            // one the move's regenerate titles each lift "Rest" (11c 5.4).
            "--seed-ski-primary",
        ]
        app.launch()
        return app
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_moveWorkout_showsBanner_andReplanClearsIt() {
        let app = launch()
        let weekTab = app.tabBars.buttons["Week"]
        XCTAssertTrue(weekTab.waitForExistence(timeout: 10))
        weekTab.tap()

        // Open each day until one offers the move action (a lift day).
        let moveAction = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "Move workout to another day")).firstMatch
        var opened = false
        for idx in 0..<7 {
            let row = app.descendants(matching: .any)["week-day-row-\(idx)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            if moveAction.waitForExistence(timeout: 2) { opened = true; break }
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(opened, "no day in the seeded week offered Move workout")
        moveAction.tap()

        let restTarget = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "rest")).firstMatch
        XCTAssertTrue(restTarget.waitForExistence(timeout: 5), "move picker should list a rest day")
        restTarget.tap()

        let done = app.buttons["Done"]
        if done.waitForExistence(timeout: 3) { done.tap() }

        let banner = app.buttons["move-banner-replan"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "move banner should appear on the Week tab")
        attachScreenshot("move-banner")

        // Row labels read "<day>, LIFT, <title>, ...": no lift row is titled Rest.
        var liftRows = 0
        for idx in 0..<7 {
            let label = app.descendants(matching: .any)["week-day-row-\(idx)"].label
            guard label.contains(", LIFT, ") else { continue }
            liftRows += 1
            XCTAssertFalse(label.contains(", LIFT, Rest"), "lift row titled Rest: \(label)")
        }
        XCTAssertGreaterThan(liftRows, 0, "no LIFT row found after the move")

        // Outlasts the old 6 second auto-clear.
        sleep(8)
        XCTAssertTrue(banner.exists, "move banner should stay until dismissed")
        XCTAssertTrue(app.buttons["move-banner-close"].exists, "move banner should offer a close button")

        banner.tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 2), "Re-plan week should clear the banner")
        attachScreenshot("after-replan")
    }
}
