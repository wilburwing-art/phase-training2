import XCTest

final class RoutineDetailSwipeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeRevealsActionsAndDeleteRemovesRow() throws {
        let app = XCUIApplication()
        app.launch()

        // Start → Browse routines.
        let routinesButton = app.buttons["start-routines-button"]
        XCTAssertTrue(routinesButton.waitForExistence(timeout: 4), "routines entry should be on start")
        routinesButton.tap()

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

        // Wait for the snap-then-delete animation (0.2s asyncAfter + spring).
        let predicate = NSPredicate(format: "self < %d", initialRowCount)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: NSNumber(value: rowCount(in: app))
        )
        // Re-evaluate in a poll loop since the count is captured at expectation
        // creation otherwise.
        let deadline = Date().addingTimeInterval(2)
        var finalCount = initialRowCount
        while Date() < deadline {
            finalCount = rowCount(in: app)
            if finalCount < initialRowCount { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        _ = expectation // silence unused warning
        XCTAssertEqual(finalCount, initialRowCount - 1,
                       "row count should drop by one after Delete")
    }

    private func rowCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'routine-row-'"))
            .count
    }
}
