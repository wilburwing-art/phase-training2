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
                                onPick: { s in pickDefaultSeason(s) }
                            )
                        } else {
                            ForEach(store.memory.sports) { sport in
                                VStack(alignment: .leading, spacing: 6) {
                                    sectionLabel(sport.name.uppercased())
                                    seasonChips(
                                        selected: store.memory.seasonsBySport[sport] ?? store.memory.defaultSeason,
                                        onPick: { s in pickSportSeason(sport: sport, season: s) }
                                    )
                                }
                            }
                            sectionLabel("OTHERWISE")
                                .padding(.top, 4)
                            seasonChips(
                                selected: store.memory.defaultSeason,
                                onPick: { s in pickDefaultSeason(s) }
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

    /// Stamp `phaseStartedAt` whenever the planner-active season actually
    /// changes — the SeasonPhaseBadge reads this to render "Week N". A tap
    /// that re-picks the same chip leaves the stamp alone so the user can
    /// re-open the sheet without resetting their counter.
    private func pickDefaultSeason(_ season: SeasonPhase) {
        let prevPlanner = store.memory.seasonForPlanner
        store.update { mem in
            mem.defaultSeason = season
            if mem.seasonForPlanner != prevPlanner {
                mem.phaseStartedAt = Date()
            }
        }
    }

    private func pickSportSeason(sport: Sport, season: SeasonPhase) {
        let prevPlanner = store.memory.seasonForPlanner
        store.update { mem in
            mem.seasonsBySport[sport] = season
            if mem.seasonForPlanner != prevPlanner {
                mem.phaseStartedAt = Date()
            }
        }
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
            // An unset peak date must LOOK unset. Binding `get:` to `?? Date()`
            // rendered today's date as though it were chosen, and the Clear
            // button keyed off `peakDate != nil` so it stayed hidden — a user
            // in Event Prep opened Seasons, saw a plausible date already
            // filled in, closed the sheet, and peakDate was still nil, so the
            // taper never engaged. It also made "my event IS today"
            // unsettable, since picking the shown value changes nothing.
            HStack {
                if let peak = store.memory.peakDate {
                    DatePicker(
                        "Peak date",
                        selection: Binding(
                            get: { peak },
                            set: { newDate in store.update { $0.peakDate = newDate } }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    Button("Clear") { store.update { $0.peakDate = nil } }
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                } else {
                    Text("Not set")
                        .styled(.body)
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    Button("Set date") {
                        store.update { $0.peakDate = Calendar.current.startOfDay(for: Date()) }
                    }
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
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
