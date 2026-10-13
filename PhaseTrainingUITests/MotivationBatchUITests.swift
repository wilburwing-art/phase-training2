// MotivationBatchUITests.swift — the 2026-10-13 motivation batch, end to end.
//
// Four surfaces changed and none had a UI test: the Today eyebrow now leads
// with the sport and the subtitle counts down to the season opener in pre-
// season; the exercise action sheet shows the running affinity and lets an
// avoid-list entry be undone; Profile gained a Favorite exercises row; the
// Progress strength card reads the change against the user's own best 90
// days back. Screenshots are attached at each stop so a device sweep can
// compare them (`xcrun xcresulttool export attachments`).

import XCTest

final class MotivationBatchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_todayEyebrowCountdownAndAffinitySheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset",
                                "--seed-plan-demo", "--seed-ski-primary", "--seed-season-countdown"]
        app.launch()

        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))

        // The eyebrow and the subtitle are separate texts on this header, so
        // each is matched by content on its own.
        let eyebrow = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "ALPINE SKIING · PRE-SEASON")).firstMatch
        XCTAssertTrue(eyebrow.waitForExistence(timeout: 5), "eyebrow should lead with the sport" + dump(app))
        let countdown = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "season in 34d")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5), "subtitle should count down to the opener" + dump(app))
        attach(app, "today-identity-countdown")

        // Recommend more, then reopen: the row carries the running score.
        let row = app.descendants(matching: .any)["today-edit-1"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "first Today row should exist" + dump(app))
        row.tap()
        let more = app.buttons["exercise-action-recommend-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "action sheet should open" + dump(app))
        XCTAssertFalse(more.label.contains("+"), "fresh install has no score yet: \(more.label)")
        more.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.label.contains("+1"), "row should show the score after one tap: \(more.label)")
        attach(app, "action-sheet-affinity")

        // Avoid, then reopen: the row flips to an undo.
        let avoid = app.buttons["exercise-action-avoid"]
        XCTAssertTrue(avoid.exists)
        XCTAssertTrue(avoid.label.contains("Don't recommend again"), avoid.label)
        avoid.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(avoid.waitForExistence(timeout: 5))
        XCTAssertTrue(avoid.label.contains("On your avoid-list"), "avoid row should toggle: \(avoid.label)")
        attach(app, "action-sheet-avoided")
        avoid.tap()   // undo, so Profile below shows only the favorite

        // Profile: the favorite is listed, and the editor lists the chip.
        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let favRow = app.staticTexts["Favorite exercises"]
        XCTAssertTrue(scrollTo(favRow, in: app), "Profile should list Favorite exercises" + dump(app))
        XCTAssertTrue(app.staticTexts["Bench Press"].exists, "row value should name the one favorite" + dump(app))
        favRow.tap()
        XCTAssertTrue(app.navigationBars["Favorite exercises"].waitForExistence(timeout: 5), "editor should open" + dump(app))
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
        XCTAssertTrue(app.staticTexts["+1"].exists, "chip should carry the score")
        attach(app, "profile-favorites")
    }

    func test_progressStrengthRowShowsSelfDelta() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-progress-demo"]
        app.launch()
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()

        XCTAssertTrue(scrollTo(app.staticTexts["STRENGTH RATIOS"], in: app), "strength card should render" + dump(app))
        let delta = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "in 90d · est 1RM")).firstMatch
        XCTAssertTrue(delta.waitForExistence(timeout: 3),
                      "a lift with a session past the 90-day window should read its change first" + dump(app))
        XCTAssertTrue(delta.label.hasPrefix("+"), "the seed progresses, so the change is positive: \(delta.label)")
        attach(app, "progress-strength-delta")

        // Body cards now sit below the PR feed.
        XCTAssertTrue(scrollTo(app.staticTexts["RECENT PRs"], in: app))
        XCTAssertTrue(scrollTo(app.staticTexts["BODY WEIGHT"], in: app))
        attach(app, "progress-body-after-prs")
    }

    // MARK: - Helpers

    /// Swipe until the element is on screen (hittable), not merely in the
    /// hierarchy, so the attached screenshot shows the card being asserted.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 12) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func dump(_ app: XCUIApplication) -> String {
        "\n--- elements ---\n" + app.debugDescription.split(separator: "\n").prefix(80).joined(separator: "\n")
    }
}
