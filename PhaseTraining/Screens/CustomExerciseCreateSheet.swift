// CustomExerciseCreateSheet.swift — make an exercise the catalog lacks.
//
// Opened from ExercisePickerSheet when a search finds nothing (or nothing
// exact). The new exercise lives in user.db only; the generator never sees it.

import SwiftUI

/// When the picker offers "Can't find it? Create ..." under the results.
enum CustomExerciseOffer {
    /// The trimmed query to offer creating, or nil when the row should not show:
    /// empty query, or a result already carries that name (ignoring case).
    static func trailingRowQuery(query: String, results: [Exercise]) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let exact = results.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        return exact ? nil : trimmed
    }
}

struct CustomExerciseCreateSheet: View {
    let initialName: String
    let initialBucket: MuscleBucket?
    let onCreate: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var bucket: MuscleBucket?
    @State private var notes: String = ""
    @State private var error: UserExerciseError?
    @FocusState private var nameFocused: Bool

    init(initialName: String, initialBucket: MuscleBucket?, onCreate: @escaping (Exercise) -> Void) {
        self.initialName = initialName
        self.initialBucket = initialBucket
        self.onCreate = onCreate
        _name = State(initialValue: initialName)
        _bucket = State(initialValue: initialBucket)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nameField
                        bucketChips
                        notesField
                        Text("Custom exercises appear when you search. Your plan is built from the library and will not include them.")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { create() }
                        .foregroundStyle(canCreate ? Color.accent : Color.ink3)
                        .disabled(!canCreate)
                        .accessibilityIdentifier("custom-exercise-create")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear { nameFocused = true }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME").styled(.micro).foregroundStyle(Color.ink3)
            TextField("", text: $name, prompt: Text("Exercise name").foregroundColor(Color.ink3))
                .font(.scaled("Inter-Regular", size: 15))
                .foregroundStyle(Color.ink)
                .padding(12)
                .frame(minHeight: 44)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($nameFocused)
                .submitLabel(.done)
                .onChange(of: name) { _, _ in error = nil }
                .accessibilityIdentifier("custom-exercise-name")
            if let error {
                Text(Self.message(for: error))
                    .font(.monoXS)
                    .foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("custom-exercise-error")
            }
        }
    }

    private var bucketChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MUSCLE GROUP").styled(.micro).foregroundStyle(Color.ink3)
            WrappingFlow(spacing: 8) {
                SelectableChip(label: "None", selected: bucket == nil) { bucket = nil }
                ForEach(MuscleBucket.allCases) { b in
                    SelectableChip(label: b.label, selected: bucket == b) { bucket = b }
                        .accessibilityIdentifier("custom-exercise-bucket-\(b.rawValue)")
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES").styled(.micro).foregroundStyle(Color.ink3)
            TextField("", text: $notes,
                      prompt: Text("Setup, grip, anything to remember (optional)").foregroundColor(Color.ink3),
                      axis: .vertical)
                .lineLimit(3...6)
                .font(.scaled("Inter-Regular", size: 15))
                .foregroundStyle(Color.ink)
                .padding(12)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("custom-exercise-notes")
        }
    }

    static func message(for error: UserExerciseError) -> String {
        switch error {
        case .nameTaken: return "An exercise with that name already exists. Search for it in the library."
        case .emptyName: return "Give the exercise a name."
        case .storeUnavailable: return "Could not save. Try again."
        }
    }

    private func create() {
        guard let store = ExerciseLookupCache.shared.userDB else {
            error = .storeUnavailable
            return
        }
        switch store.createUserExercise(name: name, muscleBucket: bucket, notes: notes) {
        case .success(let ue):
            onCreate(ue.exercise)
            dismiss()
        case .failure(let e):
            error = e
        }
    }
}
