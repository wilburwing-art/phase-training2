import XCTest

/// The exercise sheet's "Your strength" card reads the lifter's history.
final class ExerciseStrengthCardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openSquatDetail(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))
        let header = app.staticTexts["log-exercise-name-2"]   // Back Squat
        var swipes = 0
        while !header.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        header.tap()
        // The sheet's own Done button; "Back Squat" also matches the log row.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "detail sheet should open")
        return app
    }

    func test_importedHistory_showsTheCard() {
        let app = openSquatDetail(["--seed-imported-history"])
        // 100 kg x 5 = 220.5 lb x 5 -> est. max 257 lb.
        let estimate = app.staticTexts["strength-estimate"]
        var swipes = 0
        while !(estimate.exists && estimate.isHittable) && swipes < 4 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertEqual(estimate.label, "257 lb")
        XCTAssertTrue(app.staticTexts["Your strength"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "exercise-strength-card"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_noHistory_noCard() {
        let app = openSquatDetail([])
        XCTAssertFalse(app.staticTexts["Your strength"].waitForExistence(timeout: 2))
    }
}
