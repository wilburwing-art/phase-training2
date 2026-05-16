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

    private let defaults: UserDefaults

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
        let p = Planner.generate(
            memory: memory,
            overrides: overrides,
            routines: routines,
            today: today
        )
        self.plan = p
        savePlan()
        return p
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
    func apply(_ diff: PlanDiff) {
        guard !diff.isNoop else { return }
        plan = diff.after
        savePlan()
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
