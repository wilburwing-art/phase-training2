import XCTest

/// Era-affinity step copy (jargon-free descriptors). Drives onboarding to the
/// "Your training era" step for a seeded (ski-primary, age 33) user and
/// screenshots it, so the plain-language descriptor + dimmed "Sound familiar?"
/// program line can be eyeballed.
final class EraCopyUITests: XCTestCase {

    func test_eraStep_showsPlainLanguageCopy() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset", "--seed-ski-primary"]
        app.launch()

        // Advance through the seeded steps to the era step. Every prior step's
        // required input is pre-filled by the seed, so Continue is enabled.
        for step in ["welcome", "sports", "sportSeasons", "availability",
                     "equipment", "experience", "about"] {
            let btn = app.buttons["onboarding-continue-\(step)"]
            XCTAssertTrue(btn.waitForExistence(timeout: 8), "stuck before step: \(step)")
            btn.tap()
        }

        // Era step: the plain descriptor leads; the program names are the dim
        // "Sound familiar?" line.
        XCTAssertTrue(app.staticTexts["Your training era."].waitForExistence(timeout: 5))
        let plain = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "push / pull / legs")).firstMatch
        XCTAssertTrue(plain.waitForExistence(timeout: 3),
                      "plain-language descriptor should lead the accept row")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "era-plain-copy"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
