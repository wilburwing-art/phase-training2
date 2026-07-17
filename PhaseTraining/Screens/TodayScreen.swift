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
    // editableTemplate / didModify / didSaveToLibrary / addingExercise /
    // actionSheetExIdx are internal (not private) so the editor extension in
    // TodayScreen+TemplateEditor.swift can read/write the same state the
    // body's onChange(of: template) guard protects.
    @State var editableTemplate: WorkoutTemplate?
    @State var didModify: Bool = false
    @State private var swappingExIdx: Int?
    @State private var editingExIdx: Int?
    @State var addingExercise: Bool = false
    @State private var inlineDetailExercise: Exercise?
    /// Build 102 — composite-tile migration. Tap on a Today exercise row now
    /// opens an action sheet instead of going straight to the editor; this
    /// drives that sheet. See ExerciseActionSheet + HANDOFF-tile-system.md §4a.
    @State var actionSheetExIdx: Int?
    /// Build 102 — action sheet's "Exercise history" row presents
    /// HistoryScreen filtered to a single exercise name.
    @State private var historyFilterExerciseName: String?
    @State var didSaveToLibrary: Bool = false
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
    /// Which constraint blocked the consolidation — appended to the no-op
    /// alert so the user sees why the week couldn't absorb the miss.
    @State private var consolidationDecline: PlanStore.ConsolidationDecline?

    // Derived read-only state (todayPlan, effectiveKind, template, hero copy,
    // …) lives in TodayScreen+Derived.swift; the inline editor surface +
    // template mutations live in TodayScreen+TemplateEditor.swift.

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

                        RepelicanPhaseCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                        SeasonPhaseBadge(style: .full, surface: "today")
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
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
            Text(consolidationNoopMessage)
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
        // consolidateWeekDetailed reports which constraint blocked a no-op
        // (weekly cap, <2 future lift days, unrecoverable focus). Don't
        // pretend it worked — tell the user the miss was just dropped and why.
        let decline = planStore.consolidateWeekDetailed(memory: memoryStore.memory)
        planStore.dismissMissed(date: day.date, asDropped: true)
        if let decline {
            consolidationDecline = decline
            showConsolidationNoop = true
        }
    }

    /// No-op alert body: the base sentence plus the constraint that blocked
    /// consolidation, so "couldn't absorb" isn't left unexplained.
    private var consolidationNoopMessage: String {
        let reason: String
        switch consolidationDecline {
        case .weeklyCapMet:
            reason = "the weekly cap is already met"
        case .notEnoughLiftDays:
            reason = "not enough lift days left this week"
        case .unrecoverableFocus:
            reason = "the remaining workouts couldn't be merged"
        case nil:
            return "The week couldn't absorb the missed work — the workout was skipped instead."
        }
        return "The week couldn't absorb the missed work — \(reason). The workout was skipped instead."
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
