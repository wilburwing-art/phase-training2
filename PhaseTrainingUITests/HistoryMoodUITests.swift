import XCTest

/// History shows how a workout felt and the mood after it, and Edit session
/// sets the mood later (the only route for a watch-saved workout).
final class HistoryMoodUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_historyShowsMood_andEditSessionChangesIt() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-progress-demo"]
        app.launch()

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        let seeAll = app.buttons["progress-see-all-sessions"]
        var swipes = 0
        while !seeAll.isHittable && swipes < 12 { app.swipeUp(); swipes += 1 }
        seeAll.tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))

        // Newest seeded session: felt "Right", mood "better".
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-toggle-")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Felt right · Mood after: better"].waitForExistence(timeout: 5))

        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-edit-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let worse = app.buttons["mood-worse"]
        XCTAssertTrue(worse.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mood-better"].isSelected, "the sheet opens on the saved mood")
        worse.tap()
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Felt right · Mood after: worse"].waitForExistence(timeout: 5),
                      "History should show the mood set in Edit session")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-mood"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
