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

    @Published var plan: WeekPlan?
    @Published var overrides: WeekOverrides

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

    /// Memory feed for the auto-regen subscription (build 69+). When set,
    /// PlanStore observes the published memory and silently regenerates the
    /// week whenever the user's profile changes enough to drift
    /// `planInputsHash`. The drift banner UI on Today / Week / Profile got
    /// removed in the same change — what used to be "tap to refresh" is
    /// now invisible.
    weak var memoryStore: MemoryStore? {
        didSet { resubscribeToMemory() }
    }

    private let defaults: UserDefaults
    private var memorySubscription: AnyCancellable?

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
    }

    // MARK: - Generation

    /// Generate a fresh plan from memory + the current overrides; persist both.
    @discardableResult
    func generate(from memory: TrainingMemory, today: Date = Date()) -> WeekPlan {
        let routines = CoachDatabase.shared.listRoutines()
        let context = buildGeneratorContext(memory: memory, today: today)
        let p = Planner.generate(
            memory: memory,
            overrides: overrides,
            routines: routines,
            recentlyPicked: recentPicks?.recentlyPickedIds() ?? [],
            today: today,
            context: context
        )
        self.plan = p
        savePlan()
        recordPickedExercises(in: p)
        return p
    }

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

    /// Derive the runtime-history context for the planner. Returns `.empty`
    /// when sessionStore isn't wired (tests / previews) — same shape as
    /// pre-build-66 so the planner output stays unchanged in those paths.
    private func buildGeneratorContext(memory: TrainingMemory, today: Date) -> GeneratorContext {
        guard let sessionStore else { return .empty }
        return GeneratorContext.from(
            sessions: sessionStore.savedSessions,
            soreness: memory.soreness,
            feedback: memory.feedback,
            now: today
        )
    }

    /// Stamp every exercise the generator just picked into the variety
    /// memory so the next regen avoids them.
    private func recordPickedExercises(in plan: WeekPlan) {
        guard let recentPicks else { return }
        let ids = plan.days
            .compactMap(\.generatedWorkout)
            .flatMap(\.exercises)
            .map(\.exerciseId)
        recentPicks.record(exerciseIds: ids)
    }

    /// Replace the current plan wholesale (used when the user accepts a
    /// preview during onboarding).
    func setPlan(_ p: WeekPlan) {
        self.plan = p
        savePlan()
    }

    /// Wipe everything — dev / "Start over" flows.
    func clear() {
        plan = nil
        overrides = WeekOverrides(weekStart: Date().startOfTrainingWeek())
        defaults.removeObject(forKey: Self.planKey)
        defaults.removeObject(forKey: Self.overridesKey)
    }

    // MARK: - Per-week overrides

    /// Mutate + persist overrides; auto-regenerate the plan when memory is provided.
    func updateOverrides(memory: TrainingMemory? = nil,
                         today: Date = Date(),
                         _ block: (inout WeekOverrides) -> Void) {
        block(&overrides)
        saveOverrides()
        if let memory {
            generate(from: memory, today: today)
        }
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
        if let data = try? Self.encoder().encode(diff.after) {
            defaults.set(data, forKey: Self.planKey)
        }
        plan = diff.after
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
        current.days[idx].generatedWorkout = diff.after
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
            plan.days[idx].routineId = (to == .lift || to == .mobility) ? routineId : nil
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
                plan.days[idx].routineId = (kind == .lift || kind == .mobility) ? routineId : nil
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
        guard day.kind == .lift || day.kind == .mobility else { return }

        let profile = DemographicProfile.from(memory)
        let saltValue = salt ?? String(Int(Date().timeIntervalSince1970))
        let seed = "\(memory.planInputsHash)-regen-\(saltValue)"
        let recentIds = recentPicks?.recentlyPickedIds() ?? []
        let context = buildGeneratorContext(memory: memory, today: today)

        let workout: GeneratedWorkout
        switch day.kind {
        case .lift:
            // Re-derive this lift's index so push/pull/legs rotation stays
            // coherent if the user has multiple lifts in the week.
            let liftDays = plan.days.filter { $0.kind == .lift }
            let liftIndex = liftDays.firstIndex(where: { cal.isDate($0.date, inSameDayAs: today) }) ?? 0
            workout = WorkoutGenerator.generateLift(
                liftIndex: liftIndex,
                totalLifts: liftDays.count,
                memory: memory,
                profile: profile,
                hashSeed: seed,
                recentlyPicked: recentIds,
                context: context
            )
        case .mobility:
            workout = WorkoutGenerator.generateMobility(
                memory: memory,
                profile: profile,
                hashSeed: seed,
                recentlyPicked: recentIds,
                context: context
            )
        default:
            return
        }

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

    /// One-shot schema migration for users upgrading from build ≤35 whose
    /// saved plan was composed by the old routine-picker (DayPlan has
    /// `routineId` set but no `generatedWorkout`). The new planner generates
    /// workouts exercise-by-exercise; without this migration, those users
    /// would keep seeing the bundled routine that was picked under the old
    /// schema (often a sport-themed routine like "Basketball Vertical Jump
    /// Development" that has nothing to do with their actual sport
    /// selection — the old picker matched by goal only).
    ///
    /// Triggers when ANY lift / mobility day in the current plan lacks a
    /// generatedWorkout. No-op for fresh installs, post-migration plans,
    /// and rest-only weeks. User-pinned routines via dayOverrides survive
    /// because overrides live in WeekOverrides, not the WeekPlan.
    func migrateIfStale(memory: TrainingMemory, today: Date = Date()) {
        guard let plan = plan else { return }
        let needsLegacyRegen = plan.days.contains { day in
            (day.kind == .lift || day.kind == .mobility) && day.generatedWorkout == nil
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

    private func savePlan() {
        guard let plan else {
            defaults.removeObject(forKey: Self.planKey)
            return
        }
        if let data = try? Self.encoder().encode(plan) {
            defaults.set(data, forKey: Self.planKey)
        }
    }

    private func saveOverrides() {
        if let data = try? Self.encoder().encode(overrides) {
            defaults.set(data, forKey: Self.overridesKey)
        }
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
