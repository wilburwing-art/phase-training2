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
    ///   4. Offline first launch never populates proKey: refreshEntitlement()
    ///      needs Transaction.currentEntitlements, which a fresh install can't
    ///      reach without network. A returning subscriber opening offline reads
    ///      proKey=false until the next successful refresh. Consider caching a
    ///      last-known-good entitlement with a grace window before flipping.
    ///   5. A .storekit config (PhaseTraining.storekit) is wired into the run
    ///      scheme for previews/tests, but the REAL product IDs still have to
    ///      be created in App Store Connect (item 1) — the config file is not a
    ///      substitute.
    static let proRequired = false

    /// Is the coach present in THIS build at all?
    ///
    /// Beta builds ship with no gateway token (PHASETRAINING_BETA=1 blanks it
    /// in generate-coach-secrets.sh, so the literal never reaches the binary).
    /// Without this check every coach surface would still render and then fail
    /// at send time with "coach isn't available in this build" — an error the
    /// tester can neither fix nor act on. Better to not offer it.
    ///
    /// Derived from the token rather than a separate flag, so the UI can never
    /// disagree with what the binary can actually do.
    static var coachAvailable: Bool { !CoachSecrets.gatewayToken.isEmpty }

    /// Pure gate logic — parameterized so tests can exercise both sides of
    /// the switch regardless of the shipped value.
    ///
    /// `available` defaults to the build's real capability; tests pass it
    /// explicitly so a token-less test host doesn't silently turn every
    /// entitlement assertion into `false`.
    static func unlocked(consent: Bool, pro: Bool,
                         requirePro: Bool = proRequired,
                         available: Bool = coachAvailable) -> Bool {
        available && consent && (pro || !requirePro)
    }

    /// The Pro half alone (consent handled by the caller's own flag —
    /// reactive @AppStorage in views, an explicit defaults read in
    /// InsightGenerator / the LLM refinement pass). Reads `.standard`,
    /// where SubscriptionStore mirrors.
    static func proSatisfied(defaults: UserDefaults = .standard) -> Bool {
        !proRequired || defaults.bool(forKey: proKey)
    }
}
