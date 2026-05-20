// DayWorkoutPreviewSheet.swift — preview a planned day's workout with
// per-exercise editing + Start CTA when the day is today.
//
// Build 76: swap is enabled on EVERY day's preview (not just today), and
// the swap sheet is the full ExercisePickerSheet over coach.db's 789
// exercises with search + modality filter — not the narrower
// SubstituteExerciseSheet's curated 5-10 alternatives. Users can edit a
// future-day preview, save the result as a CustomRoutine for reuse, or
// start the workout immediately if it's today.
//
// Swaps mutate local @State `template`. Save-to-library persists as a
// CustomRoutine; Start (today only) consumes the in-flight template via
// SessionStore.createSession. Dismissing the sheet without either action
// discards the local swap — same shape as before, just unlocked for all
// days.

import SwiftUI

struct DayWorkoutPreviewSheet: View {
    let day: DayPlan
    /// Fires after Start to dismiss the host surface (WeekDayEditSheet, etc.)
    /// so the user lands directly in the active LogScreen.
    var onStartSession: (() -> Void)? = nil

    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var customStore: CustomRoutineStore
    @Environment(\.dismiss) private var dismiss

    @State private var template: WorkoutTemplate? = nil
    @State private var swappingExIdx: Int? = nil
    @State private var editingExIdx: Int? = nil
    @State private var addingExercise: Bool = false
    @State private var detailExercise: Exercise? = nil
    @State private var didSave: Bool = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                if let template, !template.exercises.isEmpty {
                    content(template: template)
                } else {
                    emptyState
                }
                if template != nil {
                    VStack { Spacer(); bottomBar }
                }
            }
            .navigationTitle(headerLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .sheet(item: swappingBinding) { wrapped in
                let originalName = template?.exercises[wrapped.index].name ?? "exercise"
                // Pre-filter the picker to "similar exercises" — same muscle
                // bucket AND same movement category as the source. Falls
                // back to no filter if the source exercise can't be
                // resolved (custom routines without coach.db ids).
                let initial = similarFiltersForExercise(at: wrapped.index)
                ExercisePickerSheet(
                    title: "Replace \(originalName)",
                    initialFilters: initial,
                    onPick: { picked in
                        swapExercise(at: wrapped.index, with: picked)
                    }
                )
            }
            .sheet(item: editingBinding) { wrapped in
                let ex = template?.exercises[wrapped.index]
                ExerciseEditorSheet(
                    name: ex?.name ?? "Exercise",
                    sets: ex?.targetSets ?? 3,
                    reps: ex?.targetReps ?? 8,
                    rest: ex?.rest ?? 90,
                    rpe: ex?.rpe,
                    tempo: ex?.tempo,
                    onSave: { sets, reps, rest in
                        updateExercise(at: wrapped.index, sets: sets, reps: reps, rest: rest)
                    }
                )
            }
            .sheet(isPresented: $addingExercise) {
                // No pre-filter — adding is open-ended, user might want a
                // finisher / accessory that isn't related to anything in
                // the current workout.
                ExercisePickerSheet(
                    title: "Add exercise",
                    onPick: { picked in appendExercise(picked) }
                )
            }
            .sheet(item: $detailExercise) { ex in
                ExerciseDetailSheet(exercise: ex)
            }
        }
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            if template == nil { template = day.workoutTemplate }
        }
    }

    // MARK: - Pieces

    private var headerLabel: String {
        isToday ? "Today's workout" : weekdayLabel
    }

    private var weekdayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: day.date)
    }

    /// Build 90: switched from VStack→ScrollView to List so the exercise
    /// rows get drag-to-reorder via .onMove + .editMode(.active) — same
    /// pattern as CustomRoutineEditSheet. listStyle(.insetGrouped) gives
    /// the section-card look that mirrors the previous surface treatment.
    private func content(template: WorkoutTemplate) -> some View {
        List {
            Section {
                header(template: template)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
            }

            Section {
                ForEach(Array(template.exercises.enumerated()), id: \.element.id) { idx, ex in
                    exerciseRow(ex, position: idx + 1)
                        .listRowBackground(Color.surface)
                        .listRowSeparatorTint(Color.lineSoft)
                }
                .onMove(perform: moveExercises)
                addExerciseRow
                    .listRowBackground(Color.surface)
                    .listRowSeparator(.hidden)
            }

            if !isToday {
                Section {
                    Text("Edits stay local — tap Save to library to keep them.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // Spacer section so the last row clears the sticky bottom bar.
            Section {
                Color.clear.frame(height: 90)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    /// SwiftUI .onMove handler — reorder the in-flight template's exercises.
    private func moveExercises(from source: IndexSet, to dest: Int) {
        guard let tmpl = template else { return }
        var reordered = tmpl.exercises
        reordered.move(fromOffsets: source, toOffset: dest)
        template = WorkoutTemplate(
            id: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            exercises: reordered
        )
    }

    private func header(template: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name.uppercased())
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text(summaryLine(template))
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
        }
    }

    private func summaryLine(_ t: WorkoutTemplate) -> String {
        let movements = t.exercises.count == 1 ? "1 movement" : "\(t.exercises.count) movements"
        if let mins = day.durationMinutes {
            return "\(movements) · ~\(mins) min"
        }
        if let mins = day.generatedWorkout?.estimatedMinutes {
            return "\(movements) · ~\(mins) min"
        }
        return movements
    }

    private func exerciseRow(_ ex: ExerciseTemplate, position: Int) -> some View {
        HStack(spacing: 12) {
            // Tap the position+name+meta block to edit sets/reps/rest.
            // The info + swap icons remain dedicated buttons on the right,
            // so the tap zone here is unambiguous.
            Button {
                editingExIdx = position - 1
            } label: {
                HStack(spacing: 12) {
                    Text("\(position)")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .frame(width: 18, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.custom("Inter-Regular", size: 14))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(ex.targetSets) × \(ex.targetReps) · rest \(ex.rest)s")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("preview-edit-\(position)")
            .accessibilityLabel("Edit \(ex.name) sets, reps, and rest")
            Button {
                detailExercise = CoachDatabase.shared
                    .listExercises(search: ex.name)
                    .first { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame }
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show details for \(ex.name)")

            // Build 76: swap is available on every preview, not just today's.
            // Future-day edits persist via the Save to library button at the
            // bottom; same-day edits flow into the active session on Start.
            Button {
                swappingExIdx = position - 1
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap \(ex.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Trailing row inside the exercise card — opens the picker with no
    /// pre-filter and appends the picked exercise to the template.
    private var addExerciseRow: some View {
        Button {
            addingExercise = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .frame(width: 18, alignment: .leading)
                Text("Add exercise")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundStyle(Color.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preview-add-exercise")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 26))
                .foregroundStyle(Color.ink3)
            Text("No workout planned")
                .styled(.body)
                .foregroundStyle(Color.ink2)
            Text("This day doesn't have a lift or mobility session.")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    /// Sticky bottom bar. Save is always present once a template is loaded;
    /// Start workout is added only when the day is today (other days don't
    /// have a session to begin yet — the planner regenerates on the day-of).
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: saveToLibrary) {
                HStack(spacing: 6) {
                    Image(systemName: didSave ? "checkmark" : "tray.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                    Text(didSave ? "Saved" : "Save to library")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                }
                .foregroundStyle(didSave ? Color.ok : Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(didSave)
            .accessibilityIdentifier("preview-save-to-library")

            if isToday {
                Button(action: start) {
                    Text("Start workout")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                        .foregroundStyle(Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Swap binding + mutation

    private var swappingBinding: Binding<PreviewSwapIndex?> {
        Binding(
            get: { swappingExIdx.map(PreviewSwapIndex.init) },
            set: { swappingExIdx = $0?.index }
        )
    }

    /// Parallel binding for the editor sheet. Wraps Int? in an Identifiable
    /// so `.sheet(item:)` can detect changes — same shape as swappingBinding.
    private var editingBinding: Binding<PreviewSwapIndex?> {
        Binding(
            get: { editingExIdx.map(PreviewSwapIndex.init) },
            set: { editingExIdx = $0?.index }
        )
    }

    /// Resolve "similar exercises" filters for the picker when swapping.
    /// Returns ExerciseFilters with bucket + category set from the source
    /// exercise so the picker opens narrowed to true alternatives (same
    /// body area AND same movement pattern style), not just any exercise
    /// in the same bucket. Falls back to whatever it can resolve — if the
    /// exercise isn't in coach.db, returns empty filters.
    private func similarFiltersForExercise(at idx: Int) -> ExerciseFilters {
        var filters = ExerciseFilters()
        guard let tmpl = template, tmpl.exercises.indices.contains(idx) else { return filters }
        let name = tmpl.exercises[idx].name
        guard let dbEx = CoachDatabase.shared
                .listExercises(search: name)
                .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return filters }

        // Muscle bucket — prefer primary, then secondary. First slug that
        // maps to a known bucket wins.
        let muscles = CoachDatabase.shared.musclesForExercise(dbEx.id)
        let orderedMuscles = muscles.sorted { lhs, rhs in
            let rank: (String) -> Int = { r in r == "primary" ? 0 : (r == "secondary" ? 1 : 2) }
            return rank(lhs.role) < rank(rhs.role)
        }
        for entry in orderedMuscles {
            if let bucket = MuscleBucket.bucket(forSlug: entry.slug) {
                filters.bucket = bucket
                break
            }
        }

        // Movement category — first pattern slug that maps to a known
        // category wins. Patterns aren't ranked (no role concept) so any
        // category match is acceptable.
        let patterns = CoachDatabase.shared.patternsForExercise(dbEx.id)
        for slug in patterns {
            if let cat = MovementCategory.category(forSlug: slug) {
                filters.category = cat
                break
            }
        }
        return filters
    }

    /// Append a new exercise to the end of the in-flight template. Uses
    /// the picked exercise's defaults (sets/reps/rest) when available, with
    /// reasonable fallbacks (3×8, 90s rest) when coach.db doesn't have a
    /// prescription stored. Same shape as swapExercise so the saved-to-
    /// library path keeps working.
    private func appendExercise(_ picked: Exercise) {
        guard let tmpl = template else { return }
        let newEx = ExerciseTemplate(
            id: "added-\(UUID().uuidString)",
            name: picked.name,
            type: picked.modality,
            unit: "lbs",
            targetSets: picked.defaultSets ?? 3,
            targetReps: Self.parseRepsLeading(picked.defaultReps) ?? 8,
            rest: Self.parseRestSeconds(picked.defaultRest) ?? 90
        )
        template = WorkoutTemplate(
            id: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            exercises: tmpl.exercises + [newEx]
        )
    }

    /// Update sets/reps/rest on an in-place exercise (no swap). Preserves
    /// id + name + type + rpe + tempo so the saved-to-library + prev-session
    /// lookup paths keep working.
    private func updateExercise(at idx: Int, sets: Int, reps: Int, rest: Int) {
        guard let tmpl = template, tmpl.exercises.indices.contains(idx) else { return }
        let old = tmpl.exercises[idx]
        var newExercises = tmpl.exercises
        newExercises[idx] = ExerciseTemplate(
            id: old.id,
            name: old.name,
            type: old.type,
            unit: old.unit,
            targetSets: sets,
            targetReps: reps,
            rest: rest,
            rpe: old.rpe,
            tempo: old.tempo
        )
        template = WorkoutTemplate(
            id: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            exercises: newExercises
        )
    }

    private func swapExercise(at idx: Int, with picked: Exercise) {
        guard let tmpl = template, tmpl.exercises.indices.contains(idx) else { return }
        let old = tmpl.exercises[idx]
        var newExercises = tmpl.exercises
        newExercises[idx] = ExerciseTemplate(
            id: old.id,
            name: picked.name,
            type: picked.modality,
            unit: old.unit,
            targetSets: picked.defaultSets ?? old.targetSets,
            targetReps: Self.parseRepsLeading(picked.defaultReps) ?? old.targetReps,
            rest: Self.parseRestSeconds(picked.defaultRest) ?? old.rest
        )
        template = WorkoutTemplate(
            id: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            exercises: newExercises
        )
    }

    private func start() {
        guard let template else { return }
        sessionStore.saveActive(sessionStore.createSession(from: template))
        dismiss()
        onStartSession?()
    }

    /// Snapshot the current (possibly swap-mutated) template as a CustomRoutine
    /// in the user's library. Doesn't dismiss — flips the button into a
    /// "Saved" affordance so the user can still hit Start without re-opening
    /// the sheet.
    private func saveToLibrary() {
        guard let template, !template.exercises.isEmpty else { return }
        let routine = CustomRoutine(
            id: UUID().uuidString,
            name: template.name,
            exercises: template.exercises.enumerated().map { idx, ex in
                CustomRoutineExercise(
                    id: UUID().uuidString,
                    exerciseId: lookupExerciseId(forName: ex.name) ?? 0,
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
        didSave = true
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    /// Resolve a coach.db exerciseId by name so the saved CustomRoutine can
    /// later look up substitutes / image / detail. Returns nil when no exact
    /// name match exists (the saved row stays usable as a session template
    /// either way; substitution lookup just degrades).
    private func lookupExerciseId(forName name: String) -> Int? {
        CoachDatabase.shared
            .listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }

    private static func parseRepsLeading(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private static func parseRestSeconds(_ s: String?) -> Int? {
        guard let s = s?.lowercased() else { return nil }
        let digits = s.prefix(while: { $0.isNumber || $0 == "." })
        guard let n = Double(digits) else { return nil }
        if s.contains("min") { return Int(n * 60) }
        return Int(n)
    }
}

/// Identifiable wrapper so `.sheet(item:)` can bind to swappingExIdx.
// Reused by TodayScreen for its inline swap/edit sheet bindings. Was
// private when only this sheet needed it.
struct PreviewSwapIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - DayPlan → WorkoutTemplate bridge

extension DayPlan {
    /// Resolve this day's lift/mobility template the same way TodayScreen
    /// does (generatedWorkout first, routineId fallback). Returns nil for
    /// non-workout days (sport / rest / event) and when neither source is
    /// populated.
    var workoutTemplate: WorkoutTemplate? {
        if let g = generatedWorkout {
            return g.toWorkoutTemplate(id: g.stableTemplateId)
        }
        if let rid = routineId,
           let r = CoachDatabase.shared.listRoutines().first(where: { $0.id == rid }) {
            return r.toWorkoutTemplate(with: CoachDatabase.shared.exercises(forRoutineId: rid))
        }
        return nil
    }
}
