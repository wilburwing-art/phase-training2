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
                // This count is USER-FACING and has been wrong twice ("Eight"
                // when it was nine, "Nine" when the gate was cut to four steps).
                // It is `OnboardingStep.total` minus welcome, which is not a
                // question — three today. Recount it whenever a step is added
                // or removed; a promise of "three questions" that turns into
                // five is the one thing this screen can get wrong.
                Text("Three quick questions, then your week is ready. Everything else we'll assume for now and you can change any of it later.")
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
