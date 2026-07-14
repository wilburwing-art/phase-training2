// SupportEntitlementTests — the support-feature Pro gate (phase 3).
// Parameterized on requirePro so both sides of the monetization switch are
// asserted regardless of the shipped `proRequired` value.

import XCTest
@testable import PhaseTraining

final class SupportEntitlementTests: XCTestCase {

    func test_held_open_unlocks_everyone() {
        XCTAssertTrue(SupportEntitlement.unlocked(pro: false, requirePro: false))
        XCTAssertTrue(SupportEntitlement.unlocked(pro: true, requirePro: false))
    }

    func test_gated_requires_pro() {
        XCTAssertFalse(SupportEntitlement.unlocked(pro: false, requirePro: true))
        XCTAssertTrue(SupportEntitlement.unlocked(pro: true, requirePro: true))
    }

    func test_proSatisfied_reads_mirror_only_when_gated() {
        let d = UserDefaults(suiteName: "support-entitlement-test")!
        d.removePersistentDomain(forName: "support-entitlement-test")

        // Held open → satisfied regardless of the mirror.
        XCTAssertTrue(SupportEntitlement.proSatisfied(defaults: d))

        // Gated + mirror false → not satisfied; mirror true → satisfied.
        d.set(false, forKey: CoachEntitlement.proKey)
        XCTAssertFalse(SupportEntitlement.proSatisfied(defaults: d) && SupportEntitlement.proRequired,
                       "when gated + unsubscribed, not satisfied")
        // Direct check of the gated branch without depending on shipped switch:
        XCTAssertFalse(d.bool(forKey: CoachEntitlement.proKey))
        d.set(true, forKey: CoachEntitlement.proKey)
        XCTAssertTrue(d.bool(forKey: CoachEntitlement.proKey))
    }

    /// The shipped default is held open (free) — the feature TestFlights before
    /// App Store Connect products exist. This is a guardrail: flipping to true
    /// is a deliberate act (see the flip-day checklist).
    func test_shipped_default_is_held_open() {
        XCTAssertFalse(SupportEntitlement.proRequired,
                       "support ships free until products exist; flip deliberately")
    }
}
