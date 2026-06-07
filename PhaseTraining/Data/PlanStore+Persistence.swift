// PlanStore+Persistence.swift
//
// Extracted from PlanStore.swift (Tier-3 god-object split). Persistence: the
// save* family + the shared JSON coder factories (secondsSince1970 dates).
// Lifecycle (init/reload), generation-context plumbing, PlanEdit/regeneration
// stay in PlanStore.swift.
//
// Access notes from the split: `saveConsolidationCount`, `encoder()` and
// `decoder()` were `private` when this lived in PlanStore.swift; they're
// `internal` now because their callers (consolidateWeekDetailed; init /
// reloadFromDefaults / apply) stayed in the core file. The pt_* key constants
// remain declared in PlanStore.swift (internal) — never rename their string
// values, they're persisted.

import Foundation

extension PlanStore {
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
    func saveConsolidationCount(now: Date = Date()) {
        defaults.set(midWeekConsolidationCount, forKey: Self.consolidationCountKey)
        defaults.set(now.startOfTrainingWeek(), forKey: Self.consolidationWeekKey)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
