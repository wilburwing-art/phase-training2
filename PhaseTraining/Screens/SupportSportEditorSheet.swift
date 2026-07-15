// SupportSportEditorSheet.swift — Profile → "Support sport". Declare the
// SUPPORT sport's weekly load (primary/support model, PLAN-primary-support.md).
//
// Thin chrome around the shared SupportPatternEditor: a store-backed binding
// routes every edit through store.update (persist + auto-regen). The editing
// UI itself lives in SupportPatternEditor so onboarding reuses it verbatim.

import SwiftUI

struct SupportSportEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    /// Reads memory.supportPattern; writes route through store.update so the
    /// change persists and the plan reflows.
    private var patternBinding: Binding<SupportPattern?> {
        Binding(
            get: { store.memory.supportPattern },
            set: { newValue in store.update { $0.supportPattern = newValue } }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    SupportPatternEditor(pattern: patternBinding)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Support Sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }
}
