// SkiDisciplineSheet.swift — how a ski primary skis.
//
// Sets `TrainingMemory.skiDiscipline`, which picks the season engine's ski
// variant (`TrainingMemory.primaryVariant`). Once set it joins
// `planInputsHash`, so a change rebuilds the week through the memory-drift path.

import SwiftUI

struct SkiDisciplineSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("HOW DO YOU SKI?")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        SkiDisciplinePicker(selection: store.memory.primaryVariant,
                                            onPick: { v in store.update { $0.skiDiscipline = v } },
                                            idPrefix: "discipline")
                        Text("Changes the mix: uphill aerobic work, strength, power and landing work shift to fit how you ski.")
                            .styled(.body)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Discipline")
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

/// The four ski disciplines as pick rows; shared by onboarding and Profile.
struct SkiDisciplinePicker: View {
    let selection: SportVariant
    let onPick: (SportVariant) -> Void
    let idPrefix: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(SportVariant.skiDisciplines, id: \.self) { v in
                OnboardingPickRow(
                    title: v.disciplineLabel,
                    subtitle: v.disciplineSubtitle,
                    selected: selection == v,
                    action: { onPick(v) },
                    a11yId: "\(idPrefix)-\(v.rawValue)"
                )
            }
        }
    }
}
