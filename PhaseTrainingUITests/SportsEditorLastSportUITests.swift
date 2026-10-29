import XCTest

/// Deselecting the last sport left `primarySport` nil, and every lift day in
/// the rebuilt week came back as an empty "Rest". The Sports editor now keeps
/// the last sport selected and says why.
final class SportsEditorLastSportUITests: XCTestCase {

    func test_lastSportCannotBeRemoved() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-ski-primary"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        let row = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH %@", "Sports")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Sports row should exist")
        row.tap()

        let caption = app.staticTexts["Keep at least one sport. Pick another first to switch."]
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "caption shows with one sport")

        app.buttons["Alpine Skiing"].firstMatch.tap()

        // The caption renders only while exactly one sport is selected, so it
        // still being there means the tap did not empty the list.
        XCTAssertTrue(caption.waitForExistence(timeout: 2), "the last sport was removed")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "sports-editor-last-sport"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
