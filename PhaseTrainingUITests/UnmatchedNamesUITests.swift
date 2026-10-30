import XCTest

/// Health & Imports offers to match an imported name the catalog missed, and
/// matching it clears the row.
final class UnmatchedNamesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_matchingAnUnmatchedName() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset",
                                "--seed-imported-history", "--seed-unmatched-import"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let imports = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Health & Imports")).firstMatch
        var swipes = 0
        while !imports.isHittable && swipes < 10 { app.swipeUp(); swipes += 1 }
        imports.tap()

        let row = app.buttons["unmatched-names-row"]
        swipes = 0
        while !row.isHittable && swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.isHittable, "one unmatched name is offered")
        row.tap()
        let name = app.buttons["unmatched-name-Zercher Hold Thing"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "unmatched-names"
        shot.lifetime = .keepAlways
        add(shot)
        name.tap()

        let search = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Front Squat")
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Front Squat")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()

        XCTAssertTrue(app.staticTexts["Every imported name matches an exercise."].waitForExistence(timeout: 5))
    }
}
