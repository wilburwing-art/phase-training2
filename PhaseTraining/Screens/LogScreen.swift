// LogScreen.swift — The core training log screen.
//
// Ports `handoff/proto/log.jsx` (behavior) + `handoff/hd-training-log.jsx` (visuals)
// to SwiftUI. Sticky header with elapsed timer + progress bar, scrollable exercise
// list with inline number inputs, set checkboxes, inline rest-timer card with
// pulse animation, "+ Add Set", active-row indicator, auto-save on every change.
//
// State model:
//   - `workout: ActiveWorkoutController` owns the live `ActiveSession` and the
//     `RestTimerState`. Its `session` didSet persists through store.saveActive
//     on every change; set, rest and superset rules live on the controller.
//     `session` and `rest` below forward to it so the extension files read them
//     unchanged. Rest is not persisted. Initial duration is `ex.rest`; +15
//     extends the countdown; Skip clears. See RestTimerState.swift.
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
    @AppStorage(WatchSyncCoordinator.appInstalledKey) private var watchAppInstalled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // T2-1 / T2-3 (declared here: LogSetRow.swift is an extension and
    // cannot hold stored properties). Column widths were hard pixel frames sized for the fixed
    // 13.5pt mono font. Now that the type scales with Dynamic Type these have
    // to scale with it or the log clips at the first larger setting.
    // `.footnote` matches what `.monoS` / `.body` scale with.
    @ScaledMetric(relativeTo: .footnote) var setNumWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) var labelWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .footnote) var effortWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .caption2) var setTypePillWidth: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) var setTypePillHeight: CGFloat = 14

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject private var memoryStore: MemoryStore
    @EnvironmentObject private var conv: CoachConversationStore
    @ObservedObject var workout: ActiveWorkoutController
    @StateObject private var voice: VoiceLogModel
    let onFinish: () -> Void
    var onCancel: (() -> Void)? = nil

    init(workout: ActiveWorkoutController,
         onFinish: @escaping () -> Void,
         onCancel: (() -> Void)? = nil) {
        self.workout = workout
        self.onFinish = onFinish
        self.onCancel = onCancel
        _voice = StateObject(wrappedValue: VoiceLogModel(workout: workout, input: nil))
    }

    var session: ActiveSession {
        get { workout.session }
        nonmutating set { workout.session = newValue }
    }
    var rest: RestTimerState {
        get { workout.rest }
        nonmutating set { workout.rest = newValue }
    }
    @State private var didLoad = false
    @State private var showCancelConfirm = false
    /// Finish commits irreversibly — CompleteScreen saves on .onAppear
    /// ("Finish IS the save"). The button sits directly beside "Log all" in the
    /// sticky header, so a mis-tap permanently wrote a half-logged workout into
    /// user.db, streaks and planner history. Cancel already confirms; the far
    /// more destructive action did not.
    @State private var showFinishConfirm = false
    /// "Log all" marks every remaining set done as planned, so it asks first.
    @State private var showLogAllConfirm = false
    /// PR 9 — "Stop early" is a distinct exit from Finish: it ends the
    /// session as an abandonment (<70% completion → rules-engine
    /// reshuffle, reason feeds the coach). nil = sheet closed.
    @State private var showAbandonSheet = false
    /// "Logged for" sheet: a workout done earlier, without the phone.
    @State private var showLoggedForSheet = false
    /// Sets the user marked done. Finishing with some still open is normal
    /// (dropped a set, ran out of time) — only confirm when it looks accidental.
    private var incompleteSetCount: Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { !$0.done }.count }
    }

    /// What Apple Music is playing, for the card above the tab bar. The
    /// simulator has no Music app, so `--ui-test-fake-now-playing` swaps in
    /// a fake that is playing and authorised (layout proof for the UI test).
    @StateObject private var nowPlaying = NowPlayingModel(
        player: ProcessInfo.processInfo.arguments.contains("--ui-test-fake-now-playing")
            ? FakeMusicPlayer(playbackState: .playing, authorization: .authorized,
                              track: NowPlayingTrack(title: "Blinding Lights", artist: "The Weeknd", artwork: nil))
            : MPMusicPlayerWrapper())

    /// Long-press driven "swap exercise" sheet. nil = closed. Keys by index
    /// into session.exercises so we can mutate it on pick.
    @State var swappingExIdx: Int? = nil
    /// Read-only Exercise detail (name → coach.db lookup). Opens via row tap
    /// (mid-workout how-to) or contextMenu "Show details".
    @State var detailExercise: Exercise? = nil
    /// Plate calculator opened from a barbell exercise's context menu, carrying
    /// the weight to load. Profile was the only way in before (gap pass 2026-10-31).
    @State var plateTarget: PlateTarget? = nil
    /// The exercise whose note sheet is open.
    @State var noteTarget: ExerciseNoteTarget? = nil
    /// The exercise whose hold timer is open.
    @State var holdTarget: HoldTimerTarget? = nil
    /// Mid-workout "Add exercise" picker. true = sheet open.
    @State private var addingExercise: Bool = false

    /// Exercise indices (into `session.exercises`) where the user tapped the
    /// "BW" label to reveal a weight input for a bodyweight movement — the
    /// rare weighted-bird-dog / weight-vest case. Bodyweight exercises hide
    /// the weight column by default so reps-only sets need zero weight taps.
    @State var weightEntryExercises: Set<Int> = []

    /// Debounce for downstream weight + reps propagation, keyed by
    /// "column-exIdx-setIdx". Without it the fill fired on every keystroke,
    /// briefly pushing partial values (1, 13, 135) into later sets while the
    /// user was still typing. The column prefix keeps the two independent: a
    /// weight edit must not cancel a pending reps fill on the same row.
    @State var setPropagateTasks: [String: Task<Void, Never>] = [:]
    @State var setPropagateOld: [String: String] = [:]

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if didLoad {
                content
            }
        }
        .preferredColorScheme(.dark)
        // Weight cells arrive pre-filled from the set above, so tapping one to
        // go heavier should not start with a row of backspaces.
        .selectsAllOnFocusInNumberFields()
        .onAppear(perform: loadIfNeeded)
        // The mic is set up on the first press (VoiceLogModel.pressDown), not
        // here. The first Log open on a fresh simulator paid the speech and
        // synthesizer setup while the picker sheet came up, and the app went
        // 30 s without an idle event loop (11e 1.16, run 45755849745).
        .task { await openPickerForEmptySession() }
        .onDisappear { voice.cancel() }
        .onChange(of: workout.rest) { _, _ in
            // Lock Screen / Dynamic Island rest timer. One report covers start,
            // +15, -15, a new rest and skip; the expiry notification is untouched.
            RestActivityCenter.shared.sync(workout.liveActivitySnapshot())
        }
        .onReceive(store.$active) { external in
            // A change that did not come from this screen: the watch marked a
            // set (WatchSyncCoordinator). Our own edits round-trip as the same
            // value and fall through the guard.
            guard didLoad, let external, external != workout.session else { return }
            let before = workout.session
            workout.session = external
            for (exIdx, ex) in external.exercises.enumerated() {
                let previous = before.exercises.first { $0.id == ex.id }?.sets ?? []
                for (setIdx, set) in ex.sets.enumerated()
                where set.done && !(previous.first { $0.num == set.num }?.done ?? false) {
                    workout.startRestAfterCompleting(exIdx: exIdx, setIdx: setIdx)
                }
            }
        }
        .alert("Discard workout?", isPresented: $showCancelConfirm) {
            Button("Discard", role: .destructive) { onCancel?() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your in-progress sets won't be saved.")
        }
        .alert("Log all remaining sets?", isPresented: $showLogAllConfirm) {
            Button("Log all") { logAllSetsAllExercises() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(incompleteSetCount == 1
                 ? "This marks the last set done as planned."
                 : "This marks \(incompleteSetCount) sets done as planned.")
        }
        .alert("Finish workout?", isPresented: $showFinishConfirm) {
            Button("Finish") { onFinish() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(incompleteSetCount == 1
                 ? "One set isn't logged yet. Finishing saves the workout as it stands."
                 : "\(incompleteSetCount) sets aren't logged yet. Finishing saves the workout as it stands.")
        }
        .sheet(isPresented: $showLoggedForSheet) {
            LoggedForSheet(loggedFor: $workout.session.loggedFor)
        }
        .sheet(isPresented: $showAbandonSheet) {
            // PR 9 — typed abandon-reason capture. Confirm saves the
            // partial session through the normal completed path (the
            // logged sets are real history) and records the
            // AbandonedWorkoutEntry the rules engine + coach read.
            AbandonReasonSheet(
                completionSummary: "\(store.stats(for: session).doneSets) of \(store.stats(for: session).totalSets) sets logged",
                onConfirm: { reason, note, hurtAreas in
                    abandonWorkout(reason: reason, note: note, hurtAreas: hurtAreas)
                },
                onCancel: {}
            )
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
                conversion: .swapIn,
                onPick: { picked in
                    swapExercise(at: wrapped.index, with: picked)
                }
            )
        }
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(item: $plateTarget) { target in
            PlateCalculatorSheet(initialTarget: target.weight)
                .environmentObject(memoryStore)
        }
        .sheet(item: $holdTarget) { target in
            if session.exercises.indices.contains(target.index),
               let hold = HoldProtocol.parse(session.exercises[target.index].repsLabel) {
                let ex = session.exercises[target.index]
                HoldTimerSheet(
                    exerciseName: ex.name,
                    hold: hold,
                    onMarkSetDone: ex.sets.firstIndex(where: { !$0.done }).map { setIdx in
                        { workout.toggleSet(exIdx: target.index, setIdx: setIdx) }
                    })
            }
        }
        .sheet(item: $noteTarget) { target in
            if session.exercises.indices.contains(target.index) {
                ExerciseNoteSheet(
                    exerciseName: session.exercises[target.index].name,
                    lastNote: session.exercises[target.index].lastNote,
                    note: Binding(
                        get: { session.exercises[target.index].note ?? "" },
                        set: {
                            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            session.exercises[target.index].note = trimmed.isEmpty ? nil : $0
                        }))
            }
        }
        .sheet(isPresented: $addingExercise) {
            // Mid-workout add. No initial filter — user came to the log
            // wanting to insert something specific that wasn't in the plan,
            // so we open the picker wide and let them search.
            ExercisePickerSheet(
                title: "Add exercise",
                conversion: .addToSession,
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
        var updated = session
        updated.exercises[idx].name = picked.name
        if let modality = picked.modality, !modality.isEmpty {
            updated.exercises[idx].type = picked.modalityLabel
        }
        let category = LoggedExercise.equipmentCategory(forPicked: picked)
        updated.exercises[idx].unit = LoggedExercise.unit(for: category)
        updated.exercises[idx].prevSets = store.previousSets(forExerciseNamed: picked.name)
        session = updated
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
                                .scaledSystemFont(13, weight: .semibold)
                            Text("Add exercise")
                                .styled(.body)
                        }
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-add-exercise")

                    // Bottom clearance. With no media card, 120pt clears the
                    // system tab bar. Without it the last few exercise rows render UNDER the tab bar
                    // (snapshot_ui showed tab bar at y=791-874 occluding
                    // log-set-check-2-N for the 3rd-of-5 exercise in the
                    // supersets demo seed). Tab bar visible height is
                    // 49pt + home-indicator inset ~34pt = ~83pt. 120pt
                    // gives an extra safety margin so reorder-handles and
                    // contextMenus don't get shadowed either. While the media
                    // card shows, the safe-area inset dock already ends the
                    // content above the card and the tab bar, so 16pt is enough.
                    Color.clear.frame(height: nowPlaying.state == .hidden ? 120 : 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) { VoiceHeardOverlay(model: voice) }
            .safeAreaInset(edge: .bottom) {
                // Media card, like Google Maps during navigation: change the
                // track without leaving the workout. Comes and goes with
                // playback. The card and everything below it (the gap and the
                // tab bar's safe area) sit on one opaque dock so set rows never
                // show through; a short gradient softens the cut-off above it.
                if nowPlaying.state != .hidden {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Color.bg.opacity(0), Color.bg],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        NowPlayingCard(model: nowPlaying)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .background(Color.bg.ignoresSafeArea(edges: .bottom))
                    }
                    .transition(Motion.transition(.move(edge: .bottom).combined(with: .opacity), reduced: Motion.isReduced(reduceMotion)))
                }
            }
            .motion(.easeInOut(duration: 0.25), .fade, value: nowPlaying.state)
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
                            .scaledSystemFont(14, weight: .semibold, within: 28)
                            .foregroundStyle(Color.ink2)
                            .frame(width: 28, height: 28)
                            .background(Color.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-cancel")
                    // Icon-only: VoiceOver read "xmark".
                    .accessibilityLabel("Discard workout")
                }

                Image(systemName: session.loggedFor == nil ? "timer" : "calendar")
                    .scaledSystemFont(14, weight: .regular)
                    .foregroundStyle(Color.ink3)

                // A workout logged for an earlier time has no live clock: the
                // header shows when it happened.
                if let past = session.loggedFor {
                    Text(LoggedForSheet.label(past))
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                        Text(Self.fmtElapsed(ctx.date.timeIntervalSince(session.startTime)))
                            .styled(.monoM)
                            .foregroundStyle(Color.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }

                Spacer()

                VoiceMicButton(model: voice)

                // Whole-workout shortcut: log every remaining set in one tap
                // (rack-first users). Secondary styling keeps Finish the
                // primary CTA. Hidden once everything's logged.
                if anyUndone {
                    Button { showLogAllConfirm = true } label: {
                        Text("Log all")
                            .lineLimit(1)
                            .fixedSize()
                            .font(.scaled("Inter-Regular", size: 13).weight(.bold))
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
                        .lineLimit(1)
                        .fixedSize()
                        .font(.scaled("Inter-Regular", size: 13).weight(.bold))
                        .tracking(-0.01 * 13)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log-finish")
                // "Stop early" lives in the title block, not here: three
                // padded text buttons plus the timer overflowed a 393pt
                // header and wrapped every label onto two lines.
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
                        .motion(.easeInOut(duration: 0.3), .movement, value: progress)
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
        let anyUndone = stats.doneSets < stats.totalSets
        return VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .styled(.displayM)
                .foregroundStyle(Color.ink)
            Button {
                showLoggedForSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(LoggedForSheet.label(session.loggedFor))
                        .styled(.body)
                        .foregroundStyle(session.loggedFor == nil ? Color.ink3 : Color.accent)
                    Image(systemName: "chevron.down")
                        .scaledSystemFont(10, weight: .semibold)
                        .foregroundStyle(Color.ink3)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("log-logged-for")
            .accessibilityLabel(session.loggedFor == nil
                                ? "Logged for today. Change the date"
                                : "Logged for \(LoggedForSheet.label(session.loggedFor)). Change the date")
            if watchAppInstalled {
                Text("Also on your Apple Watch. Sets you mark there land here.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .accessibilityIdentifier("log-watch-hint")
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(session.exercises.count) exercises · \(stats.doneSets)/\(stats.totalSets) sets logged")
                    .styled(.body)
                    .foregroundStyle(Color.ink3)
                Spacer(minLength: 0)
                // PR 9 — distinct from Finish: ends the session as an
                // ABANDONMENT (reason captured in AbandonReasonSheet) so
                // the rules engine can reshuffle the rest of the week
                // and the coach learns why. Only meaningful when sets
                // remain — a fully-logged workout is just Finish. Sits
                // here rather than in the sticky header because the
                // header row has no room for a third button.
                if anyUndone {
                    Button {
                        showAbandonSheet = true
                    } label: {
                        Text("Stop early")
                            .styled(.body)
                            .foregroundStyle(Color.ink2)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-stop-early")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Mutations

    /// PR 9 — end the session as an abandonment. Saves the partial
    /// session through the normal completed path (logged sets are real
    /// history: PRs, volume, prior-best), then records the
    /// AbandonedWorkoutEntry. Callback to TodayTab drops back to Start.
    func abandonWorkout(reason: AbandonReason, note: String?, hurtAreas: [String]) {
        store.saveAbandoned(session, reason: reason, note: note, hurtAreas: hurtAreas)
        // PR 9 — pain abandons soft-trigger a coach check-in: the
        // drawer opens with a pre-filled question the user can edit or
        // send. Gated on coach entitlement so a locked user isn't
        // yanked into an upsell mid-recovery. "Soft" — dismissible, no
        // forced chat, no notification.
        if reason == .pain, conv.presented == false {
            var prefill = "I stopped today's workout early because of pain"
            if !hurtAreas.isEmpty { prefill += " in my \(hurtAreas.joined(separator: " and "))" }
            if let note, !note.isEmpty { prefill += " (\(note))" }
            prefill += ". Can you adjust the rest of my week around it?"
            conv.present(withPrefill: prefill)
        }
        onFinish()
    }

    /// Long-press menu hook on a set row. `setType` is the single source for
    /// which reads count the set (see `SetType.isWorkingSet` and
    /// `countsForStrength`).
    func setSetType(exIdx: Int, setIdx: Int, _ type: SetType) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx),
              session.exercises[exIdx].sets[setIdx].setType != type else { return }
        session.exercises[exIdx].sets[setIdx].setType = type
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        var updated = session
        for exIdx in updated.exercises.indices {
            Self.markAllSetsDone(in: &updated, exIdx: exIdx)
        }
        session = updated
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rest.clear()
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
        var updated = session
        updated.exercises[exIdx].sets.remove(at: setIdx)
        // Renumber. LoggedSet.num is 1-indexed and otherwise diverges from
        // its row position after deletes.
        for i in updated.exercises[exIdx].sets.indices {
            updated.exercises[exIdx].sets[i].num = i + 1
        }
        session = updated
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Append a freshly picked exercise to the active session. Mirrors the
    /// "new exercise" branch in SessionStore.applyWorkoutDiffToActiveSession:
    /// 3 sets × 8 reps × 90s rest, no supersetGroup. Unit and last-time sets
    /// are derived the same way `swapExercise` does, so a freestyle session
    /// shows what the lifter did last time on each pick.
    private func appendExerciseFromPicker(_ picked: Exercise) {
        let target = 3
        let reps = 8
        let sets = (0..<target).map { i in
            LoggedSet(num: i + 1, weight: "", reps: "", rpe: "", done: false)
        }
        let newEx = LoggedExercise(
            id: "ad-hoc-\(UUID().uuidString.prefix(8))",
            name: picked.name,
            type: (picked.modality?.isEmpty == false) ? picked.modalityLabel : nil,
            unit: LoggedExercise.unit(for: LoggedExercise.equipmentCategory(forPicked: picked)),
            targetSets: target,
            targetReps: reps,
            rest: 90,
            sets: sets,
            prevSets: store.previousSets(forExerciseNamed: picked.name),
            rpe: nil,
            tempo: nil,
            supersetGroup: nil
        )
        session.exercises.append(newEx)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Loading

    /// How long the empty-session picker waits after the screen appears.
    /// TodayTab fades into Log over 0.18 s. A sheet presented inside that
    /// fade left the app without an idle event loop for 60 s on CI (run
    /// 45588713411, FreestyleWorkoutUITests), so the sheet opens after it.
    static let emptySessionPickerDelay: Duration = .milliseconds(300)

    /// A freestyle session starts empty: open the picker so the first
    /// exercise is one tap away.
    private func openPickerForEmptySession() async {
        guard workout.session.exercises.isEmpty else { return }
        try? await Task.sleep(for: Self.emptySessionPickerDelay)
        guard !Task.isCancelled, workout.session.exercises.isEmpty else { return }
        addingExercise = true
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        // UI-test hook: --ui-test-rest-seconds=N clamps every exercise's rest
        // so timer-expiry tests can fire in ~2s instead of 60-90s. Has no
        // effect outside test runs.
        if let s = Self.uiTestRestOverride {
            var updated = workout.session
            for i in updated.exercises.indices {
                updated.exercises[i].rest = s
            }
            workout.session = updated
        }
        didLoad = true
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
    static let uiTestSuppressAutoRest =
        ProcessInfo.processInfo.arguments.contains("--ui-test-suppress-auto-rest")
}

/// Shown when the log route is reached with no active session. An anomalous
/// state, not a normal entry: TodayTab only routes here when `store.active`
/// is set, and TodayScreen owns session creation so the workout is built from
/// today's plan, never a fabricated fallback.
struct LogNoSessionView: View {
    var onCancel: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .scaledSystemFont(34)
                    .foregroundStyle(Color.ink3)
                Text("No workout in progress")
                    .font(.scaled("Inter-Regular", size: 15).weight(.bold))
                    .foregroundStyle(Color.ink)
                Text("Start today's session from the Today tab.")
                    .font(.scaled("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                if onCancel != nil {
                    Button("Back to Today") { onCancel?() }
                        .font(.scaled("Inter-Regular", size: 13).weight(.bold))
                        .foregroundStyle(Color.accent)
                        .padding(.top, 4)
                }
            }
            .padding(32)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    let store = SessionStore(defaults: UserDefaults(suiteName: "preview.log")!)
    _ = {
        UserDefaults(suiteName: "preview.log")!.removePersistentDomain(forName: "preview.log")
    }()
    return Group {
        if let active = store.active {
            LogScreen(workout: ActiveWorkoutController(store: store, session: active), onFinish: {})
        } else {
            LogNoSessionView()
        }
    }
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
    return LogScreen(workout: ActiveWorkoutController(store: store, session: mock), onFinish: {})
        .environmentObject(store)
        .environmentObject(MemoryStore(defaults: UserDefaults(suiteName: "preview.log")!))
}
