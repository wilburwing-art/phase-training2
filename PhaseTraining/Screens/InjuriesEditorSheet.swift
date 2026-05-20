// InjuriesEditorSheet.swift — injury picker entry point + legacy free-text chip list.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass. Wraps
// the existing InjuryPickerSheet (multi-select over coach.db injuries) and
// surfaces any legacy free-text constraint entries with removable chips.

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
                    initialSelection: selectedInjurySlugs,
                    onCommit: { newSlugs in commitInjuries(newSlugs) }
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    private var selectedInjurySlugs: Set<String> {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        return Set(store.memory.constraints.filter { known.contains($0) })
    }

    private var legacyConstraints: [String] {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        return store.memory.constraints.filter { !known.contains($0) }
    }

    private var injuriesPicker: some View {
        let selected = selectedInjurySlugs
        let all = CoachDatabase.shared.listInjuries()
        let nameFor: (String) -> String = { slug in
            all.first(where: { $0.slug == slug })?.name ?? slug
        }
        return VStack(alignment: .leading, spacing: 10) {
            if !selected.isEmpty {
                WrappingFlow(spacing: 8) {
                    ForEach(Array(selected).sorted(), id: \.self) { slug in
                        injuryChip(label: nameFor(slug), onRemove: {
                            removeInjury(slug)
                        })
                    }
                }
            }
            Button {
                presentingInjuryPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(selected.isEmpty ? "Add injuries" : "Edit injuries")
                        .styled(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(selected.isEmpty ? Color.accent : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(selected.isEmpty ? Color.accentWash : Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected.isEmpty ? Color.accentBorder : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-add-injury")
            if selected.isEmpty && legacyConstraints.isEmpty {
                Text("We'll filter out exercises that aren't safe for the injuries you pick.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func injuryChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
        .background(Color.accentWash)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.accentBorder, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }

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

    private func commitInjuries(_ newSlugs: Set<String>) {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        store.update { mem in
            mem.constraints = mem.constraints.filter { !known.contains($0) } + Array(newSlugs).sorted()
        }
    }

    private func removeInjury(_ slug: String) {
        store.update { mem in
            mem.constraints.removeAll { $0 == slug }
        }
    }
}
