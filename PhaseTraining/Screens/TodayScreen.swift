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
    // Coach gate — same pair CoachBubble reads. The "personalized by coach"
    // badge must not render for users without consent/Pro, even when a stale
    // refinedByLLMAt stamp survives in the plan from before consent was
    // revoked (nothing clears the stamp on revocation).
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false
    @AppStorage(CoachEntitlement.proKey) private var proEntitled: Bool = false

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
    /// Drives the read-only explanation sheet for the "personalized by coach"
    /// badge — shown only when today's generated workout was LLM-refined
    /// (`refinedByLLMAt` stamped). No accept / reject: the refinement is
    /// already applied; this is pure transparency.
    @State private var showCoachPolishedSheet: Bool = false
    @State private var showConsolidationNoop: Bool = false

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
                    eyebrowTrailing: phaseEyebrow,
                    title: heroTitle,
                    subtitle: headerSubtitle,
                    caption: heroCaption
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // PR 8 — missed-workout banner. Renders the most
                        // recent pending miss (planned day passed with
                        // no logged session). Once the user acts, the
                        // next pending miss (if any) takes its place.
                        if let pending = currentPendingMiss {
                            MissedWorkoutBanner(
                                missedDay: pending,
                                proposedDiff: planStore.proposeMissedReshuffle(missedDate: pending.date),
                                onAccept: { acceptMissedReshuffle(for: pending) },
                                onDismiss: { dismissMissed(for: pending) },
                                onConsolidate: planStore.shouldOfferConsolidation(missedDate: pending.date)
                                    ? { consolidateForMiss(for: pending) } : nil
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            // No wrapper accessibilityIdentifier here: a parent
                            // id leaks to every child Button (XCUITest then sees
                            // Skip/Consolidate both reporting the wrapper id, not
                            // their own). The banner's own buttons carry
                            // missed-banner-* ids; use missed-banner-header for
                            // presence. (xcuitest-swiftui-gotchas #1.)
                        }

                        SeasonPhaseBadge(style: .full, surface: "today")
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        sorenessCheckInPill
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
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
                            if isCoachPolished {
                                coachPolishedBadge
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                            }
                            if let tmpl = editableTemplate {
                                inlineExerciseCard(tmpl)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 14)
                                // didModify = unsaved edits ("Save changes"),
                                // didSaveToLibrary = just saved ("Saved" tick).
                                // Save success clears didModify, so the pill
                                // needs both to keep showing the confirmation.
                                if didModify || didSaveToLibrary {
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
        .sheet(item: $editingExIdx.exerciseSheetItem) { wrapped in
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
        .sheet(item: $swappingExIdx.exerciseSheetItem) { wrapped in
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
        .sheet(item: $actionSheetExIdx.exerciseSheetItem) { wrapped in
            let exerciseName = editableTemplate?.exercises[wrapped.index].name ?? "Exercise"
            let count = editableTemplate?.exercises.count ?? 0
            ExerciseActionSheet(
                exerciseName: exerciseName,
                onEdit: { editingExIdx = wrapped.index },
                onMoveUp: wrapped.index > 0 ? { moveExercise(at: wrapped.index, by: -1) } : nil,
                onMoveDown: wrapped.index < count - 1 ? { moveExercise(at: wrapped.index, by: 1) } : nil,
                onShowDetails: {
                    inlineDetailExercise = ExerciseLookupCache.shared.exercise(forName: exerciseName)
                },
                onShowHistory: { historyFilterExerciseName = exerciseName },
                onShowReplace: { swappingExIdx = wrapped.index },
                onDelete: { deleteExercise(at: wrapped.index) }
            )
        }
        .sheet(item: $historyFilterExerciseName.exerciseSheetItem) { wrapped in
            HistoryScreen(initialExerciseFilter: wrapped.name)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSorenessSheet) {
            SorenessCheckInSheet(onDone: {})
        }
        // Attached at screen level, NOT on the banner — by the time the
        // no-op flag flips, dismissMissed has already removed the banner
        // from the hierarchy, and an alert on a removed view never shows.
        .alert("Nothing to consolidate", isPresented: $showConsolidationNoop) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The week couldn't absorb the missed work — the workout was skipped instead.")
        }
        .sheet(isPresented: $showCoachPolishedSheet) {
            CoachPolishedExplanationSheet(
                refinedAt: todayPlan?.generatedWorkout?.refinedByLLMAt,
                provenance: todayPlan?.generatedReason
            )
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
        .onChange(of: template) { _, newTemplate in
            // The underlying plan can change while Today stays on-screen — the
            // plan regenerates, a day override is scheduled, or an active
            // session appears/clears. Re-sync the editable copy so Start
            // consumes the current shape, unless the user hand-edited it (in
            // which case keep their edits rather than clobber them).
            if !didModify { editableTemplate = newTemplate }
        }
    }

    // MARK: - PR 8 — Missed-workout banner glue

    /// The single pending missed workout we surface in the banner.
    /// Picks the most recent unresolved miss; once the user acts on
    /// it (Accept / Skip), the next pending miss surfaces.
    private var currentPendingMiss: DayPlan? {
        planStore.pendingMissedWorkouts().last  // last = most recent date
    }

    private func acceptMissedReshuffle(for day: DayPlan) {
        if let diff = planStore.proposeMissedReshuffle(missedDate: day.date) {
            planStore.applyMissedReshuffle(diff, missedDate: day.date)
        } else {
            // Drop-rule fired or no valid target → log as dropped so we
            // don't re-banner the same date.
            planStore.dismissMissed(date: day.date, asDropped: true)
        }
    }

    private func dismissMissed(for day: DayPlan) {
        planStore.dismissMissed(date: day.date, asDropped: false)
    }

    /// D3 — consolidate the remaining week onto fewer lift days (offered when
    /// reshuffle found no clean slot), then clear the miss so it stops
    /// bannering.
    private func consolidateForMiss(for day: DayPlan) {
        // consolidateWeek returns false on every no-op path (weekly cap,
        // <2 future lift days, unrecoverable focus). Don't pretend it
        // worked — tell the user the miss was just dropped.
        let applied = planStore.consolidateWeek(memory: memoryStore.memory)
        planStore.dismissMissed(date: day.date, asDropped: true)
        if !applied { showConsolidationNoop = true }
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

    /// Trailing eyebrow text — the periodization phase. This is the app's
    /// namesake context (off-/pre-/in-season, event prep, maintenance), which
    /// previously surfaced only in Profile and the season editor. Appends
    /// DELOAD when this week's tone is Recovery — the only honest deload
    /// signal available (it's user-picked on the Week tab; there's no
    /// auto-scheduled mesocycle deload to read).
    private var phaseEyebrow: String {
        var s = memoryStore.memory.seasonForPlanner.compactLabel.uppercased()
        if planStore.overrides.weekTone == .recovery { s += " · DELOAD" }
        return s
    }

    /// Days until the event-prep peak, when a peak date is set and the
    /// athlete is in event prep. nil otherwise (nothing to count down to).
    private var daysToPeak: Int? {
        guard memoryStore.memory.seasonForPlanner == .eventPrep,
              let peak = memoryStore.memory.peakDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: peak)).day ?? 0
        return days >= 0 ? days : nil
    }

    /// Subtitle line. The EX·SETS summary moved here from the eyebrow (which
    /// now carries the phase); non-workout days keep their kind-specific copy.
    /// An event-prep peak countdown appends on any day kind.
    private var headerSubtitle: String? {
        var parts: [String] = []
        if effectiveKind.isWorkout, let template {
            parts.append("\(template.exercises.count) ex · \(totalSets) sets")
        } else if !heroSubtitle.isEmpty {
            parts.append(heroSubtitle)
        }
        if let d = daysToPeak {
            parts.append(d == 0 ? "peak today" : "peak in \(d)d")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// Single source of truth for the small caption rendered under the hero
    /// subtitle. Coach insight wins if present; otherwise we fall back to
    /// the planner's static generatedReason.
    private var heroCaption: String? {
        insightCopy ?? todayPlan?.generatedReason
    }

    /// True when today's generated workout was LLM-polished in the background
    /// by the build-98 refinement pass. Drives the "personalized by coach"
    /// pill — purely informational; the change is already applied (refinement
    /// is the visible default for consented users, not a coach proposal).
    /// Entitlement-gated: a stamp left over from a consented refinement (or a
    /// pre-revocation manual swap via applyWorkoutDiff) must not surface coach
    /// UI once the coach is off.
    private var isCoachPolished: Bool {
        CoachEntitlement.unlocked(consent: consentGranted, pro: proEntitled)
            && todayPlan?.generatedWorkout?.refinedByLLMAt != nil
    }

    /// Non-blocking transparency pill: signals that the background LLM
    /// refinement reshaped today's exercise picks / intensity. Tapping opens
    /// a read-only explanation sheet — no Apply / Reject, since the change
    /// is already in the plan.
    private var coachPolishedBadge: some View {
        Button { showCoachPolishedSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("PERSONALIZED BY COACH")
                    .styled(.micro)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-coach-polished-badge")
        .accessibilityLabel("Personalized by coach. Tap for details.")
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
    /// open the action sheet (adjust, swap, inspect, remove). The Add
    /// Exercise row appends to the end. All mutations flow through
    /// `editableTemplate` so Start consumes the edited shape. The List is
    /// height-bounded so it doesn't scroll independently inside the page's
    /// outer ScrollView.
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
    private func moveExercise(at idx: Int, by offset: Int) {
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
    private func deleteExercise(at idx: Int) {
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

    /// Compute "similar exercises" filters for the swap picker. Index → name
    /// resolution lives here; the bucket + category lookup is the shared
    /// ExerciseFilters.similar(toExerciseNamed:) all three swap surfaces use.
    private func similarFiltersForExercise(at idx: Int) -> ExerciseFilters {
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
        .accessibilityIdentifier("today-start-workout")
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

// MARK: - Coach-polished transparency sheet
//
// Read-only explanation for the "personalized by coach" pill on Today (and
// reusable on any surface that wants to expose the build-98 background
// refinement). Deliberately not a diff card: refinement is the visible
// default for consented users (per the build-98 design in
// `PlanStore+LLMRefinement.swift`), not a proposal awaiting Apply. The audit
// flagged a lack of transparency, not a missing consent gate — this is the
// transparency answer without re-introducing a friction prompt.
private struct CoachPolishedExplanationSheet: View {
    let refinedAt: Date?
    let provenance: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accent)
                Text("Personalized by your coach")
                    .font(.system(size: 18, weight: .bold))
            }

            Text("Your coach reshaped today's workout based on recent sessions, soreness, and goals. The shape of your week — push / pull / legs and rest days — is unchanged. Only this day's exercise picks, sets, RPE, or weights are different from the deterministic default.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if let provenance, !provenance.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REASON")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(provenance)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink)
                }
            }

            if let refinedAt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UPDATED")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(refinedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink)
                }
            }

            Text("To opt out of background polishing, turn the coach off in Profile.")
                .font(.system(size: 12))
                .foregroundStyle(Color.ink3)
                .padding(.top, 4)

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accent)
                    .foregroundStyle(Color.accentInk)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-polished-explanation-done")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg.ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
