import XCTest

/// Profile > Data > Export workouts (CSV) hands a file to the share sheet.
final class WorkoutCSVExportUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_exportOpensTheShareSheet() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-progress-demo"]
        app.launch()
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let data = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Data")).firstMatch
        var swipes = 0
        while !data.isHittable && swipes < 10 { app.swipeUp(); swipes += 1 }
        data.tap()

        let export = app.buttons["profile-export-csv"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.isEnabled, "seeded sessions make the export available")
        export.tap()

        // UIActivityViewController names its list ActivityListView.
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "the share sheet appears with the CSV")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "csv-export-share"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
