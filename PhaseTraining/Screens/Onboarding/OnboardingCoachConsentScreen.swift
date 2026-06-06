// OnboardingCoachConsentScreen.swift — final questionnaire step before plan preview.
//
// Apple Guideline 5.1.2(i) requires explicit per-feature consent before
// sending personal data to any third-party AI. This is the consent gate
// CoachConsent.swift always claimed onboarding owned — without it the coach
// bubble never appears for a new install.
//
// Default is ON: the user picks Coach or No coach, and Continue writes the
// choice into the same @AppStorage key the Profile toggle reads/writes.

import SwiftUI

struct OnboardingCoachConsentScreen: View {
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false

    let onNext: () -> Void
    let onBack: () -> Void

    /// Local state so the user can flip back-and-forth without committing to
    /// AppStorage until they tap Continue.
    @State private var localOn: Bool = true

    var body: some View {
        OnboardingScaffold(
            step: .coachConsent,
            title: "Want a coach in your pocket?",
            subtitle: "An AI Coach can answer training questions and tailor your plan. You can switch it off any time in Profile.",
            nextLabel: "See my plan",
            onNext: {
                consentGranted = localOn
                onNext()
            },
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingPickRow(
                    title: "Enable AI Coach",
                    subtitle: "Chat reaches \(CoachConsent.providerName) via \(CoachConsent.routedVia). No identity info is sent.",
                    selected: localOn,
                    leading: "sparkles",
                    action: { localOn = true }
                )
                OnboardingPickRow(
                    title: "No coach",
                    subtitle: "Nothing leaves your phone. You can turn this on later in Profile.",
                    selected: !localOn,
                    leading: "lock.fill",
                    action: { localOn = false }
                )
            }
        }
        .onAppear {
            // A stored choice mirrors as-is so backing into this step shows
            // what the user actually picked; only a fresh install (no stored
            // choice) defaults ON.
            localOn = hasMadeChoice ? consentGranted : true
        }
    }

    /// True once a value has been written to AppStorage at least once. We use
    /// this so the very-first arrival defaults to ON (CoachConsent.swift's
    /// stated intent), while a returning user who chose "No coach" sees that
    /// preserved when they back into the step.
    private var hasMadeChoice: Bool {
        UserDefaults.standard.object(forKey: CoachConsent.storageKey) != nil
    }
}

#Preview {
    OnboardingCoachConsentScreen(onNext: {}, onBack: {})
        .preferredColorScheme(.dark)
}
