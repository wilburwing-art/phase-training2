// OnboardingWelcomeScreen.swift — step 1 of the onboarding flow.
// Sets the tone: dark + lime, not a sales pitch. Single CTA into the flow.

import SwiftUI

struct OnboardingWelcomeScreen: View {
    let onStart: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                KettleView(pose: .flex)
                    .frame(width: 120, height: 150)
                    .accessibilityHidden(true)
                Text("PHASE TRAINING")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
                Text("Your week,\nplanned around\nwhat you do.")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 38))
                    .tracking(-0.025 * 38)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                // "Eight" was wrong: OnboardingStep.total is 10 and the chrome
                // renders "STEP X OF 10". Welcome is one of those and is not a
                // question, so nine is the number a user can count.
                Text("Nine quick questions. Then a plan that fits your sport, your equipment, and your week.")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                // The app prescribes barbell loads, hangboard protocols and
                // campus board work to people who declare disc herniations and
                // stress fractures, and carried no disclaimer anywhere.
                Text("Phase Training is a training planner, not medical advice. Talk to a clinician before starting, especially if you're carrying an injury.")
                    .styled(.body)
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingPrimaryButton(label: "Get started", action: onStart,
                                    a11yId: "onboarding-continue-welcome")
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
    }
}

#Preview { OnboardingWelcomeScreen(onStart: {}) }
