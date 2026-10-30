import XCTest

/// A new user meets the goal as a Week chip and past workouts as a Plan setup
/// row, and answering either retires it.
final class SetupGoalHistoryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_goalChip_andPastWorkoutsRow() {
        let app = XCUIApplication()
        // Drive the real gate so the Week tab has a committed plan and its chips.
        app.launchArguments += ["--ui-test-reset"]
        app.launch()
        step(app, "onboarding-continue-welcome", timeout: 10)
        let sport = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding-sport-'")).firstMatch
        XCTAssertTrue(sport.waitForExistence(timeout: 6))
        sport.tap()
        step(app, "onboarding-continue-sports")
        step(app, "onboarding-continue-sportSeasons")
        step(app, "onboarding-health-off")
        step(app, "onboarding-continue-health")
        step(app, "onboarding-consent-off")
        step(app, "onboarding-continue-coachConsent", timeout: 15)

        let week = app.tabBars.buttons["Week"]
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.tap()
        let goalChip = app.buttons["assumption-chip-goal"]
        XCTAssertTrue(goalChip.waitForExistence(timeout: 10), "the goal reads as assumed on a fresh install")
        XCTAssertFalse(app.buttons["assumption-chip-history"].exists, "past workouts has no Week chip")
        var swipes = 0
        while !goalChip.isHittable && swipes < 4 { app.buttons["assumption-chip-availability"].swipeLeft(); swipes += 1 }
        goalChip.tap()
        let strength = app.buttons["goal-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5), "the chip opens the goal editor")
        strength.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(goalChip.waitForNonExistence(timeout: 5), "picking a goal retires the chip")

        app.tabBars.buttons["Profile"].tap()
        let setup = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Plan setup")).firstMatch
        swipes = 0
        while !setup.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        setup.tap()
        let row = app.buttons["setup-checklist-row-history"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not imported yet"].exists)
        let checklistShot = XCTAttachment(screenshot: app.screenshot())
        checklistShot.name = "setup-checklist"
        checklistShot.lifetime = .keepAlways
        add(checklistShot)

        row.tap()
        XCTAssertTrue(app.buttons["Import Fitbod CSV"].waitForExistence(timeout: 5), "the row opens the import")
        let sheetShot = XCTAttachment(screenshot: app.screenshot())
        sheetShot.name = "past-workouts-sheet"
        sheetShot.lifetime = .keepAlways
        add(sheetShot)
        app.buttons["past-workouts-starting-fresh"].tap()
        XCTAssertTrue(app.staticTexts["Done"].waitForExistence(timeout: 5), "starting fresh answers the row")
    }

    private func step(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 8) {
        let b = app.buttons[id]
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "'\(id)' should appear")
        b.tap()
    }
}
