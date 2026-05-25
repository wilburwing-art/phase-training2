// TodayScreen.swift — Phase 10 successor to StartScreen.
//
// Renders today's hero based on PlanStore.plan?.today(). DayKind drives the
// treatment:
//   - .lift / .mobility → workout-style hero (date, last-session card,
//     exercise preview from coach.db routine, "Start workout" CTA)
//   - .sport            → sport-day card; no exercise list. "Log session"
//     CTA opens SportLogSheet; once logged, the hero subtitle swaps to a
//     "45 min · hard" recap and the CTA hides. Tapping the recap re-opens
//     the sheet for edits.
//   - .rest             → rest card; encourages mobility
//   - .event            → event card
//   - no plan / pre-onboard → falls back to upper-1 hardcoded template
//     (so cold launches before onboarding completes still work; same path
//     UI tests use)
//
// Active sessions always win — if `store.active` exists we render its
// template regardless of today's plan, so the user can resume a workout
// even on a day the planner now thinks should be rest.

import SwiftUI

struct TodayScreen: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var planStore: PlanStore
    @EnvironmentObject var memoryStore: MemoryStore
    @EnvironmentObject var tabSelection: TabSelectionStore
    @EnvironmentObject var customStore: CustomRoutineStore
    @EnvironmentObject var sportLogStore: SportLogStore

    let onStart: () -> Void

    // Build 93 — inline editor on Today. The preview-sheet round trip
    // (tap card → open sheet → edit → close) felt indirect, so swap /
    // tap-to-edit / add / reorder all happen directly on Today's exercise
    // list now. `editableTemplate` is the in-flight, mutation-applied copy
    // of `template`; `didModify` flips true on any edit so the
    // "Save to library" pill knows when to surface.
    @State private var editableTemplate: WorkoutTemplate?
    @State private var didModify: Bool = false
    @State private var swappingExIdx: Int?
    @State private var editingExIdx: Int?
    @State private var addingExercise: Bool = false
    @State private var inlineDetailExercise: Exercise?
    /// Build 102 — composite-tile migration. Tap on a Today exercise row now
    /// opens an action sheet instead of going straight to the editor; this
    /// drives that sheet. See ExerciseActionSheet + HANDOFF-tile-system.md §4a.
    @State private var actionSheetExIdx: Int?
    /// Build 102 — action sheet's "Exercise history" row presents
    /// HistoryScreen filtered to a single exercise name.
    @State private var historyFilterExerciseName: String?
    @State private var didSaveToLibrary: Bool = false
    /// Build 99 — pre-workout soreness check-in moved from an inline
    /// expand/collapse card to a header-adjacent pill that opens a modal sheet.
    @State private var showSorenessSheet: Bool = false
    @State private var showingSportLog: Bool = false

    // MARK: - Derived state

    private var todayPlan: DayPlan? { planStore.plan?.today() }

    /// Effective DayKind for rendering. Active session forces a workout
    /// hero. Otherwise, follow today's plan; default to lift if no plan.
    private var effectiveKind: DayKind {
        if store.active != nil { return .lift }
        return todayPlan?.kind ?? .lift
    }

    /// Template for the workout hero. nil on sport/rest/event days when
    /// there's no active session.
    private var template: WorkoutTemplate? {
        if let active = store.active, !active.exercises.isEmpty {
            return WorkoutTemplate(
                id: active.templateId,
                name: active.name,
                category: active.category,
                exercises: active.exercises.map { ex in
                    ExerciseTemplate(
                        id: ex.id, name: ex.name, type: ex.type, unit: ex.unit,
                        targetSets: ex.targetSets, targetReps: ex.targetReps, rest: ex.rest
                    )
                }
            )
        }
        // Generated workout (the new default for lift / mobility days).
        // Uses GeneratedWorkout.stableTemplateId — same exercises → same id,
        // so SessionStore.getPreviousSession finds last week's same-shape
        // workout and pulls weight + reps forward into the autofill column.
        if let _ = todayPlan, let workout = todayPlan?.generatedWorkout {
            return workout.toWorkoutTemplate(id: workout.stableTemplateId)
        }
        // Day-override picked a specific routine (custom workout or library pick).
        if let routineId = todayPlan?.routineId {
            return loadTemplate(routineId: routineId)
        }
        // No plan yet → upper-1 fallback. Guarantees TodayScreen always has
        // a usable template before onboarding runs.
        if planStore.plan == nil {
            return WorkoutTemplate.upper1
        }
        return nil
    }

    private func loadTemplate(routineId: Int) -> WorkoutTemplate? {
        let routines = CoachDatabase.shared.listRoutines()
        guard let r = routines.first(where: { $0.id == routineId }) else { return nil }
        let exercises = CoachDatabase.shared.exercises(forRoutineId: routineId)
        return r.toWorkoutTemplate(with: exercises)
    }

    private var totalSets: Int {
        template?.exercises.reduce(0) { $0 + $1.targetSets } ?? 0
    }

    private var previous: SavedSession? {
        guard let template else { return nil }
        return store.getPreviousSession(templateId: template.id)
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var heroTitle: String {
        switch effectiveKind {
        case .lift:
            return template?.name.replacingOccurrences(of: " Day ", with: "\nDay ")
                ?? (todayPlan?.title ?? "Train")
        case .sport:
            return todayPlan?.sport.map { "\($0.name)\nday" } ?? "Sport day"
        case .rest:
            return "Rest day"
        case .event:
            return "Event day"
        }
    }

    /// True when the current plan's last day is within 2 days (or already past).
    /// Drives the "Plan next week" pill.
    private var planEndingSoon: Bool {
        guard let last = planStore.plan?.days.last?.date else { return false }
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        let lastDay = cal.startOfDay(for: last)
        let daysLeft = cal.dateComponents([.day], from: now, to: lastDay).day ?? 0
        return daysLeft <= 2
    }

    /// Phase 13e: coach-written observation when present, otherwise the static
    /// Phase-11 rules. Picks first matching source.
    private var insightCopy: String? {
        let cal = Calendar.current
        if let coach = memoryStore.memory.coachInsights.last(where: {
            $0.surface == "today" && cal.isDate($0.date, inSameDayAs: Date())
        }) {
            return coach.body
        }
        guard let plan = planStore.plan else { return nil }
        if let day = plan.today() {
            if day.protected {
                return "Today is protected. I won't shuffle it without asking."
            }
            if let mins = day.durationMinutes {
                return "Today's session is shortened to \(mins) min."
            }
        }
        return nil
    }

    private var heroSubtitle: String {
        switch effectiveKind {
        case .lift:
            return template?.category ?? ""
        case .sport:
            if let log = todaySportLog {
                return "Logged · \(log.durationMinutes) min · \(log.intensity.label.lowercased())"
            }
            return todayPlan?.sport != nil ? "Log it when you're done." : "Sport day."
        case .rest:
            return "Sleep, food, walk. The work is in recovery."
        case .event:
            return todayPlan?.title ?? "Today's event."
        }
    }

    /// Today's most recent sport log, if any. Drives the subtitle swap
    /// and the "edit log" sheet pre-fill. Only meaningful on .sport days
    /// but read defensively (anyone could tap a stale link).
    private var todaySportLog: SportLogEntry? {
        sportLogStore.entry(on: Date())
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                TabHeader(
                    eyebrow: dateLabel,
                    eyebrowTrailing: tabHeaderTrailing,
                    title: heroTitle,
                    subtitle: heroSubtitle,
                    caption: heroCaption
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sorenessCheckInPill
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        TodayRecoveryCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        if planEndingSoon {
                            planNextWeekPill
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                        }
                        if effectiveKind.isWorkout {
                            lastSessionCard
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                            if let tmpl = editableTemplate {
                                inlineExerciseCard(tmpl)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                                if didModify {
                                    saveToLibraryPill
                                        .padding(.horizontal, 20)
                                        .padding(.top, 10)
                                }
                            }
                        }
                        Spacer().frame(height: 160)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Bottom CTA — single primary action only. Build 91 dropped
            // the secondary History button; history is accessed elsewhere
            // (TBD — orphaned in code for now).
            VStack(spacing: 10) {
                primaryButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
        .sheet(item: editingBinding) { wrapped in
            let ex = editableTemplate?.exercises[wrapped.index]
            ExerciseEditorSheet(
                name: ex?.name ?? "Exercise",
                sets: ex?.targetSets ?? 3,
                reps: ex?.targetReps ?? 8,
                rest: ex?.rest ?? 90,
                rpe: ex?.rpe,
                tempo: ex?.tempo,
                onSave: { sets, reps, rest in
                    updateExercise(at: wrapped.index, sets: sets, reps: reps, rest: rest)
                },
                onInfo: {
                    if let ex {
                        inlineDetailExercise = ExerciseLookupCache.shared.exercise(forName: ex.name)
                    }
                },
                onSwap: { swappingExIdx = wrapped.index }
            )
        }
        .sheet(item: swappingBinding) { wrapped in
            let originalName = editableTemplate?.exercises[wrapped.index].name ?? "exercise"
            let initial = similarFiltersForExercise(at: wrapped.index)
            ExercisePickerSheet(
                title: "Replace \(originalName)",
                initialFilters: initial,
                onPick: { picked in swapExercise(at: wrapped.index, with: picked) }
            )
        }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerSheet(
                title: "Add exercise",
                onPick: { picked in appendExercise(picked) }
            )
        }
        .sheet(item: $inlineDetailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(item: actionSheetBinding) { wrapped in
            let exerciseName = editableTemplate?.exercises[wrapped.index].name ?? "Exercise"
            ExerciseActionSheet(
                exerciseName: exerciseName,
                onEdit: { editingExIdx = wrapped.index },
                onShowDetails: {
                    inlineDetailExercise = ExerciseLookupCache.shared.exercise(forName: exerciseName)
                },
                onShowHistory: { historyFilterExerciseName = exerciseName },
                onShowReplace: { swappingExIdx = wrapped.index },
                onDelete: { deleteExercise(at: wrapped.index) }
            )
        }
        .sheet(item: filteredHistoryBinding) { wrapped in
            HistoryScreen(initialExerciseFilter: wrapped.name)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSorenessSheet) {
            SorenessCheckInSheet(onDone: {})
        }
        .sheet(isPresented: $showingSportLog) {
            // Guard inside the sheet builder rather than gating the modifier —
            // SwiftUI evaluates the builder only when isPresented goes true,
            // and the CTA wouldn't be visible without a sport in the first
            // place. The `?? Date()` is defensive: if the plan vanished
            // between tap and sheet build, we still render against today.
            if let sport = todayPlan?.sport {
                SportLogSheet(
                    date: Calendar.current.startOfDay(for: Date()),
                    sport: sport,
                    existing: todaySportLog,
                    onSave: { mins, intensity, note in
                        if var existing = todaySportLog {
                            existing.durationMinutes = mins
                            existing.intensity = intensity
                            existing.note = note
                            sportLogStore.update(existing)
                        } else {
                            sportLogStore.log(
                                sport: sport,
                                on: Date(),
                                durationMinutes: mins,
                                intensity: intensity,
                                note: note
                            )
                        }
                    }
                )
            }
        }
        .onAppear {
            if editableTemplate == nil { editableTemplate = template }
        }
    }

    /// Discoverable affordance for the pre-workout body check. Always visible
    /// on Today (regardless of day kind) so rest-day soreness can still be
    /// logged. When today's entry exists, the pill shows a "LOGGED" tick to
    /// signal it's already captured — same behavior the inline card had.
    private var sorenessCheckInPill: some View {
        let logged = todaysSorenessLogged
        return Button { showSorenessSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: logged ? "checkmark.circle.fill" : "figure.cooldown")
                    .font(.system(size: 13, weight: .semibold))
                Text(logged ? "SORENESS · LOGGED" : "HOW SORE ARE YOU TODAY?")
                    .styled(.micro)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(logged ? Color.accent : Color.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(logged ? Color.accentBorder : Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-soreness-checkin")
    }

    /// True when memory has a soreness entry stamped today.
    private var todaysSorenessLogged: Bool {
        let cal = Calendar.current
        return memoryStore.memory.soreness.contains { cal.isDate($0.date, inSameDayAs: Date()) }
    }

    private var planNextWeekPill: some View {
        Button { tabSelection.showWeeklyCheckIn = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("PLAN NEXT WEEK")
                    .styled(.micro)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentWash)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-plan-next-week")
    }

    /// Trailing eyebrow text for the unified TabHeader — exercise/set summary
    /// when there's a workout, otherwise the day's kind label.
    private var tabHeaderTrailing: String {
        if effectiveKind.isWorkout, let template {
            return "~\(template.exercises.count) EX · \(totalSets) SETS"
        }
        return effectiveKind.label
    }

    /// Single source of truth for the small caption rendered under the hero
    /// subtitle. Coach insight wins if present; otherwise we fall back to
    /// the planner's static generatedReason.
    private var heroCaption: String? {
        insightCopy ?? todayPlan?.generatedReason
    }

    // MARK: - Last session card

    private var lastSessionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("LAST SESSION")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text(daysAgoShort)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Text(lastSessionDetail)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var daysAgoShort: String {
        guard let prev = previous else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: prev.startTime, to: Date()).day ?? 0
        return "\(days)d ago"
    }

    private var lastSessionDetail: String {
        guard let prev = previous else { return "First time — weights will be empty" }
        let stats = computeStats(prev)
        return "\(formatDuration(prev.duration)) · \(stats.doneSets) sets · avg rpe \(stats.avgRpe)"
    }

    // MARK: - Inline editable exercise card (build 93)

    /// Today's exercise list as a directly-editable card: tap a row to
    /// adjust sets/reps/rest, tap swap to replace, tap info to inspect,
    /// drag the trailing handle to reorder. The Add Exercise row appends
    /// to the end. All mutations flow through `editableTemplate` so Start
    /// consumes the edited shape.
    ///
    /// Reorder uses `List` + `.onMove` + `editMode: .active` (same pattern
    /// as `DayWorkoutPreviewSheet`). The List is height-bounded so it
    /// doesn't scroll independently inside the page's outer ScrollView.
    /// Per-row `.draggable`/`.dropDestination` was tried first and broke
    /// after the first reorder — see `swiftui-drag-reorder-custom-styled`.
    private func inlineExerciseCard(_ tmpl: WorkoutTemplate) -> some View {
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
                    .onMove(perform: moveInlineExercise)
                    inlineAddExerciseRow
                        .listRowBackground(Color.surface)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
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
        let weightSegment = prevWeightText.isEmpty ? "—" : "\(prevWeightText) \(ex.unit)"
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

    /// Remove the exercise at `idx` from the editable template. Wired to the
    /// action sheet's destructive "Delete from workout" row.
    private func deleteExercise(at idx: Int) {
        guard let tmpl = editableTemplate, tmpl.exercises.indices.contains(idx) else { return }
        var remaining = tmpl.exercises
        remaining.remove(at: idx)
        editableTemplate = WorkoutTemplate(id: tmpl.id, name: tmpl.name, category: tmpl.category, exercises: remaining)
        didModify = true
        didSaveToLibrary = false
    }

    private var actionSheetBinding: Binding<PreviewSwapIndex?> {
        Binding(
            get: { actionSheetExIdx.map(PreviewSwapIndex.init) },
            set: { actionSheetExIdx = $0?.index }
        )
    }

    /// Binding for the filtered-history sheet. Wraps the optional exercise
    /// name in an Identifiable wrapper so `.sheet(item:)` can drive the
    /// HistoryScreen filtered to that exercise.
    private var filteredHistoryBinding: Binding<NamedExercise?> {
        Binding(
            get: { historyFilterExerciseName.map(NamedExercise.init) },
            set: { historyFilterExerciseName = $0?.name }
        )
    }

    /// SwiftUI .onMove handler — reorder editableTemplate's exercises in
    /// place. The closure's `dest` is already in original-array coordinates.
    private func moveInlineExercise(from source: IndexSet, to dest: Int) {
        guard let tmpl = editableTemplate else { return }
        var reordered = tmpl.exercises
        reordered.move(fromOffsets: source, toOffset: dest)
        editableTemplate = WorkoutTemplate(
            id: tmpl.id,
            name: tmpl.name,
            category: tmpl.category,
            exercises: reordered
        )
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

    private var saveToLibraryPill: some View {
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

    private var swappingBinding: Binding<PreviewSwapIndex?> {
        Binding(
            get: { swappingExIdx.map(PreviewSwapIndex.init) },
            set: { swappingExIdx = $0?.index }
        )
    }

    private var editingBinding: Binding<PreviewSwapIndex?> {
        Binding(
            get: { editingExIdx.map(PreviewSwapIndex.init) },
            set: { editingExIdx = $0?.index }
        )
    }

    private func updateExercise(at idx: Int, sets: Int, reps: Int, rest: Int) {
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

    private func swapExercise(at idx: Int, with picked: Exercise) {
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

    private func appendExercise(_ picked: Exercise) {
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

    /// Compute "similar exercises" filters for the swap picker — same
    /// muscle bucket AND same movement category as the source. Mirrors the
    /// helper on DayWorkoutPreviewSheet so both surfaces filter the same way.
    private func similarFiltersForExercise(at idx: Int) -> ExerciseFilters {
        var filters = ExerciseFilters()
        guard let tmpl = editableTemplate, tmpl.exercises.indices.contains(idx) else { return filters }
        let name = tmpl.exercises[idx].name
        guard let dbEx = CoachDatabase.shared.listExercises(search: name)
                .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return filters }
        let muscles = CoachDatabase.shared.musclesForExercise(dbEx.id).sorted { lhs, rhs in
            let rank: (String) -> Int = { r in r == "primary" ? 0 : (r == "secondary" ? 1 : 2) }
            return rank(lhs.role) < rank(rhs.role)
        }
        for entry in muscles {
            if let bucket = MuscleBucket.bucket(forSlug: entry.slug) { filters.bucket = bucket; break }
        }
        for slug in CoachDatabase.shared.patternsForExercise(dbEx.id) {
            if let cat = MovementCategory.category(forSlug: slug) { filters.category = cat; break }
        }
        return filters
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
        didSaveToLibrary = true
    }

    private func parseRepsLeading(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private func parseRestSeconds(_ s: String?) -> Int? {
        guard let s else { return nil }
        let lower = s.lowercased()
        let digits = lower.prefix(while: { $0.isNumber })
        guard let n = Int(digits) else { return nil }
        if lower.contains("min") { return n * 60 }
        return n
    }

    // MARK: - Buttons

    @ViewBuilder
    private var primaryButton: some View {
        switch effectiveKind {
        case .lift:
            workoutStartButton
        case .sport:
            // Only offer the log CTA when the day actually has a sport;
            // a bare sport day with no sport (rare — stale override) has
            // nothing to log against.
            if todayPlan?.sport != nil {
                sportLogButton
            } else {
                EmptyView()
            }
        case .rest, .event:
            // No primary action — the user sees today's status, no session to start.
            EmptyView()
        }
    }

    private var sportLogButton: some View {
        // Same visual treatment as the workout-start CTA — keeps the bottom
        // bar consistent across day kinds. Label flips to "Edit log" when
        // a log already exists for today so a re-tap clearly means edit.
        Button(action: { showingSportLog = true }) {
            HStack(spacing: 6) {
                Image(systemName: todaySportLog == nil ? "checkmark.circle" : "pencil.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(todaySportLog == nil ? "Log session" : "Edit log")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
            }
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-log-sport")
    }

    private var workoutStartButton: some View {
        Button(action: startWorkout) {
            HStack(spacing: 6) {
                Text(store.active == nil ? "Start workout" : "Resume workout")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(template == nil)
    }

    private func startWorkout() {
        // Use the inline-edited template if the user touched it; otherwise
        // fall back to the original computed template. Either way the
        // active session is created from what the user actually sees.
        if store.active == nil {
            if let tmpl = editableTemplate {
                store.saveActive(store.createSession(from: tmpl))
            } else if let tmpl = template {
                store.saveActive(store.createSession(from: tmpl))
            }
        }
        onStart()
    }

    // MARK: - Helpers

    private func computeStats(_ session: SavedSession) -> (doneSets: Int, avgRpe: String) {
        var doneSets = 0
        var totalRpe: Double = 0
        var rpeCount = 0
        for ex in session.exercises {
            for s in ex.sets where s.done {
                doneSets += 1
                if !s.rpe.isEmpty, let v = Double(s.rpe), !v.isNaN {
                    totalRpe += v
                    rpeCount += 1
                }
            }
        }
        let avgRpe = rpeCount > 0 ? String(format: "%.1f", totalRpe / Double(rpeCount)) : "—"
        return (doneSets, avgRpe)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview

#Preview("Lift day with plan") {
    let suite = "TodayScreen.preview.lift"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let plan = PlanStore(defaults: defaults)
    plan.setPlan(.sample())
    return TodayScreen(onStart: {})
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(plan)
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
        .environmentObject(CustomRoutineStore(defaults: defaults))
        .environmentObject(SportLogStore(defaults: defaults))
}

#Preview("No plan (fallback)") {
    let suite = "TodayScreen.preview.fallback"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return TodayScreen(onStart: {})
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(TabSelectionStore())
        .environmentObject(CustomRoutineStore(defaults: defaults))
        .environmentObject(SportLogStore(defaults: defaults))
}

/// Identifiable wrapper so `.sheet(item:)` can bind to an optional exercise
/// name string — drives the filtered HistoryScreen presentation.
private struct NamedExercise: Identifiable {
    let name: String
    var id: String { name }
}
