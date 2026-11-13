import XCTest

/// Custom exercises on screen: create from the picker, log it, find it in
/// History, delete it from its detail sheet, and the name-taken error.
final class CustomExerciseUITests: XCTestCase {

    private let customName = "Zorblax Cable Twist"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIApplication().screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
        var n = 0
        while !(el.exists && el.isHittable) && n < 12 { app.swipeUp(); n += 1 }
        XCTAssertTrue(el.exists && el.isHittable, "could not scroll to \(el)")
    }

    private func startFreestyle(_ app: XCUIApplication) {
        let freestyle = app.buttons["today-freestyle"]
        let trainAnyway = app.buttons["today-train-anyway"]
        XCTAssertTrue(freestyle.waitForExistence(timeout: 10) || trainAnyway.exists,
                      "Today offers Freestyle directly or via Train anyway")
        if freestyle.exists {
            freestyle.tap()
        } else {
            trainAnyway.tap()
            let row = app.buttons["override-freestyle"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
    }

    private func pickerRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'picker-row-name-'"))
    }

    private func type(_ text: String, into app: XCUIApplication) {
        let search = app.textFields["picker-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(text)
    }

    func testCreateLogAndDeleteACustomExercise() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()

        // 1. Freestyle opens the picker. Remember a catalog name for step 8.
        startFreestyle(app)
        let firstRow = pickerRows(app).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        let catalogName = firstRow.label
        XCTAssertFalse(catalogName.isEmpty)

        // 2. A name the library lacks offers Create.
        type(customName, into: app)
        let create = app.buttons["picker-create-custom"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), "no create button for an unknown name")
        shot("1-picker-create-offered")

        // 3. Create sheet is prefilled; pick a muscle; create.
        create.tap()
        let nameField = app.textFields["custom-exercise-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, customName)
        let chip = app.buttons["custom-exercise-bucket-core"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3))
        chip.tap()
        shot("2-create-sheet")
        app.buttons["custom-exercise-create"].tap()

        // 4. Picker closed, exercise is in the log.
        let first = app.staticTexts["log-exercise-name-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8), "created exercise did not reach the log")
        XCTAssertTrue(first.label.localizedCaseInsensitiveContains(customName), first.label)
        XCTAssertFalse(app.textFields["picker-search"].exists, "picker should have closed")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "(-)")).firstMatch.exists,
                       "custom exercise header must not show an empty modality")
        shot("3-log-has-custom")

        // 5. Log a set, finish, find it in History.
        // A custom exercise logs as weight x reps: the weight field shows
        // without tapping BW.
        XCTAssertFalse(app.buttons["log-set-bodyweight-0-0"].exists, "custom exercise must not log as bodyweight")
        let weight = app.textFields["log-set-weight-0-0"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5), "first set should show a weight field")
        weight.tap()
        weight.typeText("20")
        let reps = app.textFields["log-set-reps-0-0"]
        reps.tap()
        reps.typeText("10")
        app.buttons["log-set-check-0-0"].tap()
        let finish = app.buttons["log-finish"]
        XCTAssertTrue(finish.isHittable)
        finish.tap()
        let confirm = app.alerts.buttons["Finish"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        let done = app.buttons["complete-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "complete screen did not appear")
        shot("4-complete")
        done.tap()
        let skip = app.buttons["feedback-skip"]
        if skip.waitForExistence(timeout: 4) { skip.tap() }

        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        let seeAll = app.buttons["progress-see-all-sessions"]
        var swipes = 0
        while !seeAll.isHittable && swipes < 12 { app.swipeUp(); swipes += 1 }
        seeAll.tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-toggle-")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let inHistory = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", customName)).firstMatch
        XCTAssertTrue(inHistory.waitForExistence(timeout: 5), "History does not show \(customName)")
        shot("5-history")

        // 6. A second session: search a fragment, open the custom row's detail.
        let back = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "Back")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        startFreestyle(app)
        XCTAssertTrue(pickerRows(app).firstMatch.waitForExistence(timeout: 8))
        type("zorblax", into: app)
        let customRow = app.staticTexts["picker-row-name-\(customName)"]
        XCTAssertTrue(customRow.waitForExistence(timeout: 5), "custom row missing from search")
        XCTAssertTrue(app.buttons["picker-create-custom"].exists,
                      "partial query should still offer Create")
        app.buttons["Show details for \(customName)"].tap()
        XCTAssertTrue(app.staticTexts["Custom exercise"].waitForExistence(timeout: 5))
        let delete = app.buttons["custom-exercise-delete"]
        scrollTo(delete, in: app)
        shot("6-custom-detail")
        delete.tap()
        let dialogDelete = app.sheets.buttons["Delete exercise"]
        XCTAssertTrue(dialogDelete.waitForExistence(timeout: 5), "no delete confirmation")
        shot("7-delete-confirm")
        dialogDelete.tap()

        // 7. Row gone, Create offered again.
        XCTAssertTrue(app.textFields["picker-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["picker-create-custom"].waitForExistence(timeout: 5))
        XCTAssertFalse(customRow.exists, "deleted exercise still listed")
        shot("8-after-delete")

        // 8. A catalog name is refused.
        app.buttons["picker-create-custom"].tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        let existing = (nameField.value as? String) ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        nameField.typeText(catalogName)
        app.buttons["custom-exercise-create"].tap()
        XCTAssertTrue(app.staticTexts["custom-exercise-error"].waitForExistence(timeout: 5),
                      "name-taken error did not show")
        XCTAssertTrue(nameField.exists, "sheet should stay open")
        shot("9-name-taken")
    }
}
