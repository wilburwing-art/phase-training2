// OnboardingExperienceScreen.swift — experience + current-state picker.
//
// Two questions, both single-select. Experience = skill ceiling (drives
// routine difficulty filter + sets/reps clamps). StartingState = current
// condition (drives the calibration-week mechanic — same 7-day window for
// everyone, but per-state intensity + soreness messaging).

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
            VStack(alignment: .leading, spacing: 24) {
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

                OnboardingSectionLabel(text: "When did you last train consistently?")
                VStack(spacing: 10) {
                    ForEach(StartingState.allCases) { state in
                        OnboardingPickRow(
                            title: state.label,
                            subtitle: state.subtitle,
                            selected: draft.startingState == state,
                            action: { draft.startingState = state }
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingExperienceScreen(draft: $draft, onNext: {}, onBack: {})
}
