// ProgressScreenUITests.swift — the Progress tab's card stack, end to end.
//
// No UI test reached this tab except SorenessReachabilityUITests, which
// asserts one pill. Every other card could stop rendering and nothing would
// fail: the unit suites cover the math behind the cards, not whether the
// cards are on screen.
//
// Two shapes matter and are separate view trees, so passing in one says
// nothing about the other:
//   - populated (--seed-progress-demo): the full stack
//   - body-data-only (--seed-body-only-demo): Progress gates PER CARD, so a
//     user who has logged weight but no workout must still see their data.
//     The whole screen used to collapse to "Nothing yet." here.
//
// Card titles are asserted as literal strings. `.styled(.micro)` applies no
// text-case transform, so what the source writes is what XCUITest reads, and
// these assertions double as a copy guard.

import XCTest

final class ProgressScreenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Populated

    func test_progressTab_rendersCardStack() throws {
        let app = launch(seed: "--seed-progress-demo")
        openProgress(in: app)

        // Above the fold.
        XCTAssertTrue(app.staticTexts["THIS WEEK"].waitForExistence(timeout: 5),
                      "stat strip should render" + elementDump(app))
        XCTAssertTrue(app.staticTexts["TOTAL"].exists)

        // Each card, scrolling as we go. Order matches ProgressScreen.content.
        for title in [
            "BODY WEIGHT",
            "BODY COMPOSITION",
            "SESSIONS / WEEK",
            "VOLUME / WEEK",
            "STRENGTH RATIOS",
            "MUSCLE BALANCE · 4w",
            "RECOVERY",
            "TOP EXERCISES",
            "RECENT PRs",
            "RECENT FEEDBACK",
            "RECENT SESSIONS",
        ] {
            XCTAssertTrue(scrollTo(app.staticTexts[title], in: app),
                          "\(title) card should render on a populated Progress tab")
        }
    }

    func test_progressTab_volumeCardShowsVolumeNotSetsWhenWeightsLogged() throws {
        // The card swaps its title AND its series when no weights exist. The
        // seed logs weights, so it must be the volume form.
        let app = launch(seed: "--seed-progress-demo")
        openProgress(in: app)

        XCTAssertTrue(scrollTo(app.staticTexts["VOLUME / WEEK"], in: app))
        XCTAssertFalse(app.staticTexts["SETS / WEEK"].exists,
                       "Weighted sets were logged, so the fallback series must not be used")
    }

    func test_seeAllSessions_opensHistory() throws {
        let app = launch(seed: "--seed-progress-demo")
        openProgress(in: app)

        let seeAll = app.buttons["progress-see-all-sessions"]
        XCTAssertTrue(scrollTo(seeAll, in: app),
                      "See all sessions should be reachable" + elementDump(app))
        seeAll.tap()

        // Assert on the sheet's own content rather than the button vanishing.
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5),
                      "See all sessions should present HistoryScreen" + elementDump(app))
    }

    func test_bodyWeightCard_opensItsLogSheet() throws {
        let app = launch(seed: "--seed-progress-demo")
        openProgress(in: app)

        let card = app.buttons["progress-body-weight-card"]
        XCTAssertTrue(scrollTo(card, in: app), "body weight card should be reachable")
        card.tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5),
                      "tapping the body weight card should present its log sheet")
    }

    // MARK: - Body data, no sessions

    func test_bodyCardsRenderBeforeFirstSession() throws {
        // The per-card gate. This user has logged weight and composition but
        // never finished a workout; the tab must show that data rather than
        // "Nothing yet."
        let app = launch(seed: "--seed-body-only-demo")
        openProgress(in: app)

        XCTAssertTrue(scrollTo(app.staticTexts["BODY WEIGHT"], in: app),
                      "body weight card should render before the first session"
                        + elementDump(app))
        XCTAssertTrue(scrollTo(app.staticTexts["BODY COMPOSITION"], in: app))
        XCTAssertFalse(app.staticTexts["Nothing yet."].exists,
                       "The tab must not collapse to the empty state when body data exists")
    }

    // MARK: - Empty

    func test_emptyState_shownForFreshInstall() throws {
        let app = launch(seed: nil)
        openProgress(in: app)

        XCTAssertTrue(app.staticTexts["Nothing yet."].waitForExistence(timeout: 5),
                      "A fresh install should see the Progress empty state" + elementDump(app))
        // The check-in is offered in the empty branch too — a new user is
        // exactly who might record soreness first.
        XCTAssertTrue(app.buttons["progress-soreness-checkin"].exists)
    }

    // MARK: - Helpers

    private func launch(seed: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset"]
        if let seed { app.launchArguments.append(seed) }
        app.launch()
        return app
    }

    private func openProgress(in app: XCUIApplication) {
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "Progress tab should exist")
        progress.tap()
    }

    /// Swipe up until `element` exists. The card stack is many screens tall,
    /// so every assertion below the stat strip needs this.
    @discardableResult
    private func scrollTo(_ element: XCUIElement,
                          in app: XCUIApplication,
                          maxSwipes: Int = 12) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    /// Per the repo's XCUITest recipe: put the element dump in the failure
    /// message so a missing-vs-renamed element is diagnosed in one run.
    private func elementDump(_ app: XCUIApplication) -> String {
        let texts = app.staticTexts.allElementsBoundByIndex
            .prefix(40)
            .map { "\($0.identifier)|\($0.label)" }
            .joined(separator: ", ")
        return "; visible text: " + texts
    }
}
