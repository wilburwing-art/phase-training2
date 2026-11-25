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
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SportSearchField(text: $searchText)
                        let sections = SportPickerCatalog.sections(matching: searchText)
                        if sections.isEmpty {
                            SportPickerEmptyLine()
                        }
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.root.name.uppercased())
                                    .styled(.micro)
                                    .foregroundStyle(Color.ink3)
                                    .accessibilityAddTraits(.isHeader)
                                WrappingFlow(spacing: 8) {
                                    ForEach(section.sports) { sport in
                                        OnboardingChip(
                                            label: sport.name,
                                            selected: store.memory.sports.contains(sport),
                                            action: { toggleSport(sport) }
                                        )
                                    }
                                }
                            }
                        }
                        if store.memory.sports.count == 1 {
                            Text("Keep at least one sport. Pick another first to switch.")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
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
                        if !recoveryProfiles.isEmpty {
                            Text("RECOVERY")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 8)
                            VStack(spacing: 8) {
                                ForEach(store.memory.sports) { sport in
                                    if let profile = recoveryProfiles[sport.slug] {
                                        recoveryCard(sport: sport, profile: profile)
                                    }
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

    private var recoveryProfiles: [String: SportRecoveryProfile] {
        CoachDatabase.shared.sportRecoveryProfiles(
            forSportSlugs: Set(store.memory.sports.map(\.slug)))
    }

    private func recoveryCard(sport: Sport, profile: SportRecoveryProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sport.name)
                .styled(.body)
                .foregroundStyle(Color.ink)
            if let hours = profile.typicalRecoveryHours {
                Text("Typically recovers in \(hours) h")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink2)
            }
            if !profile.avoidLabels.isEmpty {
                Text("Go easy before a session: \(profile.avoidLabels.joined(separator: ", "))")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sport-recovery-\(sport.slug)")
    }

    /// Same toggle behavior as the inline ProfileScreen version: clears
    /// primary when sport leaves the list; reassigns primary to first
    /// remaining sport when the previous primary is deselected. The last
    /// sport cannot be removed.
    private func toggleSport(_ sport: Sport) {
        // The planner has nothing to build without a sport: removing the last
        // one turned every lift day into an empty "Rest". Onboarding enforces
        // the same floor with `nextEnabled: !draft.sports.isEmpty`.
        if store.memory.sports == [sport] { return }
        store.update { mem in
            if let idx = mem.sports.firstIndex(of: sport) {
                mem.sports.remove(at: idx)
                if mem.primarySport == sport {
                    mem.primarySport = mem.sports.first
                }
                // Drop the season too. Planner.applySecondarySportPromotion
                // iterates memory.seasonsBySport with no membership check, so a
                // deselected sport still marked .inSeason kept getting a
                // placeholder day booked into the week forever — and no UI
                // could reach the orphaned entry, since SeasonsEditorSheet only
                // iterates memory.sports.
                mem.seasonsBySport[sport] = nil
            } else {
                mem.sports.append(sport)
                if mem.primarySport == nil {
                    mem.primarySport = sport
                }
            }
        }
    }
}
