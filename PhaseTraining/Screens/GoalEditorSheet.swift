// GoalEditorSheet.swift — what the athlete trains for.
//
// Sets `TrainingMemory.trainingGoal`, which re-bands strength work in every
// season-engine session (`DemandScheme.scheme(for:progression:goal:)`). The
// goal is in `planInputsHash` once it leaves the default, so a change
// rebuilds the week through the memory-drift path.

import SwiftUI

struct GoalEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("WHAT ARE YOU TRAINING FOR?")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        VStack(spacing: 8) {
                            ForEach(TrainingGoal.allCases) { goal in
                                OnboardingPickRow(
                                    title: goal.label,
                                    subtitle: goal.subtitle,
                                    selected: store.memory.trainingGoal == goal,
                                    action: { store.update { $0.trainingGoal = goal; $0.markStated(.goal) } },
                                    a11yId: "goal-\(goal.rawValue)"
                                )
                            }
                        }
                        Text("Strength work follows your goal. Power, balance and sport-specific work keep what your season calls for.")
                            .styled(.body)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }
}
