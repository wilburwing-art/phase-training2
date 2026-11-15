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
        // Health is gated the same way; Not now keeps Apple's sheet out of CI.
        step(app, "onboarding-health-off")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "onboarding-health"
        shot.lifetime = .keepAlways
        add(shot)
        step(app, "onboarding-continue-health")
        // The consent step exists only in a build that carries a coach token.
        // CI and beta builds have none, and there Health's Continue finishes.
        if app.buttons["onboarding-consent-off"].waitForExistence(timeout: 4) {
            app.buttons["onboarding-consent-off"].tap()
            step(app, "onboarding-continue-coachConsent", timeout: 15)
        }

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
        let assumedMarker = app.staticTexts["ASSUMED"]
        XCTAssertTrue(assumedMarker.waitForExistence(timeout: 5)
                        || app.otherElements["plan-assumptions-row"].exists
                        || app.buttons["plan-assumptions-row"].exists,
                      "assumed defaults should be surfaced on the Week tab"
                        + " staticTexts: \(app.staticTexts.allElementsBoundByIndex.prefix(30).map { "\($0.identifier)|\($0.label)" }.joined(separator: ", "))")
        // Header stack: title and summary share a row and the actions sit on
        // one row, so the first day row starts in the upper half of the screen.
        let firstRow = app.descendants(matching: .any)["week-day-row-0"]
        let planNext = app.buttons["week-plan-next"]
        let tone = app.buttons["week-tone-chip"]
        XCTAssertTrue(planNext.isHittable && tone.isHittable, "header actions should be tappable")
        XCTAssertEqual(planNext.frame.midY, tone.frame.midY, accuracy: 2,
                       "Plan next week and the tone chip share one row")
        let screenH = app.windows.firstMatch.frame.height
        XCTAssertLessThan(firstRow.frame.minY, screenH * 0.42,
                          "first day row y=\(firstRow.frame.minY) of \(screenH)")
        let rowHeights = (0..<7).map { app.descendants(matching: .any)["week-day-row-\($0)"].frame.height }
        add(XCTAttachment(string: "firstRowY=\(firstRow.frame.minY) screenH=\(screenH) rowHeights=\(rowHeights)"))
        XCTAssertGreaterThanOrEqual(rowHeights.min() ?? 0, 48)

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
