// OnboardingExperienceScreen.swift — step 7 of 8.
// Single-select ExperienceLevel. Maps directly onto coach.db routine difficulty
// (beginner / intermediate / advanced); the planner filters routine candidates
// to ≤ user's level.

import SwiftUI

struct OnboardingExperienceScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            step: .experience,
            title: "How experienced are you?",
            subtitle: "Be honest — we'd rather start easy and ramp.",
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(spacing: 10) {
                ForEach(ExperienceLevel.allCases) { lvl in
                    OnboardingPickRow(
                        title: lvl.label,
                        subtitle: lvl.subtitle,
                        selected: draft.experience == lvl,
                        action: { draft.experience = lvl }
                    )
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingExperienceScreen(draft: $draft, onNext: {}, onBack: {})
}
