// InjuriesEditorSheet.swift — injury picker entry point + per-injury metadata.
//
// Build 87: each selected injury is a structured `UserInjury` record with
// optional severity (Mild/Moderate/Severe), side (L/R/Both), and onset date.
// The picker still emits a Set<String> of slugs on commit; this sheet
// reconciles that against the existing UserInjury list so editing metadata
// in place doesn't lose it. Free-text legacy entries in memory.constraints
// (not matching any coach.db slug) continue to render below as removable
// chips so users can clear out stale notes.

import SwiftUI

struct InjuriesEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var presentingInjuryPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("INJURIES")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        injuriesPicker
                        if !legacyConstraints.isEmpty {
                            Text("OTHER NOTES (LEGACY)")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 6)
                            WrappingFlow(spacing: 8) {
                                ForEach(legacyConstraints, id: \.self) { item in
                                    legacyChip(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Injuries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .sheet(isPresented: $presentingInjuryPicker) {
                InjuryPickerSheet(
                    initialSelection: selectedSlugs,
                    onCommit: { newSlugs in commitInjuries(newSlugs) }
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Derived state

    private var selectedSlugs: Set<String> {
        Set(store.memory.userInjuries.map(\.slug))
    }

    /// Free-text constraints that DON'T match any coach.db injury slug —
    /// kept around so the keyword-filter fallback path still works for
    /// notes the user typed before the structured picker existed.
    private var legacyConstraints: [String] {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        return store.memory.constraints.filter { !known.contains($0) }
    }

    private func injuryName(forSlug slug: String) -> String {
        CoachDatabase.shared.listInjuries().first(where: { $0.slug == slug })?.name ?? slug
    }

    // MARK: - Picker block

    private var injuriesPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.memory.userInjuries.isEmpty {
                VStack(spacing: 10) {
                    ForEach(store.memory.userInjuries.sorted(by: { $0.slug < $1.slug })) { injury in
                        injuryCard(injury)
                    }
                }
            }
            Button {
                presentingInjuryPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(store.memory.userInjuries.isEmpty ? "Add injuries" : "Edit injuries")
                        .styled(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(store.memory.userInjuries.isEmpty ? Color.accent : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(store.memory.userInjuries.isEmpty ? Color.accentWash : Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(store.memory.userInjuries.isEmpty ? Color.accentBorder : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-add-injury")
            if store.memory.userInjuries.isEmpty && legacyConstraints.isEmpty {
                Text("We'll filter out exercises that aren't safe for the injuries you pick.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    /// Card per active injury — title + remove button + inline severity / side
    /// chips + optional onset date row. Tapping severity/side cycles through
    /// (unset → Mild → Moderate → Severe → unset). Cycling is simpler than a
    /// menu for 3-state pickers.
    private func injuryCard(_ injury: UserInjury) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(injuryName(forSlug: injury.slug))
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 6)
                Button {
                    removeInjury(slug: injury.slug)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ink3)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(injuryName(forSlug: injury.slug))")
            }
            HStack(spacing: 14) {
                metaPicker(title: "Severity",
                           options: InjurySeverity.allCases.map(\.label),
                           selected: injury.severity?.label) { label in
                    setSeverity(slug: injury.slug, label: label)
                }
                metaPicker(title: "Side",
                           options: InjurySide.allCases.map(\.short),
                           selected: injury.side?.short) { short in
                    setSide(slug: injury.slug, short: short)
                }
            }
            HStack(spacing: 8) {
                Text("Onset")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                if let onset = injury.onsetDate {
                    DatePicker("", selection: Binding(
                        get: { onset },
                        set: { setOnset(slug: injury.slug, date: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .tint(Color.accent)
                    Button {
                        setOnset(slug: injury.slug, date: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set onset") {
                        setOnset(slug: injury.slug, date: Date())
                    }
                    .styled(.body)
                    .foregroundStyle(Color.accent)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Compact horizontal segmented control. Renders the label, an "Any" chip
    /// for the unset state, and one chip per option. Highlights the selected
    /// chip; tapping the selected chip clears it.
    private func metaPicker(
        title: String,
        options: [String],
        selected: String?,
        onSelect: @escaping (String?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 4) {
                chip(label: "—", isSelected: selected == nil) {
                    onSelect(nil)
                }
                ForEach(options, id: \.self) { opt in
                    chip(label: opt, isSelected: selected == opt) {
                        onSelect(selected == opt ? nil : opt)
                    }
                }
            }
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(isSelected ? Color.accentInk : Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accent : Color.elevated)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accent : Color.line, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legacy chips (free-text constraints)

    private func legacyChip(_ item: String) -> some View {
        HStack(spacing: 6) {
            Text(item)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
            Button {
                store.update { $0.constraints.removeAll { $0 == item } }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
        .background(Color.elevated)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }

    // MARK: - Mutation

    /// Diff old vs new slug sets. Adds become bare `UserInjury(slug:)`
    /// entries; removals drop their record (including any severity / side /
    /// onset). Existing entries unaffected so editing metadata in place
    /// survives a round-trip through the picker.
    private func commitInjuries(_ newSlugs: Set<String>) {
        store.update { mem in
            let oldSlugs = Set(mem.userInjuries.map(\.slug))
            let added = newSlugs.subtracting(oldSlugs)
            let removed = oldSlugs.subtracting(newSlugs)
            mem.userInjuries.removeAll { removed.contains($0.slug) }
            for slug in added.sorted() {
                mem.userInjuries.append(UserInjury(slug: slug))
            }
        }
    }

    private func removeInjury(slug: String) {
        store.update { mem in
            mem.userInjuries.removeAll { $0.slug == slug }
        }
    }

    private func setSeverity(slug: String, label: String?) {
        let severity: InjurySeverity? = label.flatMap { l in
            InjurySeverity.allCases.first { $0.label == l }
        }
        store.update { mem in
            guard let idx = mem.userInjuries.firstIndex(where: { $0.slug == slug }) else { return }
            mem.userInjuries[idx].severity = severity
        }
    }

    private func setSide(slug: String, short: String?) {
        let side: InjurySide? = short.flatMap { s in
            InjurySide.allCases.first { $0.short == s }
        }
        store.update { mem in
            guard let idx = mem.userInjuries.firstIndex(where: { $0.slug == slug }) else { return }
            mem.userInjuries[idx].side = side
        }
    }

    private func setOnset(slug: String, date: Date?) {
        store.update { mem in
            guard let idx = mem.userInjuries.firstIndex(where: { $0.slug == slug }) else { return }
            mem.userInjuries[idx].onsetDate = date
        }
    }
}
