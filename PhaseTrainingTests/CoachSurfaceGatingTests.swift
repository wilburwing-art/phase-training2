// CoachSurfaceGatingTests.swift — surface-level gating for the coach UI.
// CoachEntitlementTests covers the pure unlock logic; these pin the
// conditions the views actually evaluate: CoachBubble's hidden matrix
// (consent x pro x tab x session) and CoachSettingsRow's lapsed notice.
// requirePro is passed explicitly so both sides of the monetization switch
// are exercised regardless of the shipped CoachEntitlement.proRequired value.

import XCTest
@testable import PhaseTraining

final class CoachSurfaceGatingTests: XCTestCase {

    // MARK: - CoachBubble.shouldShow — consent x pro matrix

    func test_bubble_open_consentAlone_shows() {
        XCTAssertTrue(CoachBubble.shouldShow(
            consent: true, pro: false, onProfileTab: false, sessionActive: false,
            requirePro: false))
    }

    func test_bubble_noConsent_hidden_evenWithPro() {
        XCTAssertFalse(CoachBubble.shouldShow(
            consent: false, pro: true, onProfileTab: false, sessionActive: false,
            requirePro: true))
        XCTAssertFalse(CoachBubble.shouldShow(
            consent: false, pro: false, onProfileTab: false, sessionActive: false,
            requirePro: false))
    }

    func test_bubble_gated_consentAndPro_shows() {
        XCTAssertTrue(CoachBubble.shouldShow(
            consent: true, pro: true, onProfileTab: false, sessionActive: false,
            requirePro: true))
    }

    func test_bubble_lapsed_consentWithoutPro_hidden() {
        // Consent on but the subscription lapsed while the gate is closed —
        // the bubble goes dark, it doesn't fall back to free.
        XCTAssertFalse(CoachBubble.shouldShow(
            consent: true, pro: false, onProfileTab: false, sessionActive: false,
            requirePro: true))
    }

    // MARK: - CoachBubble.shouldShow — surface conditions

    func test_bubble_profileTab_hidden_evenWhenUnlocked() {
        XCTAssertFalse(CoachBubble.shouldShow(
            consent: true, pro: true, onProfileTab: true, sessionActive: false,
            requirePro: false))
    }

    func test_bubble_activeSession_hidden_evenWhenUnlocked() {
        XCTAssertFalse(CoachBubble.shouldShow(
            consent: true, pro: true, onProfileTab: false, sessionActive: true,
            requirePro: false))
    }

    // MARK: - CoachSettingsRow lapsed notice

    func test_lapsedNotice_consentOnGateClosedWithoutPro_shows() {
        // The single state the notice exists for.
        XCTAssertTrue(CoachSettingsRow.showsLapsedNotice(consent: true, pro: false, requirePro: true))
    }

    func test_lapsedNotice_proSubscriber_noNotice() {
        XCTAssertFalse(CoachSettingsRow.showsLapsedNotice(consent: true, pro: true, requirePro: true))
    }

    func test_lapsedNotice_noConsent_noNotice() {
        // Toggle off → nothing to lapse, regardless of the gate.
        XCTAssertFalse(CoachSettingsRow.showsLapsedNotice(consent: false, pro: false, requirePro: true))
        XCTAssertFalse(CoachSettingsRow.showsLapsedNotice(consent: false, pro: true, requirePro: true))
    }

    func test_lapsedNotice_openGate_neverShows() {
        // Shipped state: coach is free, so a lapsed subscription is moot.
        XCTAssertFalse(CoachSettingsRow.showsLapsedNotice(consent: true, pro: false, requirePro: false))
        XCTAssertFalse(CoachSettingsRow.showsLapsedNotice(consent: true, pro: true, requirePro: false))
    }
}
