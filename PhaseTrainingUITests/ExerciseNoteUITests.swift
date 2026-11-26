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

        pressWhenHittable(app.staticTexts["log-exercise-name-0"], in: app, step: "add-note press")
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

        pressWhenHittable(app.staticTexts["log-exercise-name-0"], in: app, step: "edit-note press")
        XCTAssertTrue(app.buttons["Edit note"].waitForExistence(timeout: 3), "the menu says Edit once a note exists")
    }

    /// Log fades in from Today (0.18 s). A press during the fade fails with
    /// "Not hittable" (push run 45772390021), so wait for the row to settle.
    /// A 5 s wait still timed out once (push run 45851627266). CI uploads the
    /// flows xcresult only when the job fails and xcbeautify drops stdout, so
    /// the failure message carries what covers the row (11e 1.17).
    private func pressWhenHittable(_ el: XCUIElement, in app: XCUIApplication, step: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: el)
        guard XCTWaiter().wait(for: [hittable], timeout: 5) == .completed else {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "not-hittable-\(step)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("\(step): \(el) never became hittable. \(coverReport(el, in: app))", file: file, line: line)
            return
        }
        el.press(forDuration: 1.0)
    }

    /// One line naming the target's frame, any alert or keyboard, and the
    /// elements whose frames hold the target's centre, last-drawn first.
    private func coverReport(_ el: XCUIElement, in app: XCUIApplication) -> String {
        var parts = ["exists=\(el.exists)", "frame=\(el.exists ? "\(el.frame)" : "-")",
                     "window=\(app.windows.firstMatch.frame)"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alerts = springboard.alerts.allElementsBoundByIndex.map(\.label) + app.alerts.allElementsBoundByIndex.map(\.label)
        parts.append("alerts=\(alerts)")
        parts.append("keyboard=\(app.keyboards.firstMatch.exists)")
        parts.append("sheets=\(app.sheets.count)")
        guard el.exists, let root = try? app.snapshot() else {
            parts.append("snapshot=unavailable")
            return parts.joined(separator: " ")
        }
        let centre = CGPoint(x: el.frame.midX, y: el.frame.midY)
        var over: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.frame.contains(centre), node.elementType != .application, node.elementType != .window {
                over.append("\(node.elementType.rawValue):'\(node.identifier)':'\(node.label.prefix(30))'")
            }
            node.children.forEach(walk)
        }
        walk(root)
        parts.append("over=\(over.suffix(8).reversed())")
        return parts.joined(separator: " ")
    }
}
