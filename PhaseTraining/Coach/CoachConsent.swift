// CoachConsent.swift — Apple Guideline 5.1.2(i) consent gate.
//
// Apple (Nov 2025) requires explicit disclosure + per-feature consent before
// sending personal data to any third-party AI. Our flow:
//   1. AI Coach off by default for existing installs; on by default for new
//      installs (set in onboarding).
//   2. Toggling on presents the consent modal with provider name, what's
//      sent, and a link to the privacy policy.
//   3. Only after the modal's Accept does any network request leave the device.
//
// Stored in @AppStorage so SettingsRow + CoachClient gating share state.

import Foundation
import SwiftUI

enum CoachConsent {
    static let storageKey = "pt_coach_consent"

    /// Marketing copy shown in the modal. Edit here, not in the row.
    static let providerName = "Anthropic (Claude)"
    static let routedVia    = "our Cloudflare AI Gateway"

    static let modalBody = """
    The AI Coach sends your training context to \(providerName) via \(routedVia) so it can answer questions and adjust your plan. That includes:

    • Your plan, workout history and logged sets
    • Body metrics you've entered — height, weight, age, gender
    • Injuries and soreness you've logged, including your own notes
    • Estimated strength numbers, and your messages to the coach

    We don't send your name, email or device identifiers, and we don't sell or share this data. You can turn the coach off anytime in Profile, which stops all transmissions.
    """

    /// One-line version for the onboarding row, which has no room for the full
    /// list. Must stay consistent with `modalBody` — the onboarding screen is
    /// the ONLY consent surface a new install sees, so it can't be vaguer than
    /// the modal a returning user gets.
    static let shortDisclosure =
        "Sends your plan, workouts, body metrics (height, weight, age, gender) and injury notes to \(providerName) via \(routedVia). Never your name or email."
}

/// View modifier that drives a confirmation alert before flipping the toggle
/// to on. If the user cancels, the toggle reverts.
struct CoachConsentModal: ViewModifier {
    @Binding var presented: Bool
    @Binding var consentGranted: Bool

    func body(content: Content) -> some View {
        content
            .alert("Enable AI Coach?", isPresented: $presented) {
                Button("Cancel", role: .cancel) {
                    // Revert the toggle if the user backs out.
                    consentGranted = false
                }
                Button("Enable") {
                    consentGranted = true
                }
            } message: {
                Text(CoachConsent.modalBody)
            }
    }
}
