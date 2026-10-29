// MoodAfterLine.swift — the one optional "Mood after?" line.
//
// Shared by the Complete screen (right after a workout) and Edit session
// (rating it later, which is the only way a watch-saved workout gets a
// mood). Plain text options with no pills, so skipping it costs nothing.
// Values are the fixed vocabulary `SavedSession.mood` documents and the
// coach context reads verbatim.

import SwiftUI

struct MoodAfterLine: View {
    @Binding var mood: String?

    static let options: [(value: String, label: String)] = [
        ("worse", "Worse"), ("same", "Same"), ("better", "Better"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            Text("Mood after?")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
            Spacer(minLength: 8)
            ForEach(Self.options, id: \.value) { option in
                let active = mood == option.value
                Button {
                    mood = active ? nil : option.value
                } label: {
                    Text(option.label)
                        .font(.monoXS)
                        .foregroundStyle(active ? Color.accent : Color.ink2)
                        .underline(active)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mood-\(option.value)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }
}
