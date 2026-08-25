// DislikesEditorSheet.swift — exercise-name avoid-list editor.
//
// Lifted out of ProfileScreen as part of the Option-C condense pass. Same
// tag-list UI as before (text field + add button + remove-chip), just in
// a sheet container.

import SwiftUI

struct DislikesEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var dislikeInput: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("EXERCISES TO AVOID")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        // "burpees" was the app's own suggested example and
                        // could never work: CoachDatabase's exclude path does a
                        // plain `lowerName.contains(dislike)` substring test and
                        // the catalog row is the SINGULAR "Burpee", so
                        // `like '%burpees%'` matches 0 of 582 exercises. The
                        // user followed the example verbatim, saw the chip
                        // appear as if it took effect, and kept being
                        // programmed burpees.
                        tagList(
                            items: store.memory.dislikes,
                            input: $dislikeInput,
                            placeholder: "e.g. burpee",
                            onAdd: { v in store.update { $0.dislikes.append(v) } },
                            onRemove: { v in store.update { $0.dislikes.removeAll { $0 == v } } }
                        )
                        // Tell the user whether the term actually excludes
                        // anything — the editor gave no match count, so a dead
                        // entry was indistinguishable from a working one.
                        ForEach(store.memory.dislikes, id: \.self) { term in
                            if Self.matchCount(for: term) == 0 {
                                Text("\"\(term)\" doesn't match any exercise — try a shorter word.")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused = false }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Exercises to avoid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    private func tagList(
        items: [String],
        input: Binding<String>,
        placeholder: String,
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: input, prompt: Text(placeholder).foregroundColor(Color.ink3))
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit {
                        commit(input: input, items: items, onAdd: onAdd)
                    }
                Button {
                    commit(input: input, items: items, onAdd: onAdd)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canCommit(input.wrappedValue) ? Color.accentInk : Color.ink3)
                        .frame(width: 44, height: 44)
                        .background(canCommit(input.wrappedValue) ? Color.accent : Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(canCommit(input.wrappedValue) ? Color.clear : Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canCommit(input.wrappedValue))
            }
            if !items.isEmpty {
                WrappingFlow(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 6) {
                            Text(item)
                                .font(.custom("Inter-Regular", size: 13))
                                .foregroundStyle(Color.ink)
                            Button { onRemove(item) } label: {
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
                }
            }
        }
    }

    private func canCommit(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commit(input: Binding<String>, items: [String], onAdd: (String) -> Void) {
        let trimmed = input.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !items.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        onAdd(trimmed)
        input.wrappedValue = ""
    }

    /// How many catalog exercises a dislike term would actually exclude.
    /// Mirrors CoachDatabase's exclude path, which is a plain substring test
    /// on the lowercased name.
    static func matchCount(for term: String) -> Int {
        let needle = term.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return 0 }
        return CoachDatabase.shared.listExercises()
            .filter { $0.name.lowercased().contains(needle) }
            .count
    }
}
