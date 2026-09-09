// OnboardingLandingUITests.swift — the gate lands you on a real, inspectable week.
//
// Replaces OnboardingPlanDetailUITests, which drove the flow to a plan-preview
// step and opened a read-only day sheet. That step is gone: the user is no
// longer asked to "Accept" a plan they can't judge, and the preview isn't a
// separate render of a separate generation any more.
//
// The coverage it was really buying — finish onboarding, get a week with actual
// sessions in it, be able to click into one — still matters, so it moved here
// and now asserts against the LIVE plan on the Week tab. Plus the new half: the
// defaults the short gate left behind are visible and tappable rather than
// silent.

import XCTest

final class OnboardingLandingUITests: XCTestCase {

    func test_finishingGate_landsOnWeekWithAssumptionsSurfaced() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-reset"]   // cold onboarding
        app.launch()

        step(app, "onboarding-continue-welcome", timeout: 10)
        let sport = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'onboarding-sport-'")).firstMatch
        XCTAssertTrue(sport.waitForExistence(timeout: 6), "a sport chip should appear")
        sport.tap()
        step(app, "onboarding-continue-sports")
        step(app, "onboarding-continue-sportSeasons")
        // Consent is gated (T0-5): pick an option or Continue never enables.
        step(app, "onboarding-consent-off")
        // Last step of the gate — its Continue commits and dismisses.
        step(app, "onboarding-continue-coachConsent", timeout: 15)

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15),
                      "finishing the gate should drop straight into the main tabs")

        app.tabBars.buttons["Week"].tap()
        XCTAssertTrue(app.otherElements["week-day-row-0"].waitForExistence(timeout: 10)
                        || app.buttons["week-day-row-0"].waitForExistence(timeout: 1),
                      "the Week tab should render a generated week")

        // Assert on the row's marker text rather than the identifier query:
        // the identifier sits on a plain VStack, which on iOS 26 does not
        // resolve through app.otherElements (same query-mismatch class as
        // the body-weight sheet). The marker text is the visible thing the
        // assertion is really about.
        let assumedMarker = app.staticTexts["ASSUMED — TAP TO CHANGE"]
        XCTAssertTrue(assumedMarker.waitForExistence(timeout: 5)
                        || app.otherElements["plan-assumptions-row"].exists
                        || app.buttons["plan-assumptions-row"].exists,
                      "assumed defaults should be surfaced on the Week tab"
                        + " staticTexts: \(app.staticTexts.allElementsBoundByIndex.prefix(30).map { "\($0.identifier)|\($0.label)" }.joined(separator: ", "))")
        let chip = app.buttons["assumption-chip-equipment"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3), "equipment should read as assumed")
        chip.tap()

        // Tapping an assumption opens the REAL Profile editor for that field —
        // that's the whole point: correcting a guess teaches where it lives.
        XCTAssertTrue(app.staticTexts["EQUIPMENT"].waitForExistence(timeout: 5),
                      "the equipment chip should open the equipment editor")
    }

    private func step(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 8,
                      file: StaticString = #file, line: UInt = #line) {
        let b = app.buttons[id]
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "'\(id)' should appear", file: file, line: line)
        b.tap()
    }
}
