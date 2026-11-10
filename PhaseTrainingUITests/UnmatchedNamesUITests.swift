import XCTest

/// Health & Imports offers to match an imported name the catalog missed, and
/// matching it clears the row.
final class UnmatchedNamesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// "Not a lift" takes the name off the list; Undo puts it back.
    func test_notALiftAndUndo() {
        let app = openUnmatchedSheet()
        let ignore = app.buttons["unmatched-ignore-Zercher Hold Thing"]
        XCTAssertTrue(ignore.waitForExistence(timeout: 5))
        ignore.tap()
        XCTAssertTrue(app.staticTexts["Nothing left to match."].waitForExistence(timeout: 5))
        let undo = app.buttons["unmatched-unignore-Zercher Hold Thing"]
        XCTAssertTrue(undo.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "unmatched-not-a-lift"
        shot.lifetime = .keepAlways
        add(shot)
        undo.tap()
        XCTAssertTrue(app.buttons["unmatched-ignore-Zercher Hold Thing"].waitForExistence(timeout: 5))
    }

    private func openUnmatchedSheet() -> XCUIApplication {
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
        return app
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
