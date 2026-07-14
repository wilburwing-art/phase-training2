// SupportEntitlement.swift — the Pro gate for the primary/support model
// (PLAN-primary-support.md phase 3). Mirrors CoachEntitlement's held-open
// pattern so the gate is fully WIRED but ships free until products exist.
//
// PRODUCT DECISION (2026-07-14): the PLAN's monetization strategy is that
// support-sport de-confliction IS the Pro feature — potentially the FIRST paid
// feature, ahead of the (currently free) coach. So this carries its OWN switch
// (`proRequired`) rather than reusing CoachEntitlement's, letting support flip
// to paid while the coach stays free. Both read the same entitlement mirror
// (`CoachEntitlement.proKey`, which SubscriptionStore updates on every refresh)
// — one Pro tier, independently gated features.
//
// Held OPEN today (`proRequired = false`): the editor + reflow ship free, so
// the feature is TestFlight-able before App Store Connect products are created.

import Foundation

enum SupportEntitlement {
    /// The monetization switch for the support feature. False = ships free
    /// (only gate is "declare a pattern"). True = the Support Sport editor
    /// routes non-subscribers to PaywallView.
    ///
    /// Flip-day checklist (when this goes true):
    ///   1. Create the products in App Store Connect — SubscriptionStore's
    ///      product IDs are placeholders until then (shared with the coach).
    ///   2. The row summary shows "Pro" and tapping opens the paywall for
    ///      non-subscribers (handled here + in ProfileScreen).
    ///   3. REVOCATION DECISION: a lapsed user who already saved a
    ///      supportPattern still gets the reflow, because Planner.apply-
    ///      SupportPattern reads memory only (kept pure — no UserDefaults read,
    ///      so PlannerSupportPatternTests stay deterministic). To revoke the
    ///      benefit on lapse, nil the pattern at the plan-generation boundary
    ///      (PlanStore) guarded by `proSatisfied()`, NOT inside the pure
    ///      Planner. Until flip day this is moot (proSatisfied is always true).
    static let proRequired = false

    /// Pure gate — parameterized so tests exercise both sides of the switch.
    static func unlocked(pro: Bool, requirePro: Bool = proRequired) -> Bool {
        pro || !requirePro
    }

    /// The Pro half for non-view call sites — reads the same mirror the coach
    /// does (`.standard[CoachEntitlement.proKey]`).
    static func proSatisfied(defaults: UserDefaults = .standard) -> Bool {
        !proRequired || defaults.bool(forKey: CoachEntitlement.proKey)
    }
}
