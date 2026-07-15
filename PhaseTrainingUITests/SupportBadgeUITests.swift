import XCTest

/// Week-tab SupportBadge (primary/support polish). --seed-support-demo sets a
/// ski-primary + climbing-support (Tue medium, Sat big) plan; the Week tab
/// should render the magnitude badge on those days. Screenshots for eyeballing.
final class SupportBadgeUITests: XCTestCase {

    func test_weekTab_showsSupportMagnitudeBadge() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-support-demo"]
        app.launch()

        let week = app.tabBars.buttons["Week"]
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.tap()

        // The seeded week has two climbing days; the row title is the bare
        // sport name and the magnitude rides in the badge.
        XCTAssertTrue(app.staticTexts["Climbing"].firstMatch.waitForExistence(timeout: 5),
                      "seeded climbing support days should render on the Week tab")
        // Badge labels (BIG / MED) appear as their own text elements.
        XCTAssertTrue(app.staticTexts["BIG"].firstMatch.waitForExistence(timeout: 3),
                      "a big support day should show the BIG magnitude badge")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "week-support-badges"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
