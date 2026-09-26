// CheckInPatternsScreen.swift — A4 pre-step: what your last few weeks say.
//
// Shows at most three PatternEngine suggestions, each a claim, one line of
// evidence and two buttons. Apply performs the change through an existing seam
// (PlanStore.acceptSuggestion) and records the decision; Not now records a
// dismissal that keeps the card away for 8 weeks. Either way the card leaves
// the list. Like CheckInMissedScreen, a decision commits on tap, so the
// preview this flow regenerates later already reflects it.
//
// Lives in the check-in rather than on Today because every rule here reads
// several weeks of behavior (phase-training-tab-time-horizon-rule).

import SwiftUI

struct CheckInPatternsScreen: View {
    @EnvironmentObject private var planStore: PlanStore

    @Binding var suggestions: [Suggestion]
    let onNext: () -> Void
    let onBack: (() -> Void)?
    let onClose: () -> Void

    @State private var failedIds: Set<String> = []

    var body: some View {
        CheckInScaffold(
            step: .patterns,
            title: "What we noticed.",
            subtitle: "From your last four weeks. Apply what fits; skip what doesn't.",
            nextLabel: suggestions.isEmpty ? "Continue" : "Skip for now",
            nextEnabled: true,
            onNext: onNext,
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(suggestions) { s in
                    card(s)
                }
                if suggestions.isEmpty {
                    Text("All set.")
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func card(_ s: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: s.rule))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    Text(s.evidence)
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink2)
                    if failedIds.contains(s.id) {
                        Text("Couldn't apply that. Nothing changed.")
                            .styled(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 4)
                Button { dismiss(s) } label: {
                    Text("Not now")
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.line, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pattern-dismiss-\(s.id)")

                Button { accept(s) } label: {
                    Text(s.acceptLabel)
                        .styled(.monoXS)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pattern-accept-\(s.id)")
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("pattern-card-\(s.id)")
    }

    private func accept(_ s: Suggestion) {
        if planStore.acceptSuggestion(s) {
            remove(s)
        } else {
            failedIds.insert(s.id)
        }
    }

    private func dismiss(_ s: Suggestion) {
        planStore.dismissSuggestion(s)
        remove(s)
    }

    private func remove(_ s: Suggestion) {
        withAnimation(.easeInOut(duration: 0.18)) {
            suggestions.removeAll { $0.id == s.id }
        }
    }

    private func icon(for rule: SuggestionRule) -> String {
        switch rule {
        case .sessionLength:   return "clock"
        case .droppedExercise: return "arrow.uturn.down"
        case .viewedRoutine:   return "bookmark"
        }
    }
}
