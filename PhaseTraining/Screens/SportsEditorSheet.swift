// SportsEditorSheet.swift — focused editor for the Profile sports list.
//
// Lifted out of ProfileScreen as the first step of Option C (settings-row
// summary on Profile, sheet-based editor here). The picker UI is the same
// chip grid + primary-sport pick rows the original section used — just in
// a sheet container with detents so it doesn't feel like a full nav push.

import SwiftUI

struct SportsEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SPORTS")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        WrappingFlow(spacing: 8) {
                            ForEach(Sport.catalog.filter { SportCatalog.isPlannable($0.slug) }) { sport in
                                OnboardingChip(
                                    label: sport.name,
                                    selected: store.memory.sports.contains(sport),
                                    action: { toggleSport(sport) }
                                )
                            }
                        }
                        if store.memory.sports.count > 1 {
                            Text("PRIMARY")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 8)
                            VStack(spacing: 8) {
                                ForEach(store.memory.sports) { sport in
                                    OnboardingPickRow(
                                        title: sport.name,
                                        subtitle: nil,
                                        selected: store.memory.primarySport == sport,
                                        action: {
                                            store.update { $0.primarySport = sport }
                                        }
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
            .navigationTitle("Sports")
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

    /// Same toggle behavior as the inline ProfileScreen version: clears
    /// primary when sport leaves the list; reassigns primary to first
    /// remaining sport when the previous primary is deselected.
    private func toggleSport(_ sport: Sport) {
        store.update { mem in
            if let idx = mem.sports.firstIndex(of: sport) {
                mem.sports.remove(at: idx)
                if mem.primarySport == sport {
                    mem.primarySport = mem.sports.first
                }
            } else {
                mem.sports.append(sport)
                if mem.primarySport == nil {
                    mem.primarySport = sport
                }
            }
        }
    }
}
