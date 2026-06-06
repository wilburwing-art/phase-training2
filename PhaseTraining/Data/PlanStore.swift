// PlanStore.swift — @Published wrapper around the active WeekPlan + the
// per-week WeekOverrides that shape it.
//
// Persists under two UserDefaults keys (secondsSince1970 dates):
//   - pt_week_plan       → the generated WeekPlan
//   - pt_week_overrides  → the user's per-week edits (availability, events)
//
// Calls Planner.generate(memory:overrides:routines:today:) at the end of
// onboarding, on weekly check-in (Phase 12), or when overrides change.
//
// `currentOverrides()` always returns a WeekOverrides anchored to the current
// week's Monday. If the persisted overrides are stale (different weekStart),
// they're discarded and a fresh empty overrides is returned. This is the
// "fresh every week" semantics the user asked for.

import Foundation
import Combine

final class PlanStore: ObservableObject {
    private static let planKey      = "pt_week_plan"
    private static let overridesKey = "pt_week_overrides"
    /// PR 4 — historical plan snapshots, rolling 12-week cap.
    /// Foundation for the weekly-coach features in
    /// PLAN-weekly-coach-roadmap.md (painted strip, rules engine,
    /// missed-workout autopilot, progress visualizations).
    private static let pastPlansKey = "pt_past_plans"
    /// PR 7 — log of dismissed PlanValidationIssues. Used to derive
    /// `suppressedRulePatterns`: a (rule, pattern) combination
    /// dismissed across ≥3 distinct weekStarts self-suppresses for
    /// the user.
    private static let planOverridesKey = "pt_plan_overrides"
    /// PR 8 — log of missed workouts. Tracks each detection so we
    /// don't re-banner the same miss twice, and feeds CoachContext
    /// with "the user has missed 3 Tuesday lifts in a row".
    private static let missedWorkoutsKey = "pt_missed_workouts"
    /// PR 8 — mid-week reshuffle counter. Resets on weekly rollover.
    /// Spec §3 rule 5: cap at 2 per week across missed + abandoned
    /// events combined (PR 9 will hit the same counter).
    private static let reshuffleCountKey = "pt_reshuffle_count"
    /// PR 8 — weekStart we last computed reshuffleCount against.
    /// When the active week changes, counter resets to 0.
    private static let reshuffleWeekKey = "pt_reshuffle_week"
    /// D3 — week-consolidation counter + the weekStart it's tagged against
    /// (resets on rollover, same as the reshuffle counter). Capped at 1/week.
    private static let consolidationCountKey = "pt_consolidation_count"
    private static let consolidationWeekKey = "pt_consolidation_week"

    /// How many weeks of history we retain. Anything older rolls off on
    /// the next snapshot. Twelve weeks matches the coach's longest-window
    /// summaries (12-week mesocycle, 12-week strength-progress chart) and
    /// keeps the persisted blob small (worst case ~50 KB compressed).
    static let pastPlansLimit = 12

    /// PR 7 — keep validation-override history bounded. Older entries
    /// roll off so a rule that bothered a user once a year ago doesn't
    /// stay suppressed forever. 90 days mirrors the soreness/feedback
    /// windows the coach already uses.
    static let planOverridesRetentionDays = 90

    @Published var plan: WeekPlan?
    @Published var overrides: WeekOverrides
    /// Rolling history of past weeks' plans. Snapshotted on every
    /// `setPlan(_:)` call (idempotent by `weekStart` — re-snapshotting the
    /// same week replaces the prior entry, keeping the latest capture) and
    /// on weekly rollover detection in `init`. Sorted newest-first.
    @Published var pastPlans: [WeekPlanSnapshot]
    /// PR 7 — recent dismissals of PlanValidationIssues. Trimmed to
    /// the last 90 days on load + on every record. Drives the
    /// suppression set the rules engine consults so a rule the user
    /// has overridden 3 weeks in a row goes silent.
    @Published var recentPlanOverrides: [WeeklyPlanOverride]
    /// PR 8 — log of missed planned workouts. Sorted newest-first.
    /// Rolling 90-day window pruned on every detection/reshuffle so
    /// the coach doesn't get fed a year-old miss.
    @Published var missedWorkouts: [MissedWorkoutEntry]
    /// PR 8 — count of mid-week reshuffles (missed + abandoned)
    /// applied in the current week. Resets on weekly rollover.
    /// Spec §3 rule 5 caps at 2/week.
    @Published var midWeekReshuffleCount: Int
    /// D3 — count of week consolidations applied in the current week.
    /// Resets on weekly rollover. Capped at 1/week (its own budget, separate
    /// from the 2/week reshuffle cap — consolidation is a bigger change).
    @Published var midWeekConsolidationCount: Int

    /// Variety memory. Wired up post-init by the App so PlanStore can stay
    /// instantiable with a single defaults param (tests, previews) while
    /// the production app gets the soft-filter on exercise reuse.
    var recentPicks: RecentPicksStore?

    /// Session history feed. Same post-init wiring pattern as `recentPicks`.
    /// When present, PlanStore builds a GeneratorContext from
    /// sessionStore.savedSessions + memory.soreness + memory.feedback and
    /// hands it to the planner, so generated workouts inherit history-aware
    /// signals (progressive overload targets, sore-area avoidance, etc.).
    /// When absent (tests, previews) the planner falls back to .empty
    /// context — same behavior as pre-build-66.
    var sessionStore: SessionStore?

    /// Sport-log feed. Build 99 — surfaces non-lift load (e.g. "climbed
    /// hard 3× this week") to the planner so it can trim lift volume when
    /// the user's already cooked. Optional + post-init like sessionStore
    /// so the test/preview surfaces stay no-op.
    var sportLogStore: SportLogStore?

    /// Custom-routine catalog. Build 105 — when the user picks a saved
    /// custom routine to override a future day (from WeekDayEditSheet),
    /// the override is keyed by routine id in WeekOverrides. PlanStore
    /// resolves the id against this store after each Planner.generate()
    /// and stamps the resulting workout onto the day. Optional + post-
    /// init like the other store refs; without it, override picks have
    /// no effect (graceful regression to pre-build-105 behavior).
    var customStore: CustomRoutineStore?

    /// Memory feed for the auto-regen subscription (build 69+). When set,
    /// PlanStore observes the published memory and silently regenerates the
    /// week whenever the user's profile changes enough to drift
    /// `planInputsHash`. The drift banner UI on Today / Week / Profile got
    /// removed in the same change — what used to be "tap to refresh" is
    /// now invisible.
    weak var memoryStore: MemoryStore? {
        didSet { resubscribeToMemory() }
    }

    let defaults: UserDefaults
    private var memorySubscription: AnyCancellable?

    /// Build 98: holds the in-flight LLM refinement Task so a fresh
    /// regen can cancel the previous one before kicking off a new pass.
    /// Lives here (not in the extension) because extensions can't add
    /// stored properties. Internal-by-default so the +LLMRefinement
    /// extension reads/writes it.
    var currentRefinementTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, today: Date = Date()) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.planKey),
           let p = try? Self.decoder().decode(WeekPlan.self, from: data) {
            self.plan = p
        } else {
            self.plan = nil
        }

        // Resolve overrides: stale (different week) → fresh.
        let thisWeek = today.startOfTrainingWeek()
        if let data = defaults.data(forKey: Self.overridesKey),
           let o = try? Self.decoder().decode(WeekOverrides.self, from: data),
           Calendar.current.isDate(o.weekStart, inSameDayAs: thisWeek) {
            self.overrides = o
        } else {
            self.overrides = WeekOverrides(weekStart: thisWeek)
        }

        // PR 4: load past-plan history. Decoded list is already trimmed +
        // sorted on save, but defensively re-trim on load in case the
        // persisted blob predates the cap rule (forward-compat with
        // future cap increases too).
        if let data = defaults.data(forKey: Self.pastPlansKey),
           let list = try? Self.decoder().decode([WeekPlanSnapshot].self, from: data) {
            self.pastPlans = WeekPlanSnapshot.trim(list, limit: Self.pastPlansLimit)
        } else {
            self.pastPlans = []
        }

        // PR 7: load validation-override log. Trim to the 90-day window
        // on load so an old blob from a fresh install doesn't carry
        // stale entries forward indefinitely.
        if let data = defaults.data(forKey: Self.planOverridesKey),
           let list = try? Self.decoder().decode([WeeklyPlanOverride].self, from: data) {
            let cutoff = today.addingTimeInterval(-Double(Self.planOverridesRetentionDays) * 86_400)
            self.recentPlanOverrides = list.filter { $0.loggedAt >= cutoff }
        } else {
            self.recentPlanOverrides = []
        }

        // PR 8: load missed-workout log + reshuffle counter. The counter
        // gets reset whenever the persisted weekStart no longer matches
        // the current training-week Monday.
        let thisWeekStart = today.startOfTrainingWeek()
        if let data = defaults.data(forKey: Self.missedWorkoutsKey),
           let list = try? Self.decoder().decode([MissedWorkoutEntry].self, from: data) {
            let cutoff = today.addingTimeInterval(-Double(Self.planOverridesRetentionDays) * 86_400)
            self.missedWorkouts = list
                .filter { $0.loggedAt >= cutoff }
                .sorted { $0.date > $1.date }
        } else {
            self.missedWorkouts = []
        }
        if let savedWeek = defaults.object(forKey: Self.reshuffleWeekKey) as? Date,
           Calendar.current.isDate(savedWeek, inSameDayAs: thisWeekStart) {
            self.midWeekReshuffleCount = defaults.integer(forKey: Self.reshuffleCountKey)
        } else {
            self.midWeekReshuffleCount = 0
        }
        if let savedWeek = defaults.object(forKey: Self.consolidationWeekKey) as? Date,
           Calendar.current.isDate(savedWeek, inSameDayAs: thisWeekStart) {
            self.midWeekConsolidationCount = defaults.integer(forKey: Self.consolidationCountKey)
        } else {
            self.midWeekConsolidationCount = 0
        }

        // Weekly-rollover detection: if we have an active plan that
        // belongs to a prior week and we haven't snapshotted it yet,
        // capture it now. This catches the case where the user opens
        // the app on a Monday after a quiet week — `setPlan` won't fire
        // until the planner regenerates, but the prior week deserves a
        // snapshot before that overwrite.
        captureRolloverIfNeeded(today: today)
    }

    /// Snapshot the currently-loaded plan if it belongs to a past week
    /// and isn't already in `pastPlans`. Called at init and from external
    /// rollover triggers (e.g. app foregrounding on a new week).
    func captureRolloverIfNeeded(today: Date = Date()) {
        guard let plan, let firstDate = plan.days.first?.date else { return }
        let planWeekStart = firstDate.startOfTrainingWeek()
        let nowWeekStart = today.startOfTrainingWeek()
        // Only snapshot if the active plan belongs to a PAST week. The
        // current week gets snapshotted from setPlan instead so we don't
        // capture an empty-Monday view of the in-flight week.
        guard planWeekStart < nowWeekStart else { return }
        // Idempotent: skip if we already have a snapshot of this week.
        if pastPlans.contains(where: { Calendar.current.isDate($0.weekStart, inSameDayAs: planWeekStart) }) {
            return
        }
        snapshotCurrentPlan(now: today)
    }

    /// Re-read plan + overrides from UserDefaults after an external write
    /// (e.g. a destructive backup-restore) so this already-instantiated store
    /// reflects the imported data without an app relaunch. Mirrors the decode
    /// path in init for these two keys (history/missed logs aren't part of the
    /// backup envelope, so they're left untouched).
    func reloadFromDefaults(today: Date = Date()) {
        if let data = defaults.data(forKey: Self.planKey),
           let p = try? Self.decoder().decode(WeekPlan.self, from: data) {
            plan = p
        } else {
            plan = nil
        }
        let thisWeek = today.startOfTrainingWeek()
        if let data = defaults.data(forKey: Self.overridesKey),
           let o = try? Self.decoder().decode(WeekOverrides.self, from: data),
           Calendar.current.isDate(o.weekStart, inSameDayAs: thisWeek) {
            overrides = o
        } else {
            overrides = WeekOverrides(weekStart: thisWeek)
        }
    }

    // MARK: - Memory-drift auto-regen

    /// Subscribe to memoryStore.$memory and silently regenerate the plan
    /// whenever the user's profile changes enough to drift `planInputsHash`.
    ///
    /// Replaces the build-26-era drift banners (Today / Week / Profile) that
    /// required a user tap to apply profile changes to the plan. The hash
    /// check is cheap; debouncing prevents cascade regens while the user
    /// edits multiple fields in a row (e.g. age + lift-days + duration).
    /// We skip when a session is active so a mid-workout profile poke
    /// doesn't reroll the active template under the user.
    private func resubscribeToMemory() {
        memorySubscription?.cancel()
        memorySubscription = nil
        guard let memoryStore else { return }
        memorySubscription = memoryStore.$memory
            .removeDuplicates { $0.planInputsHash == $1.planInputsHash }
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] memory in
                guard let self else { return }
                guard memory.onboardedAt != nil else { return }
                guard self.sessionStore?.active == nil else { return }
                guard self.needsRegeneration(for: memory) else { return }
                self.generate(from: memory)
            }
    }

    // MARK: - PR 8 — Missed-workout autopilot

    /// Spec §3 rule 5: cap mid-week reshuffles at 2 per week across
    /// missed + abandoned events combined.
    static let weeklyReshuffleCap = 2

    /// D3 — cap week consolidations at 1/week. Own budget, separate from the
    /// reshuffle cap, since collapsing the week is a bigger structural change.
    static let weeklyConsolidationCap = 1

    /// Wipe everything — dev / "Start over" flows.
    func clear() {
        plan = nil
        overrides = WeekOverrides(weekStart: Date().startOfTrainingWeek())
        pastPlans = []
        recentPlanOverrides = []
        missedWorkouts = []
        midWeekReshuffleCount = 0
        midWeekConsolidationCount = 0
        defaults.removeObject(forKey: Self.planKey)
        defaults.removeObject(forKey: Self.overridesKey)
        defaults.removeObject(forKey: Self.pastPlansKey)
        defaults.removeObject(forKey: Self.planOverridesKey)
        defaults.removeObject(forKey: Self.missedWorkoutsKey)
        defaults.removeObject(forKey: Self.reshuffleCountKey)
        defaults.removeObject(forKey: Self.reshuffleWeekKey)
        defaults.removeObject(forKey: Self.consolidationCountKey)
        defaults.removeObject(forKey: Self.consolidationWeekKey)
    }

    // MARK: - PlanEdit pipeline (Wilbur's phase 11)
    //
    // Preview-then-apply edits via PlanDiff. Used by the long-press context
    // menu on the Week tab. Mutates the WeekPlan directly (does NOT round-trip
    // through overrides / Planner) so the diff is an exact before→after.

    /// Build a PlanDiff by replaying edits against the current plan. Pure —
    /// does not mutate. Returns nil if there's no current plan.
    func propose(_ edits: [PlanEdit], reasoning: String? = nil) -> PlanDiff? {
        guard let before = plan else { return nil }
        var after = before
        for edit in edits {
            Self.applyEdit(edit, to: &after)
        }
        return PlanDiff(before: before, after: after, edits: edits, reasoning: reasoning)
    }

    /// Commit a previously proposed diff. The only public mutation point for
    /// user-driven plan edits.
    ///
    /// Persistence ordering matters: encode + write to disk BEFORE setting
    /// `plan`. The `@Published` setter triggers the SwiftUI layout cascade
    /// (TodayScreen, WeekScreen, CoachDrawer's MiniPlanDiffCard chain) on the
    /// main thread, and if that cascade exceeds the iOS watchdog's 5-second
    /// budget (build 60 hit this from the coach drawer), SIGKILL lands before
    /// the encode completes. Write-first means the new plan survives a
    /// watchdog kill — relaunch reads the user's intended change.
    func apply(_ diff: PlanDiff) {
        guard !diff.isNoop else { return }

        // Sync `generatedWorkout` for any day whose kind changed. PlanEdit
        // handlers update kind/title/routineId only — manual Week-tab edits
        // round-trip through Planner.generate() which rebuilds workouts, but
        // the coach path skips that. Without this sync, Today shows the old
        // workout's exercises under a new kind (lift→mobility leaves lift
        // exercises) or an empty hero with no Start CTA (rest→lift never gets
        // a workout populated).
        var after = diff.after
        if let memory = memoryStore?.memory {
            let beforeById = Dictionary(uniqueKeysWithValues: diff.before.days.map { ($0.id, $0) })
            var pickedIds: [Int] = []
            for idx in after.days.indices {
                let day = after.days[idx]
                guard let prior = beforeById[day.id], prior.kind != day.kind else { continue }
                switch day.kind {
                case .lift:
                    if let workout = composeWorkout(for: day, in: after, memory: memory) {
                        after.days[idx].generatedWorkout = workout
                        after.days[idx].title = workout.title
                        after.days[idx].routineId = nil
                        after.days[idx].generatedReason = workout.provenance
                        pickedIds.append(contentsOf: workout.exercises.map(\.exerciseId))
                    }
                case .rest, .sport, .event:
                    after.days[idx].generatedWorkout = nil
                }
            }
            if !pickedIds.isEmpty { recentPicks?.record(exerciseIds: pickedIds) }
        }

        if let data = try? Self.encoder().encode(after) {
            defaults.set(data, forKey: Self.planKey)
        }
        plan = after
        // Build 99: structural edits (move/swap_kind/add/remove a day)
        // can produce freshly-composed workouts via composeWorkout above,
        // which are NOT yet LLM-personalized. Re-fire refinement so the
        // user sees the same "coach polished this" treatment they'd have
        // gotten from a full regen. No-op without consent or when there
        // are no candidate days.
        if let memory = memoryStore?.memory {
            kickOffLLMRefinementIfConsented(memory: memory)
        }
    }

    /// Phase 13d: swap in a new generated workout on the day matching
    /// `date`. Returns false if no plan or the day isn't found. Caller must
    /// pre-check SessionStore.active to avoid trampling logged sets.
    @discardableResult
    func applyWorkoutDiff(_ diff: WorkoutDiff, on date: Date) -> Bool {
        guard var current = plan, !diff.isNoop else { return false }
        let cal = Calendar.current
        guard let idx = current.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) else {
            return false
        }
        // An applied workout diff is the user's final word for this day — it
        // arrives from a coach proposal (MiniWorkoutDiffCard "Apply") or a
        // manual swap. Stamp refinedByLLMAt so the background refinement
        // candidate filter skips this day.
        //
        // The previous build-99 code cleared the flag and re-fired refinement
        // "to re-personalize from the edited baseline" — but refineSingleDay
        // regenerates the day from scratch (it never reads the edited
        // exercises), so the refire silently rerolled the edit away ~5-10s
        // after the user applied it. Re-personalization belongs to the next
        // full regen (profile drift), which rebuilds the whole day anyway.
        var edited = diff.after
        edited.refinedByLLMAt = Date()
        current.days[idx].generatedWorkout = edited
        plan = current
        savePlan()
        return true
    }

    /// Apply a single edit to a WeekPlan in place. Defined as a static helper
    /// so PlannerTests can drive it without an instance.
    static func applyEdit(_ edit: PlanEdit, to plan: inout WeekPlan) {
        let cal = Calendar.current
        switch edit {
        case .move(let id, let toDate):
            guard let srcIdx = plan.days.firstIndex(where: { $0.id == id }) else { return }
            let target = cal.startOfDay(for: toDate)
            if let dstIdx = plan.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: target) }) {
                if srcIdx != dstIdx {
                    let srcDate = plan.days[srcIdx].date
                    plan.days[srcIdx].date = plan.days[dstIdx].date
                    plan.days[dstIdx].date = srcDate
                    plan.days.sort { $0.date < $1.date }
                }
            } else {
                plan.days[srcIdx].date = target
                plan.days.sort { $0.date < $1.date }
            }

        case .swapKind(let id, let to, let title, let routineId):
            guard let idx = plan.days.firstIndex(where: { $0.id == id }) else { return }
            plan.days[idx].kind = to
            plan.days[idx].title = title
            plan.days[idx].routineId = (to == .lift) ? routineId : nil
            if to != .sport { plan.days[idx].sport = nil }

        case .protectDay(let id, let eventTitle):
            guard let idx = plan.days.firstIndex(where: { $0.id == id }) else { return }
            plan.days[idx].kind = .event
            plan.days[idx].title = eventTitle
            plan.days[idx].protected = true
            plan.days[idx].routineId = nil
            plan.days[idx].sport = nil

        case .shorten(let id, let toMinutes):
            guard let idx = plan.days.firstIndex(where: { $0.id == id }) else { return }
            plan.days[idx].durationMinutes = toMinutes

        case .addSession(let date, let kind, let title, let routineId):
            let target = cal.startOfDay(for: date)
            if let idx = plan.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: target) }) {
                plan.days[idx].kind = kind
                plan.days[idx].title = title
                plan.days[idx].routineId = (kind == .lift) ? routineId : nil
            }

        case .removeSession(let id):
            guard let idx = plan.days.firstIndex(where: { $0.id == id }) else { return }
            plan.days[idx].kind = .rest
            plan.days[idx].title = "Rest"
            plan.days[idx].routineId = nil
            plan.days[idx].sport = nil
            plan.days[idx].durationMinutes = nil
        }
    }

    // MARK: - Drag-and-drop swap (my phase 11c)
    //
    // Direct (no preview) swap via paired dayOverrides. Used by drag-and-drop
    // on the Week tab and by the WeekDayEditSheet "Move workout to…" picker.
    // Goes through the planner regeneration path so taper/buffer/recovery
    // rules re-apply against the new arrangement.

    /// Swap two days' kinds (and routine ids / sports) via paired dayOverrides.
    /// No-op when source == target or when either date isn't in the current plan.
    func swap(sourceDate: Date,
              targetDate: Date,
              memory: TrainingMemory,
              today: Date = Date()) {
        let cal = Calendar.current
        guard !cal.isDate(sourceDate, inSameDayAs: targetDate) else { return }
        guard let plan,
              let sourcePlan = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: sourceDate) }),
              let targetPlan = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: targetDate) })
        else { return }

        let sourceOverride = DayKindOverride.from(plan: sourcePlan)
        let targetOverride = DayKindOverride.from(plan: targetPlan)

        updateOverrides(memory: memory, today: today) { o in
            o.dayOverrides[cal.startOfDay(for: sourceDate)] = targetOverride
            o.dayOverrides[cal.startOfDay(for: targetDate)] = sourceOverride
        }
    }

    // MARK: - Drift detection

    /// True when the persisted plan was generated from inputs that no longer
    /// match the current memory — phase 12 weekly check-in will read this.
    func needsRegeneration(for memory: TrainingMemory) -> Bool {
        guard let plan else { return true }
        return plan.inputsHash != memory.planInputsHash
    }

    // MARK: - Targeted regeneration (Phase 15c)
    //
    // The full `generate(from:)` rewrites the entire week. These finer-grained
    // entry points let the user re-roll just today's workout (variety / "I want
    // something different") or refresh the whole week against the current
    // profile (drift after a Profile edit) without losing the rest of the plan.

    /// Replace one day's generated workout with a freshly composed one. Keeps
    /// the rest of the week intact. No-op if today isn't in the current plan,
    /// the day isn't lift / mobility, or the day is protected (user-pinned).
    ///
    /// `salt` lets the caller force a fresh deterministic pick when re-rolling
    /// the same day (default = current timestamp, so each tap produces a new
    /// workout). Tests pass a fixed salt for repeatability.
    func regenerateToday(memory: TrainingMemory,
                         today: Date = Date(),
                         salt: String? = nil) {
        guard var plan = plan else { return }
        let cal = Calendar.current
        guard let idx = plan.days.firstIndex(where: { cal.isDate($0.date, inSameDayAs: today) })
        else { return }

        let day = plan.days[idx]
        guard !day.protected else { return }
        guard day.kind == .lift else { return }

        let profile = DemographicProfile.from(memory)
        let saltValue = salt ?? String(Int(Date().timeIntervalSince1970))
        let seed = "\(memory.planInputsHash)-regen-\(saltValue)"
        let recentIds = recentPicks?.recentlyPickedIds() ?? []
        let context = buildGeneratorContext(memory: memory, today: today)

        // Re-derive this lift's index so push/pull/legs rotation stays
        // coherent if the user has multiple lifts in the week.
        let liftDays = plan.days.filter { $0.kind == .lift }
        let liftIndex = liftDays.firstIndex(where: { cal.isDate($0.date, inSameDayAs: today) }) ?? 0
        let workout = WorkoutGenerator.generateLift(
            liftIndex: liftIndex,
            totalLifts: liftDays.count,
            memory: memory,
            profile: profile,
            hashSeed: seed,
            recentlyPicked: recentIds,
            context: context
        )

        plan.days[idx].generatedWorkout = workout
        plan.days[idx].title = workout.title
        plan.days[idx].routineId = nil
        plan.days[idx].generatedReason = workout.provenance

        // NOTE: do NOT touch inputsHash here — only one day was regenerated.
        // If memory has drifted since the last full generate, the other six
        // days are still stale and the drift banner must keep firing.
        self.plan = plan
        savePlan()
        recentPicks?.record(exerciseIds: workout.exercises.map(\.exerciseId))
    }

    /// Regenerate the full week against current memory. Convenience alias for
    /// `generate(from:)` named for the drift-resolution UI surfaces.
    @discardableResult
    func regenerateWeek(memory: TrainingMemory, today: Date = Date()) -> WeekPlan {
        generate(from: memory, today: today)
    }

    /// Which constraint blocked `consolidateWeek` from applying. Threaded to
    /// the Today no-op alert so the user sees why the week couldn't absorb
    /// the missed work.
    enum ConsolidationDecline {
        /// The 1/week consolidation budget is already spent.
        case weeklyCapMet
        /// Fewer than 2 future unprotected lift days — nothing to merge down.
        case notEnoughLiftDays
        /// A remaining day's focus couldn't be recovered, so merging would
        /// risk dropping coverage.
        case unrecoverableFocus
    }

    /// D3 — consolidate the remaining week onto fewer lift days after a missed
    /// workout the reshuffle engine couldn't place (gated upstream by
    /// `MissedWorkoutAutopilot.shouldOfferConsolidation`). Returns true when
    /// it applied. Thin wrapper over `consolidateWeekDetailed` for callers
    /// that don't need the no-op reason.
    @discardableResult
    func consolidateWeek(memory: TrainingMemory,
                         today: Date = Date(),
                         calendar: Calendar = .current) -> Bool {
        consolidateWeekDetailed(memory: memory, today: today, calendar: calendar) == nil
    }

    /// Drops one future lift day and grafts its focus onto a survivor: the
    /// today-onward lift days are re-planned to N-1 via `WeekConsolidator`,
    /// each survivor is regenerated as a (possibly merged) workout via
    /// `WorkoutGenerator.generateConsolidated`, and the surplus day drops to
    /// rest. Direct-mutation + savePlan, mirroring `regenerateToday` (the
    /// `PlanEdit` seam has no set-workout op). Gated by the 1/week cap.
    /// Returns nil when it applied, else the constraint that blocked it.
    func consolidateWeekDetailed(memory: TrainingMemory,
                                 today: Date = Date(),
                                 calendar: Calendar = .current) -> ConsolidationDecline? {
        guard midWeekConsolidationCount < Self.weeklyConsolidationCap else { return .weeklyCapMet }
        guard var plan = plan else { return .notEnoughLiftDays }
        let todayStart = calendar.startOfDay(for: today)

        // Future lift days (today onward, unprotected), in date order.
        let futureLiftIdx = plan.days.indices
            .filter { plan.days[$0].kind == .lift
                && calendar.startOfDay(for: plan.days[$0].date) >= todayStart
                && !plan.days[$0].protected }
            .sorted { plan.days[$0].date < plan.days[$1].date }
        guard futureLiftIdx.count >= 2 else { return .notEnoughLiftDays }   // need ≥2 to drop one

        // Recover each day's actual focus (persisted on the workout). Bail if
        // any is missing — re-deriving would risk era-splitPreference drift.
        let focuses = futureLiftIdx.compactMap { plan.days[$0].generatedWorkout?.focus }
        guard focuses.count == futureLiftIdx.count else { return .unrecoverableFocus }

        let target = futureLiftIdx.count - 1
        let consolidated = WeekConsolidator.consolidate(focuses, to: target)
        guard consolidated.count == target else { return .unrecoverableFocus }

        let profile = DemographicProfile.from(memory)
        let recentIds = recentPicks?.recentlyPickedIds() ?? []
        let context = buildGeneratorContext(memory: memory, today: today)
        var pickedIds: [Int] = []

        // First `target` future lift days take the (merged) consolidated workouts.
        for (i, cday) in consolidated.enumerated() {
            let dayIdx = futureLiftIdx[i]
            let seed = "\(memory.planInputsHash)-consolidate-\(i)"
            let workout = WorkoutGenerator.generateConsolidated(
                cday, liftIndex: i, totalLifts: target, memory: memory,
                profile: profile, hashSeed: seed, recentlyPicked: recentIds,
                context: context)
            plan.days[dayIdx].generatedWorkout = workout
            plan.days[dayIdx].title = workout.title
            plan.days[dayIdx].routineId = nil
            plan.days[dayIdx].generatedReason = workout.provenance
            pickedIds.append(contentsOf: workout.exercises.map(\.exerciseId))
        }
        // Surplus future lift day(s) → rest.
        for j in target..<futureLiftIdx.count {
            let dayIdx = futureLiftIdx[j]
            plan.days[dayIdx].kind = .rest
            plan.days[dayIdx].generatedWorkout = nil
            plan.days[dayIdx].title = "Rest"
            plan.days[dayIdx].routineId = nil
            plan.days[dayIdx].generatedReason = nil
        }

        self.plan = plan
        savePlan()
        if !pickedIds.isEmpty { recentPicks?.record(exerciseIds: pickedIds) }
        midWeekConsolidationCount += 1
        saveConsolidationCount(now: today)
        return nil
    }

    /// One-shot schema migration for users upgrading from build ≤35 whose
    /// saved plan was composed by the old routine-picker (DayPlan has
    /// `routineId` set but no `generatedWorkout`). The new planner generates
    /// workouts exercise-by-exercise; without this migration, those users
    /// would keep seeing the bundled routine that was picked under the old
    /// schema (often a sport-themed routine like "Basketball Vertical Jump
    /// Development" that has nothing to do with their actual sport
    /// selection — the old picker matched by goal only).
    ///
    /// Triggers when ANY lift day in the current plan lacks a
    /// generatedWorkout. No-op for fresh installs, post-migration plans,
    /// and rest-only weeks. User-pinned routines via dayOverrides survive
    /// because overrides live in WeekOverrides, not the WeekPlan.
    func migrateIfStale(memory: TrainingMemory, today: Date = Date()) {
        guard let plan = plan else { return }
        let needsLegacyRegen = plan.days.contains { day in
            day.kind == .lift && day.generatedWorkout == nil
        }
        // Plans built before build 78 used a rolling 7-days-starting-today
        // window. Detect those by checking whether day[0] is the Monday of
        // its own week, and regen to a Mon→Sun calendar week.
        let firstDate = plan.days.first?.date
        let needsCalendarWeekRegen: Bool = {
            guard let firstDate else { return false }
            var cal = Calendar.current
            cal.firstWeekday = 2
            let monday = firstDate.startOfTrainingWeek(calendar: cal)
            return !cal.isDate(firstDate, inSameDayAs: monday)
        }()
        guard needsLegacyRegen || needsCalendarWeekRegen else { return }
        generate(from: memory, today: today)
    }

    // MARK: - Persistence

    func savePlan() {
        guard let plan else {
            defaults.removeObject(forKey: Self.planKey)
            return
        }
        if let data = try? Self.encoder().encode(plan) {
            defaults.set(data, forKey: Self.planKey)
        }
    }

    func saveOverrides() {
        if let data = try? Self.encoder().encode(overrides) {
            defaults.set(data, forKey: Self.overridesKey)
        }
    }

    /// PR 4 — persist the rolling history. Empty list still writes (vs
    /// removeObject) so the load path can distinguish "no history yet"
    /// from "history was cleared by Start Over".
    func savePastPlans() {
        if let data = try? Self.encoder().encode(pastPlans) {
            defaults.set(data, forKey: Self.pastPlansKey)
        }
    }

    /// PR 7 — persist the rolling validation-override log.
    func savePlanOverrides() {
        if let data = try? Self.encoder().encode(recentPlanOverrides) {
            defaults.set(data, forKey: Self.planOverridesKey)
        }
    }

    /// PR 8 — persist the rolling missed-workout log.
    func saveMissedWorkouts() {
        if let data = try? Self.encoder().encode(missedWorkouts) {
            defaults.set(data, forKey: Self.missedWorkoutsKey)
        }
    }

    /// PR 8 — persist the per-week reshuffle counter. Tagged with
    /// the current training-week Monday so we know to reset when
    /// the week rolls over.
    func saveReshuffleCount(now: Date = Date()) {
        defaults.set(midWeekReshuffleCount, forKey: Self.reshuffleCountKey)
        defaults.set(now.startOfTrainingWeek(), forKey: Self.reshuffleWeekKey)
    }

    /// D3 — persist the per-week consolidation counter, tagged with the
    /// training-week Monday so it resets on rollover (same as reshuffle).
    private func saveConsolidationCount(now: Date = Date()) {
        defaults.set(midWeekConsolidationCount, forKey: Self.consolidationCountKey)
        defaults.set(now.startOfTrainingWeek(), forKey: Self.consolidationWeekKey)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
