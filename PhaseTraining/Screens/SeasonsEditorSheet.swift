// SeasonsEditorSheet.swift — per-sport season + default-season picker.
//
// Lifted out of ProfileScreen during the Option-C condense pass. Preserves
// the build-78 peak-date row that appears when any selected season is
// .eventPrep.

import SwiftUI

struct SeasonsEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if store.memory.sports.isEmpty {
                            sectionLabel("DEFAULT")
                            seasonChips(
                                selected: store.memory.defaultSeason,
                                onPick: { s in store.update { $0.defaultSeason = s } }
                            )
                        } else {
                            ForEach(store.memory.sports) { sport in
                                VStack(alignment: .leading, spacing: 6) {
                                    sectionLabel(sport.name.uppercased())
                                    seasonChips(
                                        selected: store.memory.seasonsBySport[sport] ?? store.memory.defaultSeason,
                                        onPick: { s in store.update { $0.seasonsBySport[sport] = s } }
                                    )
                                }
                            }
                            sectionLabel("OTHERWISE")
                                .padding(.top, 4)
                            seasonChips(
                                selected: store.memory.defaultSeason,
                                onPick: { s in store.update { $0.defaultSeason = s } }
                            )
                        }
                        if hasEventPrepSelected {
                            peakDateRow
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Seasons")
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    private var hasEventPrepSelected: Bool {
        if store.memory.defaultSeason == .eventPrep { return true }
        return store.memory.seasonsBySport.values.contains(.eventPrep)
    }

    private var peakDateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("PEAK DATE")
                .padding(.top, 4)
            HStack {
                DatePicker(
                    "Peak date",
                    selection: Binding(
                        get: { store.memory.peakDate ?? Date() },
                        set: { newDate in store.update { $0.peakDate = newDate } }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                .labelsHidden()
                if store.memory.peakDate != nil {
                    Button("Clear") { store.update { $0.peakDate = nil } }
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func seasonChips(selected: SeasonPhase, onPick: @escaping (SeasonPhase) -> Void) -> some View {
        WrappingFlow(spacing: 6) {
            ForEach(SeasonPhase.allCases) { phase in
                OnboardingChip(
                    label: phase.label,
                    selected: selected == phase,
                    action: { onPick(phase) }
                )
            }
        }
    }
}
