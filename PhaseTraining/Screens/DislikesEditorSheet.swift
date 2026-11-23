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
                                Text("\"\(term)\" doesn't match any exercise. Try a shorter word.")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        stoppedSection
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

    private var stopped: [StoppedExercise] {
        PatternEngine.stoppedExercises(
            decisions: store.memory.suggestionDecisions,
            affinities: store.memory.exerciseAffinities)
    }

    @ViewBuilder
    private var stoppedSection: some View {
        let items = stopped
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("STOPPED FROM CHECK-IN")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 10)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .styled(.body)
                                .foregroundStyle(Color.ink)
                            Text("Stopped \(Text(item.stoppedAt, format: .dateTime.month(.abbreviated).day()))")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        }
                        Spacer(minLength: 8)
                        Button("Plan it again") { store.resumePlanning(item.name) }
                            .foregroundStyle(Color.accent)
                            .accessibilityLabel("Plan \(item.name) again")
                    }
                }
                Text("You chose Stop planning it on these in a weekly check-in. Plan it again goes back to no preference.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lineStrong, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit {
                        commit(input: input, items: items, onAdd: onAdd)
                    }
                Button {
                    commit(input: input, items: items, onAdd: onAdd)
                } label: {
                    Image(systemName: "plus")
                        .scaledSystemFont(14, weight: .semibold, within: 44)
                        .foregroundStyle(canCommit(input.wrappedValue) ? Color.accentInk : Color.ink3)
                        .frame(width: 44, height: 44)
                        .background(canCommit(input.wrappedValue) ? Color.accent : Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(canCommit(input.wrappedValue) ? Color.clear : Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Add")
                }
                .buttonStyle(.plain)
                .disabled(!canCommit(input.wrappedValue))
            }
            if !items.isEmpty {
                WrappingFlow(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 6) {
                            Text(item)
                                .font(.scaled("Inter-Regular", size: 13))
                                .foregroundStyle(Color.ink)
                            Button { onRemove(item) } label: {
                                Image(systemName: "xmark")
                                    .scaledSystemFont(9, weight: .bold)
                                    .foregroundStyle(Color.ink3)
                                    .accessibilityLabel("Remove \(item)")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
                        .background(Color.elevated)
                        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.lineStrong, lineWidth: 0.5))
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
