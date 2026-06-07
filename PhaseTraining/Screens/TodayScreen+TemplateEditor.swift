// TodayScreen+TemplateEditor.swift — the build-93 inline editor surface.
//
// Pure extraction from TodayScreen.swift (architecture item 12): the inline
// exercise card + tile, the immutable `editableTemplate` rebuild mutations,
// and the save-to-library pill. All state stays declared on TodayScreen; this
// extension reads/writes the same `editableTemplate` / `didModify` /
// `didSaveToLibrary` @State the body's `onChange(of: template)` guard
// protects — nothing here re-derives that guard. Members the main file's
// body or sheet callbacks invoke are internal; tile/pill internals consumed
// only within this file stay private.

import SwiftUI

extension TodayScreen {

    // MARK: - Inline editable exercise card (build 93)

    /// Today's exercise list as a directly-editable card: tap a row to
    /// open the action sheet (adjust, swap, inspect, remove). The Add
    /// Exercise row appends to the end. All mutations flow through
    /// `editableTemplate` so Start consumes the edited shape. The List is
    /// height-bounded so it doesn't scroll independently inside the page's
    /// outer ScrollView.
    func inlineExerciseCard(_ tmpl: WorkoutTemplate) -> some View {
        // Height: ~88pt per ExerciseTile (.presentation density min) + ~56pt
        // add-row + ~8pt list padding. Slight overshoot is fine; rows just
        // sit at their intrinsic size.
        let listHeight = CGFloat(tmpl.exercises.count) * 88 + 56 + 8

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY'S EXERCISES")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text("\(tmpl.exercises.count)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List {
                Section {
                    ForEach(Array(tmpl.exercises.enumerated()), id: \.element.id) { idx, ex in
                        todayExerciseTile(ex, position: idx + 1)
                            .listRowBackground(Color.surface)
                            .listRowSeparatorTint(Color.lineSoft)
                            .listRowInsets(EdgeInsets())
                    }
                    inlineAddExerciseRow
                        .listRowBackground(Color.surface)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: listHeight)
        }
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// HANDOFF §4a: presentation-density composite tile. Leading slot is a
    /// 56pt photo + 28pt muscle chip; trailing collapses to a single ••• that
    /// (along with whole-row tap) opens ExerciseActionSheet. The inline
    /// info/swap buttons are gone — those actions live inside the sheet.
    private func todayExerciseTile(_ ex: ExerciseTemplate, position: Int) -> some View {
        let prevEx = previous?.exercises.first(where: { $0.id == ex.id })
        let prevWeightText = prevEx?.sets.first?.weight ?? ""
        // Build 103 — deterministic progression suggestion. Show the next
        // bump alongside the prior weight so the user sees the progression
        // story without depending on the LLM coach. Falls back to the bare
        // prev-weight when we don't have enough signal (no prior set, no
        // reps logged).
        let weightSegment = progressionSegment(ex: ex, prevEx: prevEx, prevWeightText: prevWeightText)
        let bucket = bucketForExercise(named: ex.name) ?? .chest
        let photoURL = thumbnailURLForExercise(named: ex.name)
        let exerciseID = ExerciseLookupCache.shared.exerciseID(forName: ex.name)

        return ExerciseTile(
            vm: .init(
                leading: .composite(exerciseID: exerciseID, photoURL: photoURL, group: bucket, side: bucket.naturalSide),
                title: ex.name,
                meta: "\(ex.targetSets) sets · \(ex.targetReps) reps · \(weightSegment)",
                trailing: .overflow(onTap: { actionSheetExIdx = position - 1 }),
                onTap: { actionSheetExIdx = position - 1 }
            ),
            density: .presentation
        )
        .accessibilityIdentifier("today-edit-\(position)")
    }

    /// Compose the rightmost segment of the tile meta line. Showing both
    /// the previous and the suggested weight lets the user see "+5" as
    /// progression in motion, not just a fresh number.
    private func progressionSegment(ex: ExerciseTemplate, prevEx: LoggedExercise?, prevWeightText: String) -> String {
        guard !prevWeightText.isEmpty else { return "—" }
        let unit = ex.unit
        // Shared extraction (heaviest set that met target reps) so the Today
        // tile and the Log pill never disagree on the suggested number.
        guard let prevEx,
              let s = ProgressionSuggestion.suggest(
                prevSets: prevEx.sets,
                targetReps: ex.targetReps,
                exerciseName: ex.name,
                unit: unit
              ) else {
            return "\(prevWeightText) \(unit)"
        }
        if s.delta == 0 {
            return "\(s.suggestedWeightString) \(unit) · hold"
        }
        return "\(s.suggestedWeightString) \(unit) · \(s.label)"
    }

    /// Resolve the primary muscle bucket for an exercise by name. Routes
    /// through `ExerciseLookupCache` so repeated renders of the same row
    /// (or a Today list that re-renders on every state change) hit coach.db
    /// once per unique name per session.
    private func bucketForExercise(named name: String) -> MuscleBucket? {
        ExerciseLookupCache.shared.bucket(forName: name)
    }

    /// Resolve a thumbnail URL for the composite leading slot. Same cache as
    /// the bucket lookup so both come from a single coach.db roundtrip.
    private func thumbnailURLForExercise(named name: String) -> String? {
        ExerciseLookupCache.shared.thumbnailURL(forName: name)
    }

    /// Move the exercise at `idx` by `offset` (-1 for up, +1 for down) inside
    /// the editable template. Wired to the action sheet's Move up / Move down
    /// rows, which the sheet only shows when the index isn't at the boundary.
    func moveExercise(at idx: Int, by offset: Int) {
        guard let tmpl = editableTemplate else { return }
        let target = idx + offset
        guard tmpl.exercises.indices.contains(idx),
              tmpl.exercises.indices.contains(target) else { return }
        var reordered = tmpl.exercises
        reordered.swapAt(idx, target)
        editableTemplate = WorkoutTemplate(
            id: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            exercises: reordered
        )
        didModify = true
        didSaveToLibrary = false
    }

    /// Remove the exercise at `idx` from the editable template. Wired to the
    /// action sheet's destructive "Delete from workout" row.
    func deleteExercise(at idx: Int) {
        guard let tmpl = editableTemplate, tmpl.exercises.indices.contains(idx) else { return }
        var remaining = tmpl.exercises
        remaining.remove(at: idx)
        editableTemplate = WorkoutTemplate(id: tmpl.id, name: tmpl.name, category: tmpl.category, exercises: remaining)
        didModify = true
        didSaveToLibrary = false
    }

    private var inlineAddExerciseRow: some View {
        Button {
            addingExercise = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .frame(width: 14)
                Text("Add exercise")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-add-exercise")
    }

    var saveToLibraryPill: some View {
        Button(action: saveCurrentTemplateToLibrary) {
            HStack(spacing: 6) {
                Image(systemName: didSaveToLibrary ? "checkmark" : "tray.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text(didSaveToLibrary ? "Saved to library" : "Save changes to library")
                    .styled(.micro)
                Spacer(minLength: 0)
                if !didSaveToLibrary {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(didSaveToLibrary ? Color.ok : Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(didSaveToLibrary)
        .accessibilityIdentifier("today-save-library")
    }

    // MARK: - Mutators + helpers

    func updateExercise(at idx: Int, sets: Int, reps: Int, rest: Int) {
        guard let tmpl = editableTemplate, tmpl.exercises.indices.contains(idx) else { return }
        let old = tmpl.exercises[idx]
        var newExercises = tmpl.exercises
        newExercises[idx] = ExerciseTemplate(
            id: old.id, name: old.name, type: old.type, unit: old.unit,
            targetSets: sets, targetReps: reps, rest: rest,
            rpe: old.rpe, tempo: old.tempo
        )
        editableTemplate = WorkoutTemplate(id: tmpl.id, name: tmpl.name, category: tmpl.category, exercises: newExercises)
        didModify = true
        didSaveToLibrary = false
    }

    func swapExercise(at idx: Int, with picked: Exercise) {
        guard let tmpl = editableTemplate, tmpl.exercises.indices.contains(idx) else { return }
        let old = tmpl.exercises[idx]
        var newExercises = tmpl.exercises
        newExercises[idx] = ExerciseTemplate(
            id: old.id, name: picked.name, type: picked.modality, unit: old.unit,
            targetSets: picked.defaultSets ?? old.targetSets,
            targetReps: parseRepsLeading(picked.defaultReps) ?? old.targetReps,
            rest: parseRestSeconds(picked.defaultRest) ?? old.rest
        )
        editableTemplate = WorkoutTemplate(id: tmpl.id, name: tmpl.name, category: tmpl.category, exercises: newExercises)
        didModify = true
        didSaveToLibrary = false
    }

    func appendExercise(_ picked: Exercise) {
        guard let tmpl = editableTemplate else { return }
        let newEx = ExerciseTemplate(
            id: "added-\(UUID().uuidString)",
            name: picked.name,
            type: picked.modality,
            unit: "lbs",
            targetSets: picked.defaultSets ?? 3,
            targetReps: parseRepsLeading(picked.defaultReps) ?? 8,
            rest: parseRestSeconds(picked.defaultRest) ?? 90
        )
        editableTemplate = WorkoutTemplate(id: tmpl.id, name: tmpl.name, category: tmpl.category, exercises: tmpl.exercises + [newEx])
        didModify = true
        didSaveToLibrary = false
    }

    /// Compute "similar exercises" filters for the swap picker. Index → name
    /// resolution lives here; the bucket + category lookup is the shared
    /// ExerciseFilters.similar(toExerciseNamed:) all three swap surfaces use.
    func similarFiltersForExercise(at idx: Int) -> ExerciseFilters {
        guard let tmpl = editableTemplate, tmpl.exercises.indices.contains(idx) else { return ExerciseFilters() }
        return .similar(toExerciseNamed: tmpl.exercises[idx].name)
    }

    private func saveCurrentTemplateToLibrary() {
        guard let tmpl = editableTemplate, !tmpl.exercises.isEmpty else { return }
        let routine = CustomRoutine(
            id: UUID().uuidString,
            name: tmpl.name,
            exercises: tmpl.exercises.enumerated().map { idx, ex in
                CustomRoutineExercise(
                    id: UUID().uuidString,
                    exerciseId: CoachDatabase.shared
                        .listExercises(search: ex.name)
                        .first(where: { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame })?.id ?? 0,
                    name: ex.name,
                    position: idx + 1,
                    sets: ex.targetSets,
                    reps: String(ex.targetReps),
                    rest: "\(ex.rest)s",
                    notes: nil
                )
            },
            createdAt: Date()
        )
        customStore.save(routine)
        // Save success: the edits are persisted, so clear the dirty flag —
        // the template onChange guard protects *unsaved* edits only, and the
        // next mutation re-arms both flags. didSaveToLibrary keeps the pill
        // on-screen in its "Saved to library" confirmation state.
        didSaveToLibrary = true
        didModify = false
    }
}
