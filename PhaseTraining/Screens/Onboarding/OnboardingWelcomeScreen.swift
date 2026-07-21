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
                RepelicanView(build: .athletic)
                    .frame(width: 132, height: 150)
                    .repelicanIdle()
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
                Text("Eight quick questions. Then a plan that fits your sport, your equipment, and your week.")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
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
