import XCTest

/// Profile → Plan setup → Goal: the row starts on Sport performance, and picking
/// Strength sticks and shows on the checklist row.
final class ProfileGoalUITests: XCTestCase {

    func test_pickStrengthGoal() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-ski-primary"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Plan setup")).firstMatch
        var swipes = 0
        while !row.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Plan setup row should exist")
        row.tap()

        let goalRow = app.buttons["setup-checklist-row-goal"]
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5))
        XCTAssertTrue(goalRow.label.contains("Sport performance"), goalRow.label)
        goalRow.tap()

        let strength = app.buttons["goal-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        strength.tap()

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "profile-goal-sheet"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Done"].tap()
        XCTAssertTrue(goalRow.waitForExistence(timeout: 5))
        XCTAssertTrue(goalRow.label.contains("Strength"), goalRow.label)
    }
}
