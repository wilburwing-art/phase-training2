import XCTest

/// Onboarding discoverability (primary/support). For a ski-primary user, the
/// "When are you in season?" step surfaces the TRAIN TWO SPORTS? section so the
/// feature is discovered during onboarding, not buried in Profile.
///
/// Seeds ski-primary memory and launches INTO onboarding (no
/// --ui-test-onboarded), so the draft inits ski-primary and we only tap
/// welcome → sports → seasons.
final class SupportOnboardingUITests: XCTestCase {

    func test_skiPrimaryOnboarding_showsSupportSection() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset", "--seed-ski-primary"]
        app.launch()

        // Welcome → Sports.
        let welcomeNext = app.buttons["onboarding-continue-welcome"]
        XCTAssertTrue(welcomeNext.waitForExistence(timeout: 10), "onboarding should present")
        welcomeNext.tap()

        // Sports → Seasons (ski is pre-seeded as the primary sport).
        let sportsNext = app.buttons["onboarding-continue-sports"]
        XCTAssertTrue(sportsNext.waitForExistence(timeout: 5))
        sportsNext.tap()

        // The two-sport section appears for a ski primary.
        XCTAssertTrue(app.staticTexts["TRAIN TWO SPORTS?"].waitForExistence(timeout: 5),
                      "ski-primary users should see the support-sport section in onboarding")
        // And its controls are the shared editor.
        XCTAssertTrue(app.buttons["Climbing"].firstMatch.waitForExistence(timeout: 3))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "onboarding-support-section"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
