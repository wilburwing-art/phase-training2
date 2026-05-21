// EditSessionSheet.swift — set-level edit for a past saved session.
//
// Fat-fingered weight ("1335" not "135"), wrong reps, forgot to check the
// last set done — these are the failure modes this sheet covers. Identity
// fields (startTime / endTime / templateId) are immutable so the session
// stays the same row in user.db; only per-set fields are editable.
//
// On save: calls SessionStore.updateSession which upserts via UserDatabase.
// On delete: calls deleteSession (with confirmation alert).

import SwiftUI

struct EditSessionSheet: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    /// Working copy of the session under edit. Initialized from the saved
    /// session and mutated locally until the user taps Save.
    @State private var draft: SavedSession
    @State private var showDeleteConfirm = false

    private let originalId: TimeInterval

    init(session: SavedSession) {
        self._draft = State(initialValue: session)
        self.originalId = session.id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(Array(draft.exercises.enumerated()), id: \.offset) { exIdx, ex in
                        exerciseBlock(exIdx: exIdx, ex: ex)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Text("Delete entire session")
                            .styled(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateSession(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete this session?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    store.deleteSession(id: originalId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the session and its sets from history. PRs that depended on it will recompute.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.name)
                .styled(.displayS)
                .foregroundColor(.ink)
            Text(dateLabel(draft.startTime))
                .styled(.monoS)
                .foregroundColor(.ink3)
        }
    }

    // MARK: - Exercise block

    private func exerciseBlock(exIdx: Int, ex: LoggedExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ex.name)
                .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                .foregroundColor(.ink)

            ForEach(Array(ex.sets.enumerated()), id: \.offset) { setIdx, _ in
                setRow(exIdx: exIdx, setIdx: setIdx)
                    .padding(.vertical, 4)
                if setIdx < ex.sets.count - 1 {
                    Rectangle().fill(Color.lineSoft).frame(height: 0.5)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.line, lineWidth: 0.5)
        )
    }

    private func setRow(exIdx: Int, setIdx: Int) -> some View {
        // Bind via path so edits land on the @State draft.
        let setBinding = Binding<LoggedSet>(
            get: { draft.exercises[exIdx].sets[setIdx] },
            set: { draft.exercises[exIdx].sets[setIdx] = $0 }
        )
        let isWarmup = setBinding.wrappedValue.isWarmup
        return HStack(spacing: 8) {
            // Warmup toggle — tap "W" pill flips isWarmup. Filled when set is
            // a warmup; outlined otherwise. Excluding warmups from PR/volume/
            // 1RM math is enforced downstream (UserDatabase, MuscleVolume,
            // StrengthStandards, GeneratorContext).
            Button {
                draft.exercises[exIdx].sets[setIdx].isWarmup.toggle()
            } label: {
                Text("W")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isWarmup ? Color.bg : Color.ink3)
                    .frame(width: 18, height: 14)
                    .background(isWarmup ? Color.ink3 : Color.clear)
                    .overlay(
                        Capsule().stroke(Color.line, lineWidth: 0.5)
                    )
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWarmup ? "Unmark warmup" : "Mark as warmup")

            Text("\(setBinding.wrappedValue.num)")
                .styled(.monoXS)
                .foregroundColor(.ink3)
                .frame(width: 18, alignment: .leading)

            field(text: setBinding.weight, placeholder: "wt", width: 60, keyboard: .decimalPad)
            field(text: setBinding.reps,   placeholder: "reps", width: 50, keyboard: .numbersAndPunctuation)
            field(text: setBinding.rpe,    placeholder: "rpe", width: 44, keyboard: .decimalPad)

            Spacer(minLength: 0)

            Toggle("", isOn: setBinding.done)
                .labelsHidden()
                .scaleEffect(0.85)
        }
        .opacity(isWarmup ? 0.6 : 1.0)
    }

    private func field(text: Binding<String>, placeholder: String, width: CGFloat, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .styled(.monoS)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.line, lineWidth: 0.5)
            )
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }
}
