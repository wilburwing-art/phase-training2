// CoachEntitlementTests.swift — pure gate logic. requirePro is passed
// explicitly so both sides of the monetization switch are exercised
// regardless of the shipped CoachEntitlement.proRequired value.

import XCTest
@testable import PhaseTraining

final class CoachEntitlementTests: XCTestCase {

    // MARK: - Monetization ON (requirePro: true)

    func test_gated_consentAndPro_unlocks() {
        XCTAssertTrue(CoachEntitlement.unlocked(consent: true, pro: true, requirePro: true))
    }

    func test_gated_consentWithoutPro_locked() {
        XCTAssertFalse(CoachEntitlement.unlocked(consent: true, pro: false, requirePro: true))
    }

    func test_proNeverOverridesConsent() {
        // Consent is the privacy gate — Pro (or the open gate) never
        // substitutes for it.
        XCTAssertFalse(CoachEntitlement.unlocked(consent: false, pro: true, requirePro: true))
        XCTAssertFalse(CoachEntitlement.unlocked(consent: false, pro: false, requirePro: false))
    }

    // MARK: - Monetization OFF (requirePro: false — the shipped state)

    func test_open_consentAlone_unlocks() {
        XCTAssertTrue(CoachEntitlement.unlocked(consent: true, pro: false, requirePro: false))
    }

    func test_shippedState_isFree() {
        // Locks in the 2026-06-05 product decision; flipping proRequired
        // intentionally breaks this test so the change is deliberate.
        XCTAssertFalse(CoachEntitlement.proRequired)
    }

    func test_proSatisfied_readsMirroredKey() {
        let defaults = UserDefaults(suiteName: "CoachEntitlementTests")!
        defaults.removePersistentDomain(forName: "CoachEntitlementTests")
        defer { defaults.removePersistentDomain(forName: "CoachEntitlementTests") }

        // With the gate open, proSatisfied is true even without the key.
        XCTAssertTrue(CoachEntitlement.proSatisfied(defaults: defaults))
        defaults.set(true, forKey: CoachEntitlement.proKey)
        XCTAssertTrue(CoachEntitlement.proSatisfied(defaults: defaults))
    }
}
