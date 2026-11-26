import XCTest

/// A note added from an exercise's menu in Log shows under its name.
final class ExerciseNoteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_addNoteFromTheExerciseMenu() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-supersets-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["log-finish"].waitForExistence(timeout: 8))

        pressWhenHittable(app.staticTexts["log-exercise-name-0"])
        let addNote = app.buttons["Add note"]
        XCTAssertTrue(addNote.waitForExistence(timeout: 3))
        addNote.tap()
        let field = app.textFields["exercise-note-field"].exists
            ? app.textFields["exercise-note-field"] : app.textViews["exercise-note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("seat 4")
        app.buttons["Done"].tap()

        // The note lines sit inside one Button, which merges its children.
        let note = app.buttons["log-exercise-notes-0"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("seat 4"), note.label)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "exercise-note-in-log"
        shot.lifetime = .keepAlways
        add(shot)

        pressWhenHittable(app.staticTexts["log-exercise-name-0"])
        XCTAssertTrue(app.buttons["Edit note"].waitForExistence(timeout: 3), "the menu says Edit once a note exists")
    }

    /// Log fades in from Today (0.18 s). A press during the fade fails with
    /// "Not hittable" (push run 45772390021), so wait for the row to settle.
    private func pressWhenHittable(_ el: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: el)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed,
                       "\(el) never became hittable", file: file, line: line)
        el.press(forDuration: 1.0)
    }
}
