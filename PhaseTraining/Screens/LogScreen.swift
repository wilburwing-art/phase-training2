// LogScreen.swift — The core training log screen.
//
// Ports `handoff/proto/log.jsx` (behavior) + `handoff/hd-training-log.jsx` (visuals)
// to SwiftUI. Sticky header with elapsed timer + progress bar, scrollable exercise
// list with inline number inputs, set checkboxes, inline rest-timer card with
// pulse animation, "+ Add Set", active-row indicator, auto-save on every change.
//
// State model (mirrors prototype):
//   - `session: ActiveSession` — full session, mutated in place, persisted via store.saveActive
//     on every change.
//   - `rest: RestTimerState` — rest timer (view-local, not persisted). Initial
//     duration is `ex.rest`; +15 extends the countdown; Skip clears. See
//     RestTimerState.swift.
//
// Timers:
//   - Elapsed time and rest countdown both tick via `TimelineView(.periodic(...))`.
//   - TimelineViews wrap ONLY the time-display text (not TextFields), so re-renders
//     don't disrupt user typing.
//
// Split layout (Tier 3): RestTimerState.swift (rest state + inline rest UI),
// LogExerciseBlock.swift (per-exercise block), LogSetRow.swift (set row + cells),
// LogScreenHelpers.swift (pure logic + formatters). All are extensions of this
// struct, so state stays here and bindings never cross a view boundary.

import SwiftUI
import UIKit

struct LogScreen: View {
    // T2-1 / T2-3 (declared here: LogSetRow.swift is an extension and
    // cannot hold stored properties). Column widths were hard pixel frames sized for the fixed
    // 13.5pt mono font. Now that the type scales with Dynamic Type these have
    // to scale with it or the log clips at the first larger setting.
    // `.footnote` matches what `.monoS` / `.body` scale with.
    @ScaledMetric(relativeTo: .footnote) var setNumWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) var labelWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .footnote) var effortWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .caption2) var warmupPillWidth: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) var warmupPillHeight: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) var warmupPillFont: CGFloat = 9

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var memoryStore: MemoryStore
    let onFinish: () -> Void
    var onCancel: (() -> Void)? = nil

    @State var session: ActiveSession = Self.placeholder
    @State private var didLoad = false
    @State private var showCancelConfirm = false
    /// Finish commits irreversibly — CompleteScreen saves on .onAppear
    /// ("Finish IS the save"). The button sits directly beside "Log all" in the
    /// sticky header, so a mis-tap permanently wrote a half-logged workout into
    /// user.db, streaks and planner history. Cancel already confirms; the far
    /// more destructive action did not.
    @State private var showFinishConfirm = false
    /// Reached with no active session — an anomalous state, not a normal entry.
    /// LogScreen used to paper over it by creating a hardcoded "upper-1"
    /// session, silently ignoring today's plan, generated workout and any day
    /// override. TodayTab only routes here when `store.active != nil`, and
    /// TodayScreen owns session creation precisely so it can build from today's
    /// routine instead of upper-1 (TodayTab.swift:40) — so the fallback was
    /// vestigial and could only ever fabricate the wrong workout.
    @State private var noSession = false

    /// Sets the user marked done. Finishing with some still open is normal
    /// (dropped a set, ran out of time) — only confirm when it looks accidental.
    private var incompleteSetCount: Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { !$0.done }.count }
    }

    /// Rest timer state (view-local, intentionally non-persistent per spec).
    @State var rest = RestTimerState()

    /// Long-press driven "swap exercise" sheet. nil = closed. Keys by index
    /// into session.exercises so we can mutate it on pick.
    @State var swappingExIdx: Int? = nil
    /// Read-only Exercise detail (name → coach.db lookup). Opens via row tap
    /// (mid-workout how-to) or contextMenu "Show details".
    @State var detailExercise: Exercise? = nil
    /// Mid-workout "Add exercise" picker. true = sheet open.
    @State private var addingExercise: Bool = false

    /// Exercise indices (into `session.exercises`) where the user tapped the
    /// "BW" label to reveal a weight input for a bodyweight movement — the
    /// rare weighted-bird-dog / weight-vest case. Bodyweight exercises hide
    /// the weight column by default so reps-only sets need zero weight taps.
    @State var weightEntryExercises: Set<Int> = []

    /// Debounce for downstream weight propagation, keyed by "exIdx-setIdx".
    /// Without it propagateWeight fired on every keystroke, briefly pushing
    /// partial values (1, 13, 135) into later sets while the user was still typing.
    @State var weightPropagateTasks: [String: Task<Void, Never>] = [:]
    @State var weightPropagateOld: [String: String] = [:]

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if noSession {
                noSessionState
            } else if didLoad {
                content
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: session) { _, newValue in
            // Auto-save on every mutation (per README.md:286).
            store.saveActive(newValue)
        }
        .alert("Discard workout?", isPresented: $showCancelConfirm) {
            Button("Discard", role: .destructive) { onCancel?() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your in-progress sets won't be saved.")
        }
        .alert("Finish workout?", isPresented: $showFinishConfirm) {
            Button("Finish") { onFinish() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(incompleteSetCount == 1
                 ? "One set isn't logged yet. Finishing saves the workout as it stands."
                 : "\(incompleteSetCount) sets aren't logged yet. Finishing saves the workout as it stands.")
        }
        .sheet(item: $swappingExIdx.exerciseSheetItem) { wrapped in
            let original = session.exercises[wrapped.index]
            // Build 99 — switched from SubstituteExerciseSheet (sparse
            // curated table — many exercises had zero substitutes, so the
            // list was empty) to ExercisePickerSheet pre-filtered to
            // "similar exercises": same muscle bucket + same movement
            // category as the source. Same fix the preview sheet shipped
            // in build 78 + Today inline in build 94. User can clear
            // either filter to broaden if they want anything in the library.
            ExercisePickerSheet(
                title: "Replace \(original.name)",
                initialFilters: .similar(toExerciseNamed: original.name),
                onPick: { picked in
                    swapExercise(at: wrapped.index, with: picked)
                }
            )
        }
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(isPresented: $addingExercise) {
            // Mid-workout add. No initial filter — user came to the log
            // wanting to insert something specific that wasn't in the plan,
            // so we open the picker wide and let them search.
            ExercisePickerSheet(
                title: "Add exercise",
                onPick: { picked in
                    appendExerciseFromPicker(picked)
                }
            )
        }
    }

    /// In-session substitution. Replace the exercise's name + display type
    /// in-place; keep already-logged sets intact (the user did the work,
    /// just under a different label).
    ///
    /// `prevSets` and `unit` MUST be re-derived, not carried over: they belong
    /// to the exercise being replaced. Leaving prevSets made the progression
    /// pill prescribe a load computed from a different lift ("SUGGESTED · 190 lb
    /// · +5" for a movement the user has never performed) and the per-row "Last"
    /// column show the old exercise's numbers.
    private func swapExercise(at idx: Int, with picked: Exercise) {
        guard session.exercises.indices.contains(idx) else { return }
        let originalName = session.exercises[idx].name
        session.exercises[idx].name = picked.name
        if let modality = picked.modality, !modality.isEmpty {
            session.exercises[idx].type = picked.modalityLabel
        }
        let category = CoachDatabase.shared.equipmentCategory(forExerciseIds: [picked.id])[picked.id]
        session.exercises[idx].unit = LoggedExercise.unit(for: category)
        session.exercises[idx].prevSets = store.previousSets(forExerciseNamed: picked.name)
        // Remember the swap so the generator favors the chosen exercise (and,
        // after repeated swaps-away, demotes the original) in future plans.
        memoryStore.recordSwap(out: originalName, in: picked.name)
    }

    // MARK: - Body content

    /// Re-ordered + labeled view of `session.exercises` for rendering.
    /// Members of the same superset render adjacently with an "A1/A2/…"
    /// prefix on the title and a 3pt accent left band spanning the group.
    /// Solo (un-supersetted) rows pass through unchanged.
    private var groupedExercises: [SupersetGroupedItem<LoggedExercise>] {
        SupersetGrouping.layout(session.exercises) { $0.supersetGroup }
    }

    private var content: some View {
        VStack(spacing: 0) {
            stickyHeader
            ScrollView {
                VStack(spacing: 0) {
                    titleBlock
                    Rectangle()
                        .fill(Color.line)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    let grouped = groupedExercises
                    ForEach(Array(grouped.enumerated()), id: \.offset) { i, gi in
                        exerciseBlock(exIdx: gi.originalIndex, grouping: gi)
                        if i < grouped.count - 1 {
                            Rectangle()
                                .fill(Color.line)
                                .frame(height: 0.5)
                                .padding(.horizontal, 20)
                        }
                    }

                    // Mid-workout "Add exercise" — opens the full picker so
                    // the user can insert anything from coach.db without
                    // leaving the log to edit the plan.
                    Rectangle()
                        .fill(Color.line)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                    Button { addingExercise = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add exercise")
                                .styled(.body)
                        }
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-add-exercise")

                    // Bottom clearance for the system tab bar. Without this
                    // the last few exercise rows render UNDER the tab bar
                    // (snapshot_ui showed tab bar at y=791-874 occluding
                    // log-set-check-2-N for the 3rd-of-5 exercise in the
                    // supersets demo seed). Tab bar visible height is
                    // 49pt + home-indicator inset ~34pt = ~83pt. 120pt
                    // gives an extra safety margin so reorder-handles and
                    // contextMenus don't get shadowed either.
                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Sticky header

    private var stickyHeader: some View {
        let stats = store.stats(for: session)
        let totalSets = max(stats.totalSets, 1)
        let progress = CGFloat(stats.doneSets) / CGFloat(totalSets)
        let anyUndone = stats.doneSets < stats.totalSets

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if onCancel != nil {
                    Button {
                        showCancelConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 28, height: 28)
                            .background(Color.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-cancel")
                }

                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.ink3)

                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    Text(Self.fmtElapsed(ctx.date.timeIntervalSince(session.startTime)))
                        .styled(.monoM)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                }

                Spacer()

                // Whole-workout shortcut: log every remaining set in one tap
                // (rack-first users). Secondary styling keeps Finish the
                // primary CTA. Hidden once everything's logged.
                if anyUndone {
                    Button(action: logAllSetsAllExercises) {
                        Text("Log all")
                            .font(.custom("Inter-Regular", size: 13).weight(.bold))
                            .tracking(-0.01 * 13)
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.accentBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-all-workout")
                }

                Button(action: {
                    // Fully-logged workout finishes straight through; only an
                    // apparently-accidental tap (open sets remaining) confirms.
                    if incompleteSetCount > 0 { showFinishConfirm = true } else { onFinish() }
                }) {
                    Text("Finish")
                        .font(.custom("Inter-Regular", size: 13).weight(.bold))
                        .tracking(-0.01 * 13)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log-finish")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.lineSoft)
                    Rectangle()
                        .fill(Color.accent)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .frame(height: 3)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
        }
        .background(Color.bg)
    }

    // MARK: - Title block (in scrolled body, like proto)

    private var titleBlock: some View {
        let stats = store.stats(for: session)
        return VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .styled(.displayM)
                .foregroundStyle(Color.ink)
            Text("\(session.exercises.count) exercises · \(stats.doneSets)/\(stats.totalSets) sets logged")
                .styled(.body)
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Mutations

    /// Long-press menu hook on a set row. Flips the warmup flag, which is
    /// the single source of truth for the PR / volume / 1RM exclusion path
    /// (see UserDatabase.bestWeightsByExerciseAndReps, MuscleVolume,
    /// StrengthStandards). UI re-renders pick up smaller font + dimmed
    /// opacity + leading "W" pill automatically via the @State binding.
    func toggleWarmup(exIdx: Int, setIdx: Int) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].isWarmup.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func setRIR(exIdx: Int, setIdx: Int, value: String) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].rir = value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func toggleSet(exIdx: Int, setIdx: Int) {
        let wasDone = session.exercises[exIdx].sets[setIdx].done
        session.exercises[exIdx].sets[setIdx].done = !wasDone

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if !wasDone {
            // Just marked done. Start rest timer if not the final set.
            //
            // Superset-aware: when this exercise belongs to a superset and
            // there are still un-completed siblings at THIS set index in the
            // group, skip the rest timer — the user is mid-round-robin and
            // should move to the next member's matching set. The rest only
            // fires after the LAST member of the group completes set `setIdx`.
            //
            // Inter-exercise auto-rest: when this is the final set of the
            // exercise (and the superset round is complete) AND there's a
            // next exercise still owed sets, start a rest anchored to this
            // set using the current exercise's rest interval. Lifters
            // expect the same rest window between exercises as between sets,
            // so we don't change the duration on the transition.
            let ex = session.exercises[exIdx]
            let hasMoreSets = setIdx < ex.sets.count - 1

            if isMidSupersetRound(exIdx: exIdx, setIdx: setIdx) {
                // Clear any pending rest from a prior round so the active band
                // moves cleanly to the next group member.
                rest.clear()
            } else if !Self.uiTestSuppressAutoRest, hasMoreSets {
                rest.start(exIdx: exIdx, setIdx: setIdx, duration: ex.rest)
            } else if !Self.uiTestSuppressAutoRest, hasFollowingWork(afterExIdx: exIdx) {
                // Last set of this exercise, but the session has more work
                // ahead — auto-start the rest so the user gets the same
                // countdown + expiry alert between exercises.
                rest.start(exIdx: exIdx, setIdx: setIdx, duration: ex.rest)
            }
        } else {
            // Untoggled — clear rest if it was anchored to this set.
            if rest.exIdx == exIdx, rest.setIdx == setIdx {
                rest.clear()
            }
        }
    }

    /// Mark every set in this exercise done in one tap. Doesn't start a rest
    /// timer — the bulk-log path means the user already rested at the rack.
    func logAllSets(exIdx: Int) {
        markAllSetsDone(exIdx: exIdx)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if rest.exIdx == exIdx { rest.clear() }
    }

    /// Whole-workout version of `logAllSets`: mark EVERY set in EVERY exercise
    /// done in one tap, for users who did the whole session at the rack and
    /// just want to record it. Same per-exercise weight/reps propagation; one
    /// haptic; clears any pending rest.
    private func logAllSetsAllExercises() {
        for exIdx in session.exercises.indices { markAllSetsDone(exIdx: exIdx) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rest.clear()
    }

    func addSet(exIdx: Int) {
        let ex = session.exercises[exIdx]
        let lastSet = ex.sets.last
        let newSet = LoggedSet(
            num: ex.sets.count + 1,
            weight: lastSet?.weight ?? "",
            reps: lastSet?.reps ?? String(ex.targetReps),
            rpe: "",
            done: false
        )
        session.exercises[exIdx].sets.append(newSet)
    }

    /// Remove a logged set and renumber the remaining rows. If this set
    /// anchored the active rest card, clear the rest too.
    func deleteSet(exIdx: Int, setIdx: Int) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        // If the rest card was anchored to this set, clear it.
        if rest.exIdx == exIdx, rest.setIdx == setIdx {
            rest.clear()
        } else if rest.exIdx == exIdx, let r = rest.setIdx, r > setIdx {
            // Anchor sits below the deleted row — shift it up by one so it
            // stays attached to the same logical set.
            rest.setIdx = r - 1
        }
        session.exercises[exIdx].sets.remove(at: setIdx)
        // Renumber. LoggedSet.num is 1-indexed and otherwise diverges from
        // its row position after deletes.
        for i in session.exercises[exIdx].sets.indices {
            session.exercises[exIdx].sets[i].num = i + 1
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// "Re-open" a set the user marked done so they can edit weight / reps /
    /// effort. We don't expose this as a hard-delete button on the row
    /// because un-toggling preserves the previously-entered values, which is
    /// what the user usually wants (e.g. they hit Done before adding RPE).
    func reopenSet(exIdx: Int, setIdx: Int) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].done = false
        // Clear the rest if it was anchored to this row, otherwise we end up
        // with an active rest pointing at an un-done set.
        if rest.exIdx == exIdx, rest.setIdx == setIdx { rest.clear() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Append a freshly picked exercise to the active session. Mirrors the
    /// "new exercise" branch in SessionStore.applyWorkoutDiffToActiveSession:
    /// 3 sets × 8 reps × 90s rest, no prevSets, no supersetGroup.
    private func appendExerciseFromPicker(_ picked: Exercise) {
        let target = 3
        let reps = 8
        let sets = (0..<target).map { i in
            LoggedSet(num: i + 1, weight: "", reps: "", rpe: "", done: false)
        }
        let newEx = LoggedExercise(
            id: "ad-hoc-\(UUID().uuidString.prefix(8))",
            name: picked.name,
            type: picked.modalityLabel,
            unit: "lbs",
            targetSets: target,
            targetReps: reps,
            rest: 90,
            sets: sets,
            prevSets: [],
            rpe: nil,
            tempo: nil,
            supersetGroup: nil
        )
        session.exercises.append(newEx)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        guard !didLoad else { return }
        guard let existing = store.active else {
            // Render an empty state rather than inventing a workout that isn't
            // today's. See `noSession`.
            noSession = true
            return
        }
        session = existing
        // UI-test hook: --ui-test-rest-seconds=N clamps every exercise's rest
        // so timer-expiry tests can fire in ~2s instead of 60-90s. Has no
        // effect outside test runs.
        if let s = Self.uiTestRestOverride {
            for i in session.exercises.indices {
                session.exercises[i].rest = s
            }
        }
        didLoad = true
    }

    private var noSessionState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34))
                .foregroundStyle(Color.ink3)
            Text("No workout in progress")
                .font(.custom("Inter-Regular", size: 15).weight(.bold))
                .foregroundStyle(Color.ink)
            Text("Start today's session from the Today tab.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
            if onCancel != nil {
                Button("Back to Today") { onCancel?() }
                    .font(.custom("Inter-Regular", size: 13).weight(.bold))
                    .foregroundStyle(Color.accent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }

    private static let uiTestRestOverride: Int? = {
        let prefix = "--ui-test-rest-seconds="
        guard let arg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix(prefix)
        }) else { return nil }
        return Int(arg.dropFirst(prefix.count))
    }()

    // UI-test hook: --ui-test-suppress-auto-rest disables the auto-started rest
    // card after a set is marked done. The per-set TapBudget flow taps each
    // undone set's check one by one; an inline rest card overlays the next row
    // and drops its controls from the a11y tree faster than the 1s rest clamp
    // clears them, undercounting taps. Suppressing auto-rest makes that flow
    // deterministic. No effect outside test runs; rest-behavior tests don't
    // pass this flag.
    private static let uiTestSuppressAutoRest =
        ProcessInfo.processInfo.arguments.contains("--ui-test-suppress-auto-rest")

    // MARK: - Placeholder

    private static let placeholder = ActiveSession(
        templateId: "",
        name: "",
        category: "",
        startTime: Date(),
        exercises: [],
        feel: nil,
        note: nil
    )
}

#Preview {
    let store = SessionStore(defaults: UserDefaults(suiteName: "preview.log")!)
    _ = {
        UserDefaults(suiteName: "preview.log")!.removePersistentDomain(forName: "preview.log")
    }()
    return LogScreen(onFinish: {})
        .environmentObject(store)
        .environmentObject(MemoryStore(defaults: UserDefaults(suiteName: "preview.log")!))
}

#Preview("Supersets") {
    // Mock superset session: A1 (Bench) + A2 (DB Row) form group 1,
    // then a solo squat in between, then B1 (Curl) + B2 (Pushdown) form
    // group 2. Demonstrates the band, the A1/A2/B1/B2 labels, the
    // round-robin reorder (group 2 anchored at its first appearance).
    let suite = "preview.log.supersets"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SessionStore(defaults: defaults)
    let mock = ActiveSession(
        templateId: "mock-superset",
        name: "Upper · superset preview",
        category: "Demo",
        startTime: Date().addingTimeInterval(-12 * 60),
        exercises: [
            LoggedExercise(
                id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
                targetSets: 3, targetReps: 8, rest: 90,
                sets: [
                    LoggedSet(num: 1, weight: "135", reps: "8", rpe: "7", done: true),
                    LoggedSet(num: 2, weight: "135", reps: "8", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "135", reps: "8", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 1
            ),
            LoggedExercise(
                id: "row", name: "DB Row", type: "Dumbbell", unit: "lbs",
                targetSets: 3, targetReps: 10, rest: 90,
                sets: [
                    LoggedSet(num: 1, weight: "55", reps: "10", rpe: "7", done: true),
                    LoggedSet(num: 2, weight: "55", reps: "10", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "55", reps: "10", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 1
            ),
            LoggedExercise(
                id: "squat", name: "Back Squat", type: "Barbell", unit: "lbs",
                targetSets: 3, targetReps: 5, rest: 180,
                sets: [
                    LoggedSet(num: 1, weight: "225", reps: "5", rpe: "8", done: false),
                    LoggedSet(num: 2, weight: "225", reps: "5", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "225", reps: "5", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: nil
            ),
            LoggedExercise(
                id: "curl", name: "Cable Curl", type: "Cable", unit: "lbs",
                targetSets: 3, targetReps: 12, rest: 60,
                sets: [
                    LoggedSet(num: 1, weight: "40", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 2, weight: "40", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "40", reps: "12", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 2
            ),
            LoggedExercise(
                id: "pushdown", name: "Tricep Pushdown", type: "Cable", unit: "lbs",
                targetSets: 3, targetReps: 12, rest: 60,
                sets: [
                    LoggedSet(num: 1, weight: "50", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 2, weight: "50", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "50", reps: "12", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 2
            ),
        ],
        feel: nil,
        note: nil
    )
    store.saveActive(mock)
    return LogScreen(onFinish: {})
        .environmentObject(store)
        .environmentObject(MemoryStore(defaults: UserDefaults(suiteName: "preview.log")!))
}
