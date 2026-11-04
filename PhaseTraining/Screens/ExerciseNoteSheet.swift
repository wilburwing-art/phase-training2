// ExerciseNoteSheet.swift — one note per exercise per session.
//
// Opened from the exercise's context menu or its note line in Log. The note
// saves with the session (session_exercises.note) and shows next time as
// "Last time: …".

import SwiftUI

struct ExerciseNoteTarget: Identifiable {
    let index: Int
    var id: Int { index }
}

struct ExerciseNoteSheet: View {
    let exerciseName: String
    let lastNote: String?
    @Binding var note: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    if let lastNote, !lastNote.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LAST TIME")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                            Text(lastNote)
                                .styled(.body)
                                .foregroundStyle(Color.ink2)
                        }
                    }
                    TextField("Seat height, grip, how it felt", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.scaled("Inter-Regular", size: 15))
                        .foregroundStyle(Color.ink)
                        .padding(12)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .focused($focused)
                        .accessibilityIdentifier("exercise-note-field")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }
}
