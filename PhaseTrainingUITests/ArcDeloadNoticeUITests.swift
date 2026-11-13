import XCTest

/// After three build weeks the week is lighter, labelled DELOAD on Today and
/// noted on the Week tab with a "Train normally" button that declines it.
final class ArcDeloadNoticeUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-onboarded",
            "--ui-test-reset",
            "--seed-plan-demo",
            "--seed-arc-deload",
        ]
        app.launch()
        return app
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        add(shot)
    }

    private func deloadLabels(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "DELOAD"))
    }

    func test_weekNotice_showsAndDeclineRemovesIt() {
        let app = launch()

        XCTAssertTrue(deloadLabels(app).firstMatch.waitForExistence(timeout: 10),
                      "Today eyebrow should end in DELOAD")

        let weekTab = app.tabBars.buttons["Week"]
        XCTAssertTrue(weekTab.waitForExistence(timeout: 10))
        weekTab.tap()

        let notice = app.staticTexts["arc-deload-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "arc deload notice should show on Week")
        XCTAssertEqual(notice.label, "Three hard weeks in a row, so this week is lighter")
        let decline = app.buttons["arc-deload-decline"]
        XCTAssertTrue(decline.exists)
        XCTAssertTrue(decline.isHittable)

        for idx in 0..<7 {
            let row = app.descendants(matching: .any)["week-day-row-\(idx)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "week-day-row-\(idx) missing")
            XCTAssertTrue(row.isHittable, "week-day-row-\(idx) not hittable with the notice showing")
        }
        attachScreenshot("week-arc-deload")

        decline.tap()
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: notice)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "declining should remove the notice")
        attachScreenshot("week-after-decline")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertEqual(deloadLabels(app).count, 0, "Today should no longer read DELOAD")
    }
}
