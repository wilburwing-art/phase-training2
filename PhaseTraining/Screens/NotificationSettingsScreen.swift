// NotificationSettingsScreen.swift — PR 12 of the weekly-coach roadmap.
//
// Per-class notification toggles (spec §7). Each row toggles a
// NotificationBudget.Class; disabled classes never schedule. The daily
// cap itself (3/day) is not user-adjustable — it's the governance
// contract, and a slider here would just be a way to re-derive the
// "app talks too much" problem this PR exists to fix.
//
// Reached from Profile → Notifications.

import SwiftUI

struct NotificationSettingsScreen: View {
    @State private var enabled: [NotificationBudget.Class: Bool] = [:]

    var body: some View {
        List {
            Section {
                ForEach([NotificationBudget.Class].allCasesInDisplayOrder, id: \.self) { cls in
                    Toggle(cls.label, isOn: binding(for: cls))
                }
            } footer: {
                Text(
                    "PhaseTraining will send at most 3 push notifications a day " +
                    "(workout timers don't count — they only fire while a workout is running). " +
                    "Notifications you dismiss repeatedly are suppressed automatically."
                )
            }
        }
        .navigationTitle("Notifications")
        .onAppear(perform: load)
    }

    private func load() {
        for cls in NotificationBudget.Class.allCases {
            enabled[cls] = NotificationBudget.isEnabled(cls)
        }
    }

    private func binding(for cls: NotificationBudget.Class) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.enabled[cls] ?? true },
            set: { newValue in
                self.enabled[cls] = newValue
                NotificationBudget.setEnabled(newValue, for: cls)
            }
        )
    }
}

private extension Array where Element == NotificationBudget.Class {
    /// Display order: most-actionable first, matching the budget's
    /// priority semantics.
    static var allCasesInDisplayOrder: [NotificationBudget.Class] {
        [.missedWorkout, .weeklyPlan, .coachMilestone, .operational]
    }
}

#Preview {
    NavigationStack { NotificationSettingsScreen() }
}
