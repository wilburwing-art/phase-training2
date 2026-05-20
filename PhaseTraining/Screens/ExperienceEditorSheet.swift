// ExperienceEditorSheet.swift — experience-level single-pick.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass.

import SwiftUI

struct ExperienceEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("EXPERIENCE")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        VStack(spacing: 8) {
                            ForEach(ExperienceLevel.allCases) { lvl in
                                OnboardingPickRow(
                                    title: lvl.label,
                                    subtitle: lvl.subtitle,
                                    selected: store.memory.experience == lvl,
                                    action: { store.update { $0.experience = lvl } }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Experience")
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
