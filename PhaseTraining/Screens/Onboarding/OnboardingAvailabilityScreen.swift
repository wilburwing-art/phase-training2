// OnboardingAvailabilityScreen.swift — Phase 11 trim.
// Sets long-term training preferences (session length + target lift days).
// Per-week availability now lives in WeekOverrides — the user customizes
// "this week" from the Week tab, not here.

import SwiftUI

struct OnboardingAvailabilityScreen: View {
    @Binding var draft: TrainingMemory
    let onNext: () -> Void
    let onBack: () -> Void

    private let stepperBounds = 15...120
    private let stepSize = 15

    var body: some View {
        OnboardingScaffold(
            step: .availability,
            title: "How do you train?",
            subtitle: "Defaults for every week — you'll set which specific days you're free in the Week tab.",
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingSectionLabel(text: "Session length")
                    stepperCard(
                        value: "\(draft.sessionMinutes)",
                        unit: "MIN",
                        valueSize: 34,
                        onMinus: { adjustMinutes(-stepSize) },
                        onPlus:  { adjustMinutes(stepSize) }
                    )
                    Text("Most users land between 30 and 60 min.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingSectionLabel(text: "Target lift days per week")
                    stepperCard(
                        value: "\(draft.liftDaysPerWeek)",
                        unit: draft.liftDaysPerWeek == 1 ? "DAY" : "DAYS",
                        valueSize: 28,
                        onMinus: { adjustLifts(-1) },
                        onPlus:  { adjustLifts(1) }
                    )
                    Text("0 = no lift slots. Capped at the days you have free this week.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    @ViewBuilder
    private func stepperCard(value: String, unit: String, valueSize: CGFloat,
                             onMinus: @escaping () -> Void,
                             onPlus:  @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            StepperButton(symbol: "minus", action: onMinus)
            VStack(spacing: 0) {
                Text(value)
                    .font(.custom("JetBrainsMono-SemiBold", size: valueSize))
                    .foregroundStyle(Color.ink)
                Text(unit)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity)
            StepperButton(symbol: "plus", action: onPlus)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func adjustMinutes(_ delta: Int) {
        let next = draft.sessionMinutes + delta
        draft.sessionMinutes = min(max(next, stepperBounds.lowerBound), stepperBounds.upperBound)
    }

    private func adjustLifts(_ delta: Int) {
        let next = draft.liftDaysPerWeek + delta
        draft.liftDaysPerWeek = min(max(next, 0), 7)
    }
}

// Small +/- pill used by Availability's bounded steppers (session length
// 30–90 min, lift days 0–7). Age/height/weight stopped using this in
// build 49 — those went typeable. Kept private here since this is the
// only remaining caller.
private struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 48, height: 48)
                .background(Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var draft = TrainingMemory()
    return OnboardingAvailabilityScreen(draft: $draft, onNext: {}, onBack: {})
}
