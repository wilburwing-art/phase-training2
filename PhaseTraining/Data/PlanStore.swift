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
