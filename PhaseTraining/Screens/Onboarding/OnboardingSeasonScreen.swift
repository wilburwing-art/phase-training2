// OnboardingSeasonScreen.swift — step 4 of 8.
// Single-select SeasonPhase. Modulates volume + specificity at planning time
// (off-season → high volume / low specificity; in-season → maintain / recover).

import SwiftUI

struct OnboardingSeasonScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            step: .season,
            title: "Where are you in the year?",
            subtitle: "Tells us how hard to push and how much to recover.",
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(spacing: 10) {
                ForEach(SeasonPhase.allCases) { season in
                    OnboardingPickRow(
                        title: season.label,
                        subtitle: season.subtitle,
                        selected: draft.season == season,
                        action: { draft.season = season }
                    )
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingSeasonScreen(draft: $draft, onNext: {}, onBack: {})
}
