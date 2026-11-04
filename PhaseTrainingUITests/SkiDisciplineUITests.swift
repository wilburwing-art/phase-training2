import XCTest

/// Onboarding asks a skier how they ski, and Profile shows and edits it.
final class SkiDisciplineUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_pickBackcountryInOnboarding_showsInProfile() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset"]
        app.launch()
        step(app, "onboarding-continue-welcome", timeout: 10)
        let ski = app.buttons["onboarding-sport-alpine-skiing"]
        XCTAssertTrue(ski.waitForExistence(timeout: 6))
        ski.tap()
        step(app, "onboarding-continue-sports")

        let backcountry = app.buttons["onboarding-discipline-backcountry"]
        var swipes = 0
        while !(backcountry.exists && backcountry.isHittable) && swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(backcountry.exists, "a ski primary is asked how they ski")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "onboarding-discipline"
        shot.lifetime = .keepAlways
        add(shot)
        backcountry.tap()

        step(app, "onboarding-continue-sportSeasons")
        step(app, "onboarding-health-off")
        step(app, "onboarding-continue-health")
        step(app, "onboarding-consent-off")
        step(app, "onboarding-continue-coachConsent", timeout: 15)

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Discipline")).firstMatch
        swipes = 0
        while !row.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.label.contains("Backcountry"), row.label)
        row.tap()
        let park = app.buttons["discipline-park"]
        XCTAssertTrue(park.waitForExistence(timeout: 5))
        park.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Park"), row.label)
    }

    private func step(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 8) {
        let b = app.buttons[id]
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "'\(id)' should appear")
        b.tap()
    }
}
