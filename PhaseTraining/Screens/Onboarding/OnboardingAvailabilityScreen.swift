// OnboardingAvailabilityScreen.swift — step 5 of 8.
// Multi-select training days + a session-length stepper. The planner uses the
// day count to decide how many lift slots fit; session length picks routines
// from coach.db whose duration_minutes matches.

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
            title: "When can you train?",
            subtitle: "Pick the days you're typically free, and how long a session can run.",
            nextEnabled: !draft.availableDays.isEmpty,
            onNext: onNext,
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingSectionLabel(text: "Days")
                    HStack(spacing: 8) {
                        ForEach(Weekday.allCases) { day in
                            DayPill(day: day, selected: draft.availableDays.contains(day)) {
                                toggleDay(day)
                            }
                        }
                    }
                    Text("\(draft.availableDays.count) day\(draft.availableDays.count == 1 ? "" : "s") per week")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }

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
                    OnboardingSectionLabel(text: "Lift days per week")
                    stepperCard(
                        value: "\(draft.liftDaysPerWeek)",
                        unit: draft.liftDaysPerWeek == 1 ? "DAY" : "DAYS",
                        valueSize: 28,
                        onMinus: { adjustLifts(-1) },
                        onPlus:  { adjustLifts(1) }
                    )
                    Text(liftHint)
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

    private var liftHint: String {
        let cap = draft.availableDays.isEmpty ? 7 : draft.availableDays.count
        if draft.liftDaysPerWeek > cap {
            return "Capped at \(cap) — only \(cap) day\(cap == 1 ? "" : "s") available."
        }
        return "0 = no lift slots in your week."
    }

    private func toggleDay(_ day: Weekday) {
        if let idx = draft.availableDays.firstIndex(of: day) {
            draft.availableDays.remove(at: idx)
        } else {
            draft.availableDays.append(day)
            draft.availableDays.sort { $0.rawValue < $1.rawValue }
        }
        // Keep liftDaysPerWeek ≤ availableDays.count when day count drops.
        if !draft.availableDays.isEmpty {
            draft.liftDaysPerWeek = min(draft.liftDaysPerWeek, draft.availableDays.count)
        }
    }

    private func adjustMinutes(_ delta: Int) {
        let next = draft.sessionMinutes + delta
        draft.sessionMinutes = min(max(next, stepperBounds.lowerBound), stepperBounds.upperBound)
    }

    private func adjustLifts(_ delta: Int) {
        let cap = draft.availableDays.isEmpty ? 7 : draft.availableDays.count
        let next = draft.liftDaysPerWeek + delta
        draft.liftDaysPerWeek = min(max(next, 0), cap)
    }
}

private struct DayPill: View {
    let day: Weekday
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day.letter)
                .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                .foregroundStyle(selected ? Color.accentInk : Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(selected ? Color.accent : Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.clear : Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

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
