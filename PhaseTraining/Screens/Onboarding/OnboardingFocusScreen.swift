// OnboardingFocusScreen.swift — step 3 of 8.
// Single-select PrimaryFocus. Drives planner emphasis: which DayKind to favor,
// rep ranges, time allocation between strength / power / endurance / mobility.

import SwiftUI

struct OnboardingFocusScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            step: .focus,
            title: "What's the goal?",
            subtitle: "Pick the one that matters most right now. You can change it later.",
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(spacing: 10) {
                ForEach(PrimaryFocus.allCases) { focus in
                    OnboardingPickRow(
                        title: focus.label,
                        subtitle: focus.subtitle,
                        selected: draft.primaryFocus == focus,
                        action: { draft.primaryFocus = focus }
                    )
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingFocusScreen(draft: $draft, onNext: {}, onBack: {})
}
