// OnboardingCoachConsentScreen.swift — final questionnaire step before plan preview.
//
// Apple Guideline 5.1.2(i) requires explicit per-feature consent before
// sending personal data to any third-party AI. This is the consent gate
// CoachConsent.swift always claimed onboarding owned — without it the coach
// bubble never appears for a new install.
//
// Default is OFF and NEITHER option is pre-selected: the user must make an
// affirmative pick before Continue enables. A pre-ticked "Enable AI Coach"
// accepted by a generic "See my plan" button is a pre-checked consent box —
// weak evidence of consent for App Review and not valid opt-in under GDPR,
// especially since the payload includes health-adjacent body metrics and
// injury notes. Continue writes the choice into the same @AppStorage key the
// Profile toggle reads/writes.

import SwiftUI

struct OnboardingCoachConsentScreen: View {
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false

    let onNext: () -> Void
    let onBack: () -> Void

    /// Local state so the user can flip back-and-forth without committing to
    /// AppStorage until they tap Continue. `nil` = no choice made yet, which
    /// gates Continue — consent must be an affirmative act, not a default.
    @State private var localOn: Bool?

    var body: some View {
        OnboardingScaffold(
            step: .coachConsent,
            title: "Want a coach in your pocket?",
            subtitle: "An AI Coach can answer training questions and tailor your plan. You can switch it off any time in Profile.",
            nextLabel: "See my plan",
            nextEnabled: localOn != nil,
            onNext: {
                consentGranted = localOn ?? false
                onNext()
            },
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingPickRow(
                    title: "Enable AI Coach",
                    subtitle: CoachConsent.shortDisclosure,
                    selected: localOn == true,
                    leading: "sparkles",
                    action: { localOn = true },
                    a11yId: "onboarding-consent-on"
                )
                OnboardingPickRow(
                    title: "No coach",
                    subtitle: "Nothing leaves your phone. You can turn this on later in Profile.",
                    selected: localOn == false,
                    leading: "lock.fill",
                    action: { localOn = false },
                    a11yId: "onboarding-consent-off"
                )
                Text(CoachConsent.modalBody)
                    .font(.caption)
                    .foregroundColor(.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .onAppear {
            // A stored choice mirrors as-is so backing into this step shows what
            // the user actually picked. A fresh install starts with NO selection
            // so neither option is pre-consented.
            localOn = hasMadeChoice ? consentGranted : nil
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
