// WorkoutExerciseRow.swift — shared exercise-slot row used by Today + DayWorkoutPreviewSheet.
//
// One row per ExerciseTemplate inside a workout. Tap the text block to edit
// sets/reps/rest. Info button → exercise detail. Swap button → picker.
//
// Caller assembles the meta line (set ×rep · prev · rest, or any subset).
// Container handles reorder via List + .onMove — drag affordance is the
// List's built-in trailing handle in editMode.

import SwiftUI

struct WorkoutExerciseRow: View {
    let name: String
    let position: Int
    let metaText: String
    let onTap: () -> Void
    let onInfo: () -> Void
    let onSwap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text("\(position)")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .frame(width: 18, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.custom("Inter-Regular", size: 14))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(metaText)
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(name) sets, reps, and rest")

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show details for \(name)")

            Button(action: onSwap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap \(name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
