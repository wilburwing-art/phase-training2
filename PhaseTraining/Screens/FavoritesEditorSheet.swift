// FavoritesEditorSheet.swift — the liked-exercise list, the positive mirror of
// DislikesEditorSheet.
//
// Reads `TrainingMemory.exerciseAffinities` (score > 0 only). There is no
// free-text add: affinities are keyed by exact catalog names and are earned
// by tapping "Recommend more often" on an exercise, or by swapping toward it.
// Removing a chip clears the score to nil, which is the generator's "no
// preference", not a dislike.

import SwiftUI

struct FavoritesEditorSheet: View {
    @EnvironmentObject private var store: MemoryStore
    @Environment(\.dismiss) private var dismiss

    /// (name, score) with score > 0, strongest first, then by name so the
    /// order is stable across renders.
    static func favorites(in affinities: [String: Int]) -> [(name: String, score: Int)] {
        AthleteState.lowercasedAffinities(affinities)
            .filter { $0.value > 0 }
            .map { (name: displayName(for: $0.key, in: affinities), score: $0.value) }
            .sorted { ($1.score, $0.name) < ($0.score, $1.name) }
    }

    /// The generator folds case; the chip should show the name as the user
    /// last saw it. Prefer a raw key that matches case-insensitively.
    private static func displayName(for folded: String, in raw: [String: Int]) -> String {
        raw.keys.first { $0.lowercased() == folded } ?? folded
    }

    private var favorites: [(name: String, score: Int)] {
        Self.favorites(in: store.memory.exerciseAffinities)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("EXERCISES YOU'VE ASKED FOR MORE OF")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        if favorites.isEmpty {
                            Text("Tap an exercise on Today and choose Recommend more often. It shows up here, and the planner favours it when it rotates back in.")
                                .styled(.body)
                                .foregroundStyle(Color.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            WrappingFlow(spacing: 8) {
                                ForEach(favorites, id: \.name) { fav in
                                    chip(fav.name, score: fav.score)
                                }
                            }
                            Text("The number is how many more times you've asked for it than against it. Remove a chip to go back to no preference.")
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Favorite exercises")
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

    private func chip(_ name: String, score: Int) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.scaled("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
            Text("+\(score)")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Button { remove(name) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(name) from favorites")
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
        .background(Color.elevated)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }

    /// Clear every case variant of the name, the same fold
    /// `PlanStore.acceptSuggestion(.sinkExercise)` uses, so no stray key
    /// keeps the exercise favoured after the chip is gone.
    private func remove(_ name: String) {
        store.update { m in
            for key in m.exerciseAffinities.keys where key.lowercased() == name.lowercased() {
                m.exerciseAffinities[key] = nil
            }
        }
    }
}

#Preview {
    let suite = "FavoritesEditorSheet.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = MemoryStore(defaults: defaults)
    store.update { $0.exerciseAffinities = ["Goblet Squat": 3, "Romanian Deadlift": 1, "Burpee": -2] }
    return Color.bg.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            FavoritesEditorSheet().environmentObject(store)
        }
        .preferredColorScheme(.dark)
}
