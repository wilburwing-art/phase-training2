// GoalPickerSheet.swift — PR 11 of the weekly-coach roadmap.
//
// Pick 1-2 active goals from the curated GoalTemplate set. Reached from
// Profile → TRAINING SETUP → Goals. Selecting writes
// TrainingMemory.userGoals (replacing the previous set — goals are
// active/inactive, not accumulated history).
//
// Style mirrors AbandonReasonSheet: dark, card rows with a checkmark on
// selection, sticky confirm in the toolbar.

import SwiftUI

struct GoalPickerSheet: View {
    /// Currently active goals (pre-selection state).
    let activeGoals: [UserGoal]
    let onConfirm: ([UserGoal]) -> Void

    @State private var selected: [GoalTemplate]
    @Environment(\.dismiss) private var dismiss

    init(activeGoals: [UserGoal], onConfirm: @escaping ([UserGoal]) -> Void) {
        self.activeGoals = activeGoals
        self.onConfirm = onConfirm
        _selected = State(initialValue: activeGoals.map(\.templateId))
    }

    private func toggle(_ t: GoalTemplate) {
        if let idx = selected.firstIndex(of: t) {
            selected.remove(at: idx)
        } else if selected.count < 2 {
            selected.append(t)
        }
        // >2 selected: ignore the tap — the footer explains the cap.
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pick 1-2 goals to track. Progress shows on the Progress tab.")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 14)

                VStack(spacing: 8) {
                    ForEach(GoalTemplate.allCases) { t in
                        let isOn = selected.contains(t)
                        Button {
                            toggle(t)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.label)
                                        .styled(.body)
                                        .foregroundStyle(Color.ink)
                                    Text(t.subtitle)
                                        .font(.monoXS)
                                        .foregroundStyle(Color.ink3)
                                }
                                Spacer()
                                if isOn {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isOn ? Color.surface : Color.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isOn ? Color.accentBorder : Color.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("goal-\(t.rawValue)")
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let now = Date()
                        // Preserve createdAt on goals that stay active.
                        let prior = Dictionary(uniqueKeysWithValues:
                            activeGoals.map { ($0.templateId, $0.createdAt) })
                        onConfirm(selected.map { t in
                            UserGoal(templateId: t,
                                     createdAt: prior[t] ?? now)
                        })
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
    }
}

#Preview {
    GoalPickerSheet(activeGoals: [], onConfirm: { _ in })
}