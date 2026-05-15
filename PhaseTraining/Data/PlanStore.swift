// PlanStore.swift — @Published wrapper around the active WeekPlan.
// Persists under UserDefaults key `pt_week_plan` with the same date strategy
// as MemoryStore / SessionStore (secondsSince1970).
//
// Calls Planner.generate at the end of onboarding and on weekly check-in. The
// routine catalog is loaded from CoachDatabase.shared at generate-time so the
// Planner stays a pure function (easier to unit-test without coach.db).

import Foundation
import Combine

final class PlanStore: ObservableObject {
    private static let key = "pt_week_plan"

    @Published var plan: WeekPlan?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let p = try? Self.decoder().decode(WeekPlan.self, from: data) {
            self.plan = p
        } else {
            self.plan = nil
        }
    }

    // MARK: - Generation

    /// Generate a new plan from the given memory and persist it. Loads the
    /// routine catalog from CoachDatabase.shared.
    @discardableResult
    func generate(from memory: TrainingMemory, today: Date = Date()) -> WeekPlan {
        let routines = CoachDatabase.shared.listRoutines()
        let p = Planner.generate(memory: memory, routines: routines, today: today)
        self.plan = p
        save()
        return p
    }

    /// Replace the current plan wholesale (used when the user accepts a
    /// preview during onboarding).
    func setPlan(_ p: WeekPlan) {
        self.plan = p
        save()
    }

    /// Wipe — used by reset / "Start over" flows.
    func clear() {
        plan = nil
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Drift detection

    /// True when the persisted plan was generated from inputs that no longer
    /// match the current memory — phase 12 weekly check-in will read this.
    func needsRegeneration(for memory: TrainingMemory) -> Bool {
        guard let plan else { return true }
        return plan.inputsHash != memory.planInputsHash
    }

    // MARK: - Persistence

    func save() {
        guard let plan else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        if let data = try? Self.encoder().encode(plan) {
            defaults.set(data, forKey: Self.key)
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
