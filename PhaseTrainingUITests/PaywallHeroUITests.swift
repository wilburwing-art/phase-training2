// PaywallHeroUITests.swift — the two-Kettle paywall hero.
//
// The hero is a Kettle pair running two loops, bike beside flex (the two-sport
// differentiator made visual). This drives Profile -> Subscription and confirms
// the paywall presents without crashing — the mascot is a SwiftUI Canvas
// rendered inside a sheet, the one place a paint bug would surface, and both
// loops are live TimelineViews there.

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

        // The Pro paywall (two-Kettle hero) presents without crashing.
        XCTAssertTrue(app.staticTexts["Phase Training Pro"].waitForExistence(timeout: 5),
                      "paywall should present with its mascot hero")

        // Guideline 3.1.2: the terms a buyer must see before purchase. The
        // scheme's StoreKit configuration supplies the two products, so the
        // price-per-period line renders on each button.
        let monthly = app.buttons["paywall-buy-com.phasetraining.app.pro_monthly"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 8), "monthly product should load from the StoreKit config")
        XCTAssertTrue(monthly.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '/ month'")).firstMatch.exists,
                      "monthly button should state its price per period")
        for id in ["paywall-terms", "paywall-privacy", "paywall-manage", "paywall-restore"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, "\(id) should be on the paywall")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "paywall-terms"; shot.lifetime = .keepAlways
        add(shot)
    }
}
