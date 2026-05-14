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
                    HStack(spacing: 14) {
                        StepperButton(symbol: "minus") { adjustMinutes(-stepSize) }
                        VStack(spacing: 0) {
                            Text("\(draft.sessionMinutes)")
                                .font(.custom("JetBrainsMono-SemiBold", size: 34))
                                .foregroundStyle(Color.ink)
                            Text("MIN")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        StepperButton(symbol: "plus") { adjustMinutes(stepSize) }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text("Most users land between 30 and 60 min.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func toggleDay(_ day: Weekday) {
        if let idx = draft.availableDays.firstIndex(of: day) {
            draft.availableDays.remove(at: idx)
        } else {
            draft.availableDays.append(day)
            draft.availableDays.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func adjustMinutes(_ delta: Int) {
        let next = draft.sessionMinutes + delta
        draft.sessionMinutes = min(max(next, stepperBounds.lowerBound), stepperBounds.upperBound)
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
