// CoachEntitlementTests.swift — pure gate logic. requirePro is passed
// explicitly so both sides of the monetization switch are exercised
// regardless of the shipped CoachEntitlement.proRequired value.
// `available: true` is passed explicitly for the same reason: CI builds
// with a blanked gateway token, so the coachAvailable default is false
// there and every unlock assertion would fail on the token, not the gate
// under test (exactly the failure mode unlocked's doc comment warns
// about — these four call sites had been failing on CI since 8/27).

import XCTest
@testable import PhaseTraining

final class CoachEntitlementTests: XCTestCase {

    // MARK: - Monetization ON (requirePro: true)

    func test_gated_consentAndPro_unlocks() {
        XCTAssertTrue(CoachEntitlement.unlocked(consent: true, pro: true, requirePro: true,
                                                available: true))
    }

    func test_gated_consentWithoutPro_locked() {
        XCTAssertFalse(CoachEntitlement.unlocked(consent: true, pro: false, requirePro: true,
                                                 available: true))
    }

    func test_proNeverOverridesConsent() {
        // Consent is the privacy gate — Pro (or the open gate) never
        // substitutes for it.
        XCTAssertFalse(CoachEntitlement.unlocked(consent: false, pro: true, requirePro: true,
                                                 available: true))
        XCTAssertFalse(CoachEntitlement.unlocked(consent: false, pro: false, requirePro: false,
                                                 available: true))
    }

    func test_unavailableBuild_neverUnlocks() {
        // The beta/no-token build hides the coach outright, whatever the
        // consent and Pro state say.
        XCTAssertFalse(CoachEntitlement.unlocked(consent: true, pro: true, requirePro: true,
                                                 available: false))
        XCTAssertFalse(CoachEntitlement.unlocked(consent: true, pro: false, requirePro: false,
                                                 available: false))
    }

    // MARK: - Monetization OFF (requirePro: false — the shipped state)

    func test_open_consentAlone_unlocks() {
        XCTAssertTrue(CoachEntitlement.unlocked(consent: true, pro: false, requirePro: false,
                                                available: true))
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
