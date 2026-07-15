import XCTest

/// Primary/support model — the Support Sport editor sheet renders and wires
/// (PLAN-primary-support.md phase 2 UI). Drives the real UI: Profile tab →
/// Support sport row → enable Climbing → the discipline + weekly grid appear →
/// tapping a day's magnitude updates the footer. Also captures a screenshot so
/// the layout can be eyeballed.
final class SupportSportUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Ski-primary so the (ski/snow-gated) Support sport row appears; no
        // pattern seeded so the editor opens empty and the footer reads "1 day".
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-ski-primary"]
        app.launch()
        return app
    }

    func test_supportSportEditor_rendersAndWires() {
        let app = launch()

        // 1. Profile tab.
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        // 2. Open the Support sport row (SettingsRow button carries its label).
        let row = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "Support sport")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Support sport row should exist")
        row.tap()

        // 3. Sheet starts disabled — enabling Climbing reveals the grid.
        let climbing = app.buttons["Climbing"]
        XCTAssertTrue(climbing.waitForExistence(timeout: 5), "editor sheet should present")
        climbing.tap()

        // 4. Discipline + day grid now render.
        XCTAssertTrue(app.buttons["Trad / Alpine"].waitForExistence(timeout: 3),
                      "discipline chips should appear once enabled")
        XCTAssertTrue(app.buttons["Big"].firstMatch.waitForExistence(timeout: 3),
                      "per-day magnitude chips should appear")

        // 5. Wire: set the first day (Monday) to Big → footer reflects 1 day.
        app.buttons["Big"].firstMatch.tap()
        let footer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "day set")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 3),
                      "footer should confirm a day was set")

        // Visual record.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "support-sport-editor"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
