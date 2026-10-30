import XCTest

/// Imported workouts show in Progress (recent sessions, PR feed) and in
/// History as read-only rows.
final class ImportedHistoryProgressUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_importedWorkoutsShowInProgressAndHistory() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-imported-history"]
        app.launch()

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        let seeAll = app.buttons["progress-see-all-sessions"]
        var swipes = 0
        while !seeAll.isHittable && swipes < 12 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(seeAll.isHittable, "imported workouts fill the recent sessions card")
        XCTAssertFalse(app.staticTexts["No PRs yet. Beat any prior set to land one."].exists,
                       "imported bests land in the PR feed")
        let progressShot = XCTAttachment(screenshot: app.screenshot())
        progressShot.name = "progress-imported"
        progressShot.lifetime = .keepAlways
        add(progressShot)

        seeAll.tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-toggle-")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Imported from Fitbod"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-edit-")).firstMatch.exists,
                       "imported workouts are read-only")
        let historyShot = XCTAttachment(screenshot: app.screenshot())
        historyShot.name = "history-imported"
        historyShot.lifetime = .keepAlways
        add(historyShot)
    }
}
