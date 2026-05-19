// CustomRoutineEditSheet.swift — edit a saved CustomRoutine in place.
//
// Mutates a local draft copy and only commits on Save so the user can back
// out without partial writes leaking to CustomRoutineStore. Supports rename,
// per-exercise sets/reps/rest edits, drag-to-reorder via SwiftUI List, swipe
// to delete, and adding a new exercise through ExercisePickerSheet.
//
// Presented from OverrideTodaySheet's customRow (long-press → Edit, or the
// pencil button). Save persists via CustomRoutineStore.save which is
// upsert-by-id; deletion uses CustomRoutineStore.delete.

import SwiftUI

struct CustomRoutineEditSheet: View {
    @EnvironmentObject private var store: CustomRoutineStore
    @Environment(\.dismiss) private var dismiss

    let original: CustomRoutine
    @State private var draft: CustomRoutine
    @State private var showingPicker = false
    @State private var detailExercise: Exercise? = nil
    @State private var showingDeleteConfirm = false

    init(routine: CustomRoutine) {
        self.original = routine
        _draft = State(initialValue: routine)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                content
            }
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? Color.accent : Color.ink3)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerSheet(title: "Add exercise") { ex in
                    addExercise(ex)
                }
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
            .alert("Delete workout?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    store.delete(original)
                    dismiss()
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("This removes \"\(original.name.isEmpty ? "Untitled workout" : original.name)\" permanently.")
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Content

    private var content: some View {
        List {
            Section {
                TextField("", text: $draft.name,
                          prompt: Text("Workout name").foregroundColor(Color.ink3))
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .listRowBackground(Color.surface)
            } header: {
                Text("NAME")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }

            Section {
                ForEach($draft.exercises) { $exercise in
                    exerciseRow($exercise)
                        .listRowBackground(Color.surface)
                        .listRowSeparatorTint(Color.lineSoft)
                }
                .onMove(perform: moveExercises)
                .onDelete(perform: deleteExercises)

                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .medium))
                        Text("Add exercise")
                            .styled(.body)
                    }
                    .foregroundStyle(Color.accent)
                }
                .listRowBackground(Color.surface)
            } header: {
                Text("EXERCISES (\(draft.exercises.count))")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                        Text("Delete workout")
                    }
                    .foregroundStyle(Color.danger)
                }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: Binding<CustomRoutineExercise>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exercise.wrappedValue.name)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 6)
                Button {
                    detailExercise = CoachDatabase.shared.exercise(id: exercise.wrappedValue.exerciseId)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                fieldBlock("Sets", text: setsBinding(exercise))
                    .frame(maxWidth: .infinity)
                fieldBlock("Reps", text: repsBinding(exercise))
                    .frame(maxWidth: .infinity)
                fieldBlock("Rest", text: restBinding(exercise))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private func fieldBlock(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            TextField("", text: text)
                .font(.monoS)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .keyboardType(label == "Sets" ? .numberPad : .default)
        }
    }

    // MARK: - Bindings + mutations

    private func setsBinding(_ exercise: Binding<CustomRoutineExercise>) -> Binding<String> {
        Binding(
            get: { exercise.wrappedValue.sets.map(String.init) ?? "" },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    exercise.wrappedValue.sets = nil
                } else if let n = Int(trimmed), n > 0 {
                    exercise.wrappedValue.sets = min(n, 99)
                }
            }
        )
    }

    private func repsBinding(_ exercise: Binding<CustomRoutineExercise>) -> Binding<String> {
        Binding(
            get: { exercise.wrappedValue.reps ?? "" },
            set: { exercise.wrappedValue.reps = $0.isEmpty ? nil : $0 }
        )
    }

    private func restBinding(_ exercise: Binding<CustomRoutineExercise>) -> Binding<String> {
        Binding(
            get: { exercise.wrappedValue.rest ?? "" },
            set: { exercise.wrappedValue.rest = $0.isEmpty ? nil : $0 }
        )
    }

    private func moveExercises(from source: IndexSet, to dest: Int) {
        draft.exercises.move(fromOffsets: source, toOffset: dest)
        renumberPositions()
    }

    private func deleteExercises(at offsets: IndexSet) {
        draft.exercises.remove(atOffsets: offsets)
        renumberPositions()
    }

    private func addExercise(_ ex: Exercise) {
        draft.exercises.append(CustomRoutineExercise(
            id: UUID().uuidString,
            exerciseId: ex.id,
            name: ex.name,
            position: draft.exercises.count + 1,
            sets: ex.defaultSets ?? 3,
            reps: ex.defaultReps ?? "8-10",
            rest: ex.defaultRest ?? "90s",
            notes: nil
        ))
    }

    private func renumberPositions() {
        for i in draft.exercises.indices {
            draft.exercises[i].position = i + 1
        }
    }

    private var canSave: Bool {
        !draft.exercises.isEmpty
    }

    private func save() {
        renumberPositions()
        store.save(draft)
        dismiss()
    }
}
