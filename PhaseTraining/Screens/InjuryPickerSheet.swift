// InjuryPickerSheet.swift — multi-select picker over the 56 coach.db
// common_injuries, grouped by body region. The user's selections are
// committed as injury slugs into TrainingMemory.constraints, where
// DemographicProfile reads them to compute the contraindicated exercise
// id set for the planner.
//
// Replaces the free-text tag input that lived in Profile/Onboarding for
// constraints — that filter was string-matching exercise names and both
// over- and under-matched ("knee" filtered rehab exercises FOR knees, and
// "squat" wasn't tagged unsafe for patellar tendinopathy users).
//
// Free-text legacy entries (anything in constraints that doesn't match a
// known slug) are surfaced separately in the Profile screen with the
// option to remove them — they fall through to the old name-keyword
// filter until the user replaces them with a structured pick.

import SwiftUI

struct InjuryPickerSheet: View {
    let sportSlugs: Set<String>
    let initialSelection: Set<String>
    let onCommit: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var searchText: String = ""
    @State private var prevalenceByInjury: [String: [InjuryPrevalence]] = [:]

    private var grouped: [(region: String, items: [CommonInjury])] {
        let all = CoachDatabase.shared.listInjuries()
        let filtered: [CommonInjury] = {
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return all }
            // Search the body region too. Filtering on name alone meant the
            // most obvious query returned nothing: coach.db has zero injuries
            // whose NAME contains "knee", but eight with body_region='knee'
            // (Patellar Tendinopathy, ACL Sprain/Tear, MCL Sprain, Meniscus
            // Tear, IT Band Syndrome, Patellofemoral Pain Syndrome,
            // Chondromalacia Patella, Baker's Cyst) — all one group header
            // away, behind a "No matches" empty state. Same for back, hip,
            // ankle, neck.
            return all.filter {
                $0.name.lowercased().contains(q)
                    || $0.bodyRegionLabel.lowercased().contains(q)
                    || ($0.bodyRegion ?? "").lowercased().contains(q)
            }
        }()
        let dict = Dictionary(grouping: filtered, by: { $0.bodyRegionLabel })
        return dict.sorted { $0.key < $1.key }.map { (region: $0.key, items: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        searchField
                        if grouped.isEmpty {
                            empty
                        } else {
                            ForEach(grouped, id: \.region) { group in
                                groupBlock(region: group.region, items: group.items)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Injuries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onCommit(selected)
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            selected = initialSelection
            if !sportSlugs.isEmpty {
                prevalenceByInjury = CoachDatabase.shared.injuryPrevalence(forSportSlugs: sportSlugs)
            }
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .scaledSystemFont(14, within: 42)
                .foregroundStyle(Color.ink3)
            TextField("", text: $searchText,
                      prompt: Text("Search injuries…").foregroundColor(Color.ink3))
                .styled(.body)
                .foregroundStyle(Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lineStrong, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func groupBlock(region: String, items: [CommonInjury]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(region.uppercased())
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .padding(.bottom, 2)
            VStack(spacing: 6) {
                ForEach(items) { injury in
                    row(injury)
                }
            }
        }
    }

    /// "Common in Running, Climbing · Occasional in Golf". Rare is dropped.
    private func prevalenceHint(for injury: CommonInjury) -> String? {
        guard let rows = prevalenceByInjury[injury.slug] else { return nil }
        let parts = [InjuryPrevalence.Level.common, .occasional].compactMap { level -> String? in
            let names = rows.filter { $0.level == level }.map { Sport.resolve(slug: $0.sportSlug).name }
            return names.isEmpty ? nil : "\(level.label) in \(names.joined(separator: ", "))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ injury: CommonInjury) -> some View {
        let isSelected = selected.contains(injury.slug)
        return Button {
            if isSelected { selected.remove(injury.slug) }
            else          { selected.insert(injury.slug) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .scaledSystemFont(18)
                    .foregroundStyle(isSelected ? Color.accent : Color.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(injury.name)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    if let hint = prevalenceHint(for: injury) {
                        Text(hint)
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentWash : Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentBorder : Color.lineStrong, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No matches")
                .styled(.body)
                .foregroundStyle(Color.ink)
            Text("Try a shorter search or clear the filter.")
                .styled(.body)
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
