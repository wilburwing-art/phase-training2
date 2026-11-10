import XCTest

/// "Freestyle" on Today: one tap opens an empty session with the picker up,
/// a second tap puts the first exercise in the log.
final class FreestyleWorkoutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_freestyleStartsAnEmptySessionWithThePickerOpen() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()

        // Lift and sport days show the pill; rest and event days route
        // Freestyle through "Train anyway". Which one today is depends on
        // the seeded plan and the weekday, so accept either path.
        let freestyle = app.buttons["today-freestyle"]
        let trainAnyway = app.buttons["today-train-anyway"]
        XCTAssertTrue(freestyle.waitForExistence(timeout: 10) || trainAnyway.exists,
                      "Today offers Freestyle directly or via Train anyway")
        if freestyle.exists {
            XCTAssertFalse(trainAnyway.exists, "the two never show together")
            freestyle.tap()
        } else {
            trainAnyway.tap()
            let row = app.buttons["override-freestyle"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }

        let pickerRow = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'picker-row-name-'")
        ).firstMatch
        XCTAssertTrue(pickerRow.waitForExistence(timeout: 5),
                      "an empty session opens the picker without a second tap")
        let picked = pickerRow.label
        pickerRow.tap()

        let first = app.staticTexts["log-exercise-name-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.localizedCaseInsensitiveContains(picked) || picked.isEmpty,
                      "\(first.label) vs \(picked)")
        XCTAssertFalse(app.staticTexts["log-exercise-name-1"].exists)
        XCTAssertTrue(app.buttons["log-finish"].exists)
        XCTAssertTrue(app.buttons["log-add-exercise"].exists || { app.swipeUp(); return app.buttons["log-add-exercise"].exists }())

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "freestyle-first-exercise"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
