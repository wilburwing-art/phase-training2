// CoachEntitlement.swift — single source of truth for "is the AI coach
// usable right now". The coach requires the privacy consent (CoachConsent)
// and, when monetization turns on, a live Pro subscription. SubscriptionStore
// mirrors `isPro` into UserDefaults under `proKey` on every entitlement
// refresh so non-SwiftUI call sites (InsightGenerator, the LLM refinement
// pass) can read it without an environment object; views observe the same
// key via @AppStorage for reactivity.
//
// PRODUCT DECISION (2026-06-05): coach ships FREE. The Pro gate is wired at
// every coach surface but held open by `proRequired = false`. To start
// charging: flip it to true and create the products in App Store Connect
// (see SubscriptionStore.swift) — no other code changes needed.

import Foundation

enum CoachEntitlement {
    /// UserDefaults key SubscriptionStore mirrors `isPro` into on every
    /// entitlement refresh.
    static let proKey = "pt_pro_entitled"

    /// The monetization switch. False = coach ships free (consent is the
    /// only gate). True = coach surfaces additionally require Pro and the
    /// consent toggle routes non-subscribers to PaywallView.
    ///
    /// Flip-day checklist (when this goes true):
    ///   1. Create the products in App Store Connect — SubscriptionStore's
    ///      product IDs are placeholders until then.
    ///   2. CoachBubble disappears silently for lapsed users; only
    ///      CoachSettingsRow shows the lapsed notice. Decide if that's enough.
    ///   3. InsightGenerator's foreground path awaits refresh() before
    ///      runIfDue (1e9d8ad), so the proKey mirror race is handled.
    static let proRequired = false

    /// Pure gate logic — parameterized so tests can exercise both sides of
    /// the switch regardless of the shipped value.
    static func unlocked(consent: Bool, pro: Bool, requirePro: Bool = proRequired) -> Bool {
        consent && (pro || !requirePro)
    }

    /// The Pro half alone (consent handled by the caller's own flag —
    /// reactive @AppStorage in views, an explicit defaults read in
    /// InsightGenerator / the LLM refinement pass). Reads `.standard`,
    /// where SubscriptionStore mirrors.
    static func proSatisfied(defaults: UserDefaults = .standard) -> Bool {
        !proRequired || defaults.bool(forKey: proKey)
    }
}
