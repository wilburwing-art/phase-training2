// ExperienceEditorSheet.swift — experience level + starting state.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass.
//
// Carries BOTH halves of what OnboardingExperienceScreen used to ask:
// experience (skill ceiling — drives the routine difficulty filter and the
// sets/reps clamps) and startingState (current condition vs that ceiling,
// which the coach reads as a permanent profile fact). startingState landed
// here when the onboarding step was deleted; before that it was written by
// onboarding ONLY and had no permanent home, the same orphan the era-affinity
// step turned out to be.

import SwiftUI

struct ExperienceEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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
                                        action: {
                                            store.update {
                                                $0.experience = lvl
                                                $0.markStated(.experience)
                                            }
                                        },
                                        a11yId: "experience-level-\(lvl.rawValue)"
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Text("WHEN DID YOU LAST TRAIN CONSISTENTLY?")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            VStack(spacing: 8) {
                                ForEach(StartingState.allCases) { state in
                                    OnboardingPickRow(
                                        title: state.label,
                                        subtitle: state.subtitle,
                                        selected: store.memory.startingState == state,
                                        action: {
                                            store.update {
                                                $0.startingState = state
                                                $0.markStated(.experience)
                                            }
                                        },
                                        a11yId: "experience-state-\(state.rawValue)"
                                    )
                                }
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
