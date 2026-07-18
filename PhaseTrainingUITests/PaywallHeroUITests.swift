// PaywallHeroUITests.swift — the Repelican Lean+Swole paywall hero.
//
// The paywall hero swapped the sparkles icon for a Lean + Swole Repelican pair
// (the two-sport differentiator made visual). This drives Profile -> Subscription
// and confirms the paywall presents without crashing — the mascot is a SwiftUI
// Canvas rendered inside a sheet, the one place a paint bug would surface.

import XCTest

final class PaywallHeroUITests: XCTestCase {

    func test_paywall_presents_with_mascot_hero() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-onboarded", "--ui-test-reset", "--seed-ski-primary"]
        app.launch()

        let profile = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "Profile tab should exist")
        profile.tap()

        let subscription = app.staticTexts["Subscription"]
        XCTAssertTrue(subscription.waitForExistence(timeout: 8), "Subscription row should exist")
        subscription.tap()

        // The Pro paywall (Lean + Swole hero) presents without crashing.
        XCTAssertTrue(app.staticTexts["Phase Training Pro"].waitForExistence(timeout: 5),
                      "paywall should present with its mascot hero")
    }
}
