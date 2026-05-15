import XCTest

final class RoutineDetailSwipeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeRevealsActionsAndDeleteRemovesRow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        app.launch()

        // Phase 11 dropped the Train tab. Library is reachable from Today's
        // "Pick a different routine" link instead — it's below the exercise list
        // so we may need to scroll the ScrollView.
        let pickLink = app.buttons["today-pick-routine"]
        XCTAssertTrue(pickLink.waitForExistence(timeout: 4), "Today's pick-routine link should exist")
        if !pickLink.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(pickLink.isHittable, "pick-routine link should be tappable after scroll")
        pickLink.tap()

        // First routine card (coach.db id=1 → Climber Antagonist & Push).
        let firstCard = app.buttons["routine-card-1"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 4), "first routine card should exist")
        firstCard.tap()

        // Routine Detail: count rows before swipe.
        let firstRow = app.descendants(matching: .any)["routine-row-0"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 4), "first row should exist on routine detail")
        let initialRowCount = self.rowCount(in: app)
        XCTAssertGreaterThan(initialRowCount, 0)

        // Swipe the first row left.
        firstRow.swipeLeft()

        // Replace + Delete action buttons should now be visible.
        let deleteButton = app.buttons["routine-row-delete"]
        let replaceButton = app.buttons["routine-row-replace"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2), "DELETE should appear after swipe")
        XCTAssertTrue(replaceButton.exists, "REPLACE should also be visible")

        // Tap Delete and assert the row count drops.
        deleteButton.tap()

        // Allow the snap-back + 0.2s asyncAfter + spring + state mutation.
        Thread.sleep(forTimeInterval: 1.0)
        let originalFirstRow = firstRowLabel(in: app)
        print("UITEST: first row label after delete: \(originalFirstRow)")
        print("UITEST: row count after delete: \(rowCount(in: app))")
        // Soft assertion — initial intent: deleted row disappears.
        XCTAssertLessThan(rowCount(in: app), initialRowCount,
                          "row count should drop after Delete")
    }

    private func rowCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'routine-row-'"))
            .count
    }

    private func firstRowLabel(in app: XCUIApplication) -> String {
        let row = app.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier == 'routine-row-0'"))
            .firstMatch
        return row.exists ? (row.label) : ""
    }
}
