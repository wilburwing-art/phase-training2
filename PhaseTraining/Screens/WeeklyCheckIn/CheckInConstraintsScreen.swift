// CheckInConstraintsScreen.swift — step 2: days you can't train next week.

import SwiftUI

struct CheckInConstraintsScreen: View {
    @Binding var draft: WeeklyCheckInDraft
    let onNext: () -> Void
    let onBack: () -> Void
    /// Escape hatch. Steps 2-5 passed nil, so CheckInScaffold rendered a blank
    /// 32x32 spacer where the X should be — a user who opened the flow from the
    /// Sunday notification and wanted out had to tap Back three or four times.
    let onClose: () -> Void

    var body: some View {
        CheckInScaffold(
            step: .constraints,
            title: "Days off.",
            subtitle: "Tap any days you can't train. You'll add races and sessions in the next step.",
            nextLabel: "Continue",
            nextEnabled: true,
            onNext: onNext,
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("UNAVAILABLE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Weekday.allCases) { day in
                        OnboardingChip(
                            label: day.short,
                            selected: draft.unavailableDays.contains(day),
                            action: { toggle(day) }
                        )
                    }
                }
            }
        }
    }

    private func toggle(_ day: Weekday) {
        if draft.unavailableDays.contains(day) { draft.unavailableDays.remove(day) }
        else { draft.unavailableDays.insert(day) }
    }
}
