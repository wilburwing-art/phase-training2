import XCTest

/// Profile → Goal: the row starts on Sport performance, and picking Strength
/// sticks and shows on the row.
final class ProfileGoalUITests: XCTestCase {

    func test_pickStrengthGoal() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-ski-primary"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Goal")).firstMatch
        var swipes = 0
        while !row.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Goal row should exist")
        XCTAssertTrue(row.label.contains("Sport performance"), row.label)
        row.tap()

        let strength = app.buttons["goal-strength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        strength.tap()

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "profile-goal-sheet"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Strength"), row.label)
    }
}
