// FocusesEditorSheet.swift — multi-pick focuses + primary reorder.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass.

import SwiftUI

struct FocusesEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("FOCUSES")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        VStack(spacing: 8) {
                            ForEach(PrimaryFocus.allCases) { focus in
                                OnboardingPickRow(
                                    title: focus.label,
                                    subtitle: focus.subtitle,
                                    selected: store.memory.focuses.contains(focus),
                                    action: { toggleFocus(focus) }
                                )
                            }
                        }
                        if store.memory.focuses.count > 1 {
                            Text("PRIMARY")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 8)
                            VStack(spacing: 8) {
                                ForEach(store.memory.focuses) { focus in
                                    OnboardingPickRow(
                                        title: focus.label,
                                        subtitle: nil,
                                        selected: store.memory.focuses.first == focus,
                                        action: { setPrimaryFocus(focus) }
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
            .navigationTitle("Focuses")
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

    /// Same multi-pick + primary-reorder rules as the previous inline UI:
    /// adding when not present; removing when present; if the removed focus
    /// was primary, the new first becomes primary.
    private func toggleFocus(_ focus: PrimaryFocus) {
        store.update { mem in
            if let idx = mem.focuses.firstIndex(of: focus) {
                mem.focuses.remove(at: idx)
            } else {
                mem.focuses.append(focus)
            }
        }
    }

    private func setPrimaryFocus(_ focus: PrimaryFocus) {
        store.update { mem in
            guard let idx = mem.focuses.firstIndex(of: focus) else { return }
            mem.focuses.remove(at: idx)
            mem.focuses.insert(focus, at: 0)
        }
    }
}
