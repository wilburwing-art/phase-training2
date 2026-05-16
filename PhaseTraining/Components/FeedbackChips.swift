// FeedbackChips.swift — post-workout structured feedback rows.
//
// Three signals captured on CompleteScreen save:
//   1. Difficulty: too easy / right / too hard (mutually exclusive)
//   2. Hurt areas: per-exercise tap-to-mark (multi-select)
//   3. Ran-long toggle
//
// All bound directly from a @Binding FeedbackEntry the caller assembles. The
// caller appends the entry to memory.feedback at save time. Phase 13 coach
// reads the latest week's entries to bias the next plan.

import SwiftUI

struct FeedbackChips: View {
    @Binding var entry: FeedbackEntry
    let exerciseOptions: [(id: String, name: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            difficultyRow
            ranLongRow
            if !exerciseOptions.isEmpty {
                hurtRow
            }
        }
    }

    // MARK: - Difficulty

    private static let difficultyOptions: [(String, String)] = [
        ("too_easy", "Too easy"),
        ("right",    "Right"),
        ("too_hard", "Too hard"),
    ]

    private var difficultyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DIFFICULTY")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 5) {
                ForEach(Self.difficultyOptions, id: \.0) { value, label in
                    chip(label: label, active: entry.difficulty == value) {
                        entry.difficulty = entry.difficulty == value ? nil : value
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Ran-long

    private var ranLongRow: some View {
        Button {
            entry.ranLong.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.ranLong ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(entry.ranLong ? Color.accent : Color.ink3)
                Text("Took longer than planned")
                    .styled(.body)
                    .foregroundStyle(Color.ink2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hurt areas

    private var hurtRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ANYTHING HURT?")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(exerciseOptions, id: \.id) { opt in
                    chip(label: opt.name, active: entry.hurtAreas.contains(opt.id)) {
                        toggle(area: opt.id)
                    }
                }
            }
        }
    }

    private func toggle(area: String) {
        if let i = entry.hurtAreas.firstIndex(of: area) {
            entry.hurtAreas.remove(at: i)
        } else {
            entry.hurtAreas.append(area)
        }
    }

    // MARK: - Chip primitive

    private func chip(label: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .foregroundStyle(active ? Color.accentInk : Color.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(active ? Color.accent : Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(active ? Color.clear : Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Wrapper: View {
        @State var entry = FeedbackEntry(date: Date())
        var body: some View {
            FeedbackChips(
                entry: $entry,
                exerciseOptions: [
                    ("bench",  "Bench"),
                    ("squat",  "Squat"),
                    ("row",    "Row"),
                    ("ohp",    "OHP"),
                ]
            )
            .padding()
            .background(Color.bg)
            .preferredColorScheme(.dark)
        }
    }
    return Wrapper()
}
