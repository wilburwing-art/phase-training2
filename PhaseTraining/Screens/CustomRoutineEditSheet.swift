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
    /// When set, a "Start workout" action is shown that hands the current
    /// draft back to the caller to run as today's live session. Left nil by
    /// callers (e.g. the Week-day scheduling flow) where "start now" makes no
    /// sense. The draft is NOT auto-saved to the library on start — that's a
    /// deliberate ad-hoc path; the user hits Save separately to keep it.
    let onStartNow: ((CustomRoutine) -> Void)?
    @State private var draft: CustomRoutine
    @State private var showingPicker = false
    @State private var detailExercise: Exercise? = nil
    @State private var showingDeleteConfirm = false
    /// Index into `draft.exercises` whose alternatives the user is browsing
    /// (via the row's `.controls` swap button). nil = sheet closed.
    @State private var swappingExerciseId: String? = nil

    init(routine: CustomRoutine, onStartNow: ((CustomRoutine) -> Void)? = nil) {
        self.original = routine
        self.onStartNow = onStartNow
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
            // `ExerciseSheetName` here wraps the row's stable id string (not
            // a display name) — only `wrapped.id` is read, never `.name`.
            .sheet(item: $swappingExerciseId.exerciseSheetItem) { wrapped in
                // Look the row up by stable id, not array index — the row can
                // be deleted between tapping Swap and this sheet rendering.
                let name = draft.exercises.first(where: { $0.id == wrapped.id })?.name ?? "exercise"
                ExercisePickerSheet(title: "Replace \(name)") { picked in
                    if let i = draft.exercises.firstIndex(where: { $0.id == wrapped.id }) {
                        draft.exercises[i].exerciseId = picked.id
                        draft.exercises[i].name = picked.name
                    }
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
                // Render in superset-grouped order so A1/A2/… members stay
                // adjacent. The ForEach is now keyed off the grouped view —
                // `.onMove`'s render-order indices get translated back to
                // source order in moveExercises so the underlying draft
                // stays group-adjacent.
                let grouped = SupersetGrouping.layout(draft.exercises) { $0.supersetGroup }
                ForEach(Array(grouped.enumerated()), id: \.element.element.id) { _, gi in
                    customExerciseTile(
                        binding(forId: gi.element.id),
                        grouping: gi
                    )
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

            if onStartNow != nil {
                Section {
                    Button {
                        startNow()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text("Start workout")
                        }
                        .foregroundStyle(canSave ? Color.accent : Color.ink3)
                    }
                    .disabled(!canSave)
                    .listRowBackground(Color.surface)
                    .accessibilityIdentifier("custom-routine-start")
                } footer: {
                    Text("Starts this as today's session. It won't be saved to your library unless you tap Save.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
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

    /// HANDOFF §4: row chrome is ExerciseTile with `.handle` leading (the
    /// sheet is always in reorder mode) and `.controls(info, swap)` trailing.
    /// Inline sets/reps/rest TextFields stay below the tile — they're the
    /// distinguishing feature of this sheet and CustomRoutineExercise stores
    /// free-form strings ("8-10", "AMRAP") that the generic
    /// `ExerciseEditorSheet` (Int-only) can't represent without rework.
    ///
    /// `grouping` carries the superset label + first/last hints so the row
    /// can prefix "A1"/"A2"/… to the title and draw the accent left band.
    /// The long-press contextMenu provides the "Add to superset" / "Remove
    /// from superset" affordance that mutates `draft.exercises`.
    @ViewBuilder
    private func customExerciseTile(
        _ exercise: Binding<CustomRoutineExercise>,
        grouping: SupersetGroupedItem<CustomRoutineExercise>
    ) -> some View {
        let displayName: String = {
            if let label = grouping.label { return "\(label)  \(exercise.wrappedValue.name)" }
            return exercise.wrappedValue.name
        }()
        let inSuperset = grouping.groupSize >= 2
        VStack(alignment: .leading, spacing: 8) {
            ExerciseTile(
                vm: .init(
                    leading: .handle,
                    title: displayName,
                    meta: nil,
                    trailing: .controls(
                        onInfo: {
                            detailExercise = CoachDatabase.shared.exercise(id: exercise.wrappedValue.exerciseId)
                        },
                        onSwap: {
                            swappingExerciseId = exercise.wrappedValue.id
                        }
                    )
                ),
                density: .flat
            )
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
        .overlay(alignment: .leading) {
            if inSuperset {
                let topRadius: CGFloat = grouping.isFirstInGroup ? 1.5 : 0
                let bottomRadius: CGFloat = grouping.isLastInGroup ? 1.5 : 0
                UnevenRoundedRectangle(
                    topLeadingRadius: topRadius,
                    bottomLeadingRadius: bottomRadius,
                    bottomTrailingRadius: bottomRadius,
                    topTrailingRadius: topRadius,
                    style: .continuous
                )
                .fill(Color.accent)
                .frame(width: 3)
                .padding(.leading, -8)
                .accessibilityHidden(true)
            }
        }
        .contextMenu {
            if exercise.wrappedValue.supersetGroup == nil {
                Button {
                    addToSuperset(id: exercise.wrappedValue.id)
                } label: {
                    Label("Add to superset", systemImage: "link")
                }
            } else {
                Button(role: .destructive) {
                    removeFromSuperset(id: exercise.wrappedValue.id)
                } label: {
                    Label("Remove from superset", systemImage: "link.badge.minus")
                }
            }
        }
    }

    /// Resolve a binding into `draft.exercises` by row id. Needed because
    /// we render in superset-grouped (not source) order, so iterating
    /// `$draft.exercises` directly would deliver the wrong index.
    private func binding(forId id: String) -> Binding<CustomRoutineExercise> {
        Binding(
            get: { draft.exercises.first(where: { $0.id == id }) ?? draft.exercises[0] },
            set: { newValue in
                if let i = draft.exercises.firstIndex(where: { $0.id == id }) {
                    draft.exercises[i] = newValue
                }
            }
        )
    }

    /// Assign the row to a superset group. Strategy:
    ///   1. If an adjacent neighbor (above or below in source order) is
    ///      already in a group, join that group — the user implicitly meant
    ///      "pair with the row next to me."
    ///   2. Otherwise, mint the next unused integer (max(existing) + 1, or
    ///      1 if no groups exist yet) AND auto-pair with the next un-grouped
    ///      neighbor so we don't leave a solo group of size 1.
    /// Adjacency is preserved because the rendered list re-groups on every
    /// pass via SupersetGrouping.layout.
    private func addToSuperset(id: String) {
        guard let i = draft.exercises.firstIndex(where: { $0.id == id }) else { return }

        if let neighborGroup = adjacentGroup(at: i) {
            draft.exercises[i].supersetGroup = neighborGroup
            return
        }

        let existing = Set(draft.exercises.compactMap(\.supersetGroup))
        let nextGroup = (existing.max() ?? 0) + 1
        draft.exercises[i].supersetGroup = nextGroup

        // Pair with the next un-grouped neighbor so the affordance produces
        // a real superset (≥ 2 members) on first tap. Prefer the row below,
        // fall back to the row above.
        let candidates: [Int] = [i + 1, i - 1].filter { draft.exercises.indices.contains($0) }
        for j in candidates where draft.exercises[j].supersetGroup == nil {
            draft.exercises[j].supersetGroup = nextGroup
            break
        }
    }

    /// Strip the row's group assignment. If only one other row was in that
    /// group (leaving an orphan solo), strip the orphan too — no point
    /// retaining a singleton group, the UI hides its label anyway.
    private func removeFromSuperset(id: String) {
        guard let i = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        guard let group = draft.exercises[i].supersetGroup else { return }
        draft.exercises[i].supersetGroup = nil
        let stillInGroup = draft.exercises.indices.filter { draft.exercises[$0].supersetGroup == group }
        if stillInGroup.count == 1, let solo = stillInGroup.first {
            draft.exercises[solo].supersetGroup = nil
        }
    }

    /// Group id of an adjacent row (above/below) in source order, or nil
    /// if neither neighbor is in a superset. Used by `addToSuperset` to
    /// extend an existing group instead of starting a new singleton.
    private func adjacentGroup(at idx: Int) -> Int? {
        for j in [idx - 1, idx + 1] where draft.exercises.indices.contains(j) {
            if let g = draft.exercises[j].supersetGroup {
                return g
            }
        }
        return nil
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
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    exercise.wrappedValue.reps = nil
                } else if let n = Int(trimmed) {
                    // Pure-integer input — clamp. Free-form strings
                    // ("8-10", "AMRAP", "30s hold") fall through to the else
                    // branch and pass through unchanged.
                    exercise.wrappedValue.reps = String(max(1, min(n, 50)))
                } else {
                    exercise.wrappedValue.reps = trimmed
                }
            }
        )
    }

    private func restBinding(_ exercise: Binding<CustomRoutineExercise>) -> Binding<String> {
        Binding(
            get: { exercise.wrappedValue.rest ?? "" },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    exercise.wrappedValue.rest = nil
                } else if let n = Int(trimmed) {
                    exercise.wrappedValue.rest = String(max(0, min(n, 600)))
                } else {
                    exercise.wrappedValue.rest = trimmed
                }
            }
        )
    }

    /// .onMove fires in RENDER-order indices (the superset-grouped view),
    /// not source order. Re-layout, apply the move on the grouped sequence,
    /// then write back as the new source — this preserves group adjacency
    /// "for free" since adjacent group members stay together through the
    /// move operation.
    private func moveExercises(from source: IndexSet, to dest: Int) {
        let grouped = SupersetGrouping.layout(draft.exercises) { $0.supersetGroup }
        var renderOrder = grouped.map { $0.element }
        renderOrder.move(fromOffsets: source, toOffset: dest)
        draft.exercises = renderOrder
        renumberPositions()
    }

    /// Mirror moveExercises — offsets are in render order, so remove from
    /// the rendered list and write back. Removing the last member of a
    /// superset auto-orphans the partner; clean that up so we don't leave
    /// a labeled singleton.
    private func deleteExercises(at offsets: IndexSet) {
        let grouped = SupersetGrouping.layout(draft.exercises) { $0.supersetGroup }
        var renderOrder = grouped.map { $0.element }
        renderOrder.remove(atOffsets: offsets)

        // Drop singleton supersets left behind by the delete.
        let groupCounts = Dictionary(grouping: renderOrder.compactMap(\.supersetGroup), by: { $0 })
            .mapValues { $0.count }
        for i in renderOrder.indices {
            if let g = renderOrder[i].supersetGroup, (groupCounts[g] ?? 0) < 2 {
                renderOrder[i].supersetGroup = nil
            }
        }

        draft.exercises = renderOrder
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

    /// Hand the current draft to the caller to run as today's live session,
    /// then dismiss. Persisting to the library is intentionally NOT done here
    /// (see `onStartNow`); the caller owns the active-session hand-off and the
    /// in-progress-session guard.
    private func startNow() {
        renumberPositions()
        onStartNow?(draft)
        dismiss()
    }
}
