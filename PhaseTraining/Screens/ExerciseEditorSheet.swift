// ExerciseEditorSheet.swift — small modal for editing sets/reps/rest on a
// single exercise in a workout. Build 89 closes the editable-preview loop:
// you can now swap, add, and adjust the prescription per exercise from the
// same surface. Drag-to-reorder is a follow-up.
//
// Sheet takes initial values + an onSave callback. Locks bounds to keep
// the user out of nonsense territory (negative rest, 50-set ladders).

import SwiftUI

struct ExerciseEditorSheet: View {
    let name: String
    /// RPE / tempo passed through unchanged — surfaced as a hint row but
    /// not editable here. Power users can swap the exercise if they want
    /// different prescription depth.
    let rpe: String?
    let tempo: String?

    @State private var sets: Int
    @State private var reps: Int
    @State private var rest: Int

    let onSave: (Int, Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        name: String,
        sets: Int,
        reps: Int,
        rest: Int,
        rpe: String? = nil,
        tempo: String? = nil,
        onSave: @escaping (Int, Int, Int) -> Void
    ) {
        self.name = name
        self.rpe = rpe
        self.tempo = tempo
        self._sets = State(initialValue: sets)
        self._reps = State(initialValue: reps)
        self._rest = State(initialValue: rest)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    if rpe != nil || tempo != nil {
                        hintRow
                    }
                    stepperCard(
                        title: "SETS",
                        value: sets,
                        suffix: "",
                        decrement: { if sets > 1 { sets -= 1 } },
                        increment: { if sets < 10 { sets += 1 } },
                        canDecrement: sets > 1,
                        canIncrement: sets < 10
                    )
                    stepperCard(
                        title: "REPS",
                        value: reps,
                        suffix: "",
                        decrement: { if reps > 1 { reps -= 1 } },
                        increment: { if reps < 50 { reps += 1 } },
                        canDecrement: reps > 1,
                        canIncrement: reps < 50
                    )
                    stepperCard(
                        title: "REST",
                        value: rest,
                        suffix: "s",
                        decrement: { if rest >= 15 { rest -= 15 } },
                        increment: { if rest <= 285 { rest += 15 } },
                        canDecrement: rest >= 15,
                        canIncrement: rest <= 285
                    )
                    Spacer()
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
            }
        }
        .presentationBackground(Color.bg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var hintRow: some View {
        HStack(spacing: 14) {
            if let rpe {
                hintChip(label: "RPE", value: rpe)
            }
            if let tempo {
                hintChip(label: "TEMPO", value: tempo)
            }
            Spacer()
        }
    }

    private func hintChip(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text(value)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func stepperCard(
        title: String,
        value: Int,
        suffix: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void,
        canDecrement: Bool,
        canIncrement: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .frame(width: 60, alignment: .leading)

            Spacer()

            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canDecrement ? Color.accent : Color.line)
            }
            .buttonStyle(.plain)
            .disabled(!canDecrement)

            Text("\(value)\(suffix)")
                .font(.custom("SpaceGrotesk-SemiBold", size: 22))
                .foregroundStyle(Color.ink)
                .frame(minWidth: 70)
                .multilineTextAlignment(.center)

            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canIncrement ? Color.accent : Color.line)
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var saveButton: some View {
        Button {
            onSave(sets, reps, rest)
            dismiss()
        } label: {
            Text("Save")
                .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                .foregroundStyle(Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise-editor-save")
    }
}
