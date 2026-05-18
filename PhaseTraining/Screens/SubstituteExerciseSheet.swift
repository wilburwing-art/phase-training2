// SubstituteExerciseSheet.swift — alternative-exercise picker.
//
// Reads CoachDatabase.substitutes(forExerciseId:) — 1,730 pre-curated pairs
// in the bundled coach.db tagged by context (home_friendly, lower_intensity,
// equipment_swap, etc.). Surfaces them as a ranked list of cards. Tap one →
// `onPick(Exercise)` → presenter wires it back into the session.
//
// Reached from LogScreen rows (mid-workout swap), via either the visible
// arrow.left.arrow.right button or the long-press contextMenu. The caller
// is responsible for the actual mutation; this view is pure UI.

import SwiftUI

struct SubstituteExerciseSheet: View {
    let originalName: String
    let substitutes: [ExerciseSubstitute]
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detailExercise: Exercise? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                if substitutes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header
                            ForEach(substitutes) { sub in
                                row(sub)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
        }
        .presentationBackground(Color.bg)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FOR")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text(originalName)
                .styled(.displayS)
                .foregroundStyle(Color.ink)
            Text("\(substitutes.count) similar")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
    }

    private func row(_ sub: ExerciseSubstitute) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                onPick(sub.exercise)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(sub.exercise.name)
                            .styled(.body)
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Text("\(sub.matchPercent)%")
                            .font(.custom("JetBrainsMono-SemiBold", size: 12))
                            .foregroundStyle(matchColor(sub.matchPercent))
                    }
                    if !sub.exercise.modalityLabel.isEmpty || !sub.exercise.difficultyLabel.isEmpty {
                        Text(metaLine(sub.exercise))
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    if !sub.contextLabels.isEmpty {
                        contextBadges(sub.contextLabels)
                    }
                    if let notes = sub.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundStyle(Color.ink2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    detailExercise = sub.exercise
                } label: {
                    Label("Show details", systemImage: "info.circle")
                }
                Button {
                    onPick(sub.exercise)
                    dismiss()
                } label: {
                    Label("Swap to this", systemImage: "arrow.left.arrow.right")
                }
            }

            Button {
                detailExercise = sub.exercise
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 36, height: 36)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show details for \(sub.exercise.name)")
        }
    }

    private func metaLine(_ ex: Exercise) -> String {
        let parts = [ex.modalityLabel, ex.difficultyLabel].filter { $0 != "—" }
        return parts.joined(separator: " · ")
    }

    private func contextBadges(_ labels: [String]) -> some View {
        WrappingFlow(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func matchColor(_ pct: Int) -> Color {
        switch pct {
        case 80...: return Color.ok
        case 60..<80: return Color.accent
        default: return Color.ink3
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Color.ink3)
            Text("No similar exercises")
                .styled(.body)
                .foregroundStyle(Color.ink)
            Text("Nothing in the library substitutes well for \(originalName).")
                .styled(.body)
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
