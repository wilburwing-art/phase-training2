// OnboardingSportSeasonsScreen.swift — per-sport season picker.
//
// For each sport in draft.sports, show a horizontal segmented picker for
// SeasonPhase. Writes to draft.seasonsBySport[sport].
//
// Edge cases:
//  - draft.sports empty → show one "default" picker for general fitness; writes
//    to draft.defaultSeason. Lets no-sport users still set context.
//  - default season is always shown at the bottom for fall-through cases (e.g.
//    sports added later via Profile would inherit it).

import SwiftUI

struct OnboardingSportSeasonsScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            step: .sportSeasons,
            title: "When are you in season?",
            subtitle: subtitleText,
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 22) {
                if draft.sports.isEmpty {
                    defaultSeasonPicker
                } else {
                    perSportPickers
                    Divider().background(Color.lineSoft)
                    defaultSeasonPicker
                }
                if showSupport {
                    Divider().background(Color.lineSoft)
                    supportSection
                }
            }
        }
    }

    /// The primary/support wedge is ski/board-primary + climbing-support, so
    /// this only appears for a ski/snow primary sport — the highest-intent
    /// moment to discover the two-sport feature.
    private var showSupport: Bool {
        PhaseRule.skiSlugs.contains(draft.primarySport?.slug ?? "")
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAIN TWO SPORTS?")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text("If you climb through your ski off-season, tell us your weekly rhythm and we'll plan your ski training around it — optional, and you can change it anytime.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            SupportPatternEditor(pattern: $draft.supportPattern, showBlurb: false)
        }
    }

    private var subtitleText: String {
        if draft.sports.isEmpty {
            return "How are you training? Off-season builds the engine; in-season protects performance."
        }
        return "Different sports can be in different phases. Pick what fits each."
    }

    private var perSportPickers: some View {
        VStack(spacing: 16) {
            ForEach(draft.sports) { sport in
                VStack(alignment: .leading, spacing: 8) {
                    Text(sport.name.uppercased())
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    SeasonChipRow(
                        selection: draft.seasonsBySport[sport] ?? draft.defaultSeason,
                        onPick: { draft.seasonsBySport[sport] = $0 }
                    )
                }
            }
        }
    }

    private var defaultSeasonPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.sports.isEmpty ? "TRAINING PHASE" : "OTHERWISE / DEFAULT")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            SeasonChipRow(
                selection: draft.defaultSeason,
                onPick: { draft.defaultSeason = $0 }
            )
        }
    }
}

private struct SeasonChipRow: View {
    let selection: SeasonPhase
    let onPick: (SeasonPhase) -> Void

    var body: some View {
        WrappingFlow(spacing: 6) {
            ForEach(SeasonPhase.allCases) { phase in
                OnboardingChip(
                    label: phase.label,
                    selected: selection == phase,
                    action: { onPick(phase) }
                )
            }
        }
    }
}

#Preview("With sports") {
    @Previewable @State var draft: TrainingMemory = {
        var m = TrainingMemory()
        m.sports = [
            Sport.catalog.first { $0.slug == "climbing" }!,
            Sport.catalog.first { $0.slug == "alpine-skiing" }!
        ]
        return m
    }()
    return OnboardingSportSeasonsScreen(draft: $draft, onNext: {}, onBack: {})
}

#Preview("No sports") {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingSportSeasonsScreen(draft: $draft, onNext: {}, onBack: {})
}
