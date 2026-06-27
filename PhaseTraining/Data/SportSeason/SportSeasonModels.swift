// SportSeasonModels.swift — core vocabulary for the season-aware generator.
//
// The organizing primitive is the phase of the sport season, not a generic
// goal. These three enums + the SetScheme value type are the shared language
// every other SportSeason file speaks:
//
//   Demand          — a trainable quality a movement develops (the slot axis).
//   SportVariant    — sub-discipline that shifts demand weighting + filters.
//   ProgressionMode — how load/reps move session-to-session within a phase.
//   SetScheme       — the prescription for one movement in one phase.
//
// String-backed so they round-trip the `sport_movements` seed JSON
// (db/source/sport_movements.json) without a translation layer: the seed's
// `demands`/`allowed_variants` strings are these rawValues verbatim.

import Foundation

// MARK: - Demand

/// A trainable quality, sport-tagged so the movement pool stays curated
/// (SPEC §2). Skiing demands are live at M1; climbing demands are defined now
/// (so the seed + eval can reference them) but unused until M3.
enum Demand: String, Codable, CaseIterable, Hashable {
    // shared
    case maxStrength
    case power
    case core
    case prehab
    case aerobicUphill
    // skiing-leaning
    case eccentricLeg
    case legEndurance
    case kneeStability
    case hipLateral
    // climbing-leaning (M3)
    case fingerStrength
    case pullStrength
    case bodyTension
    case contactStrength
    case pullEndurance
    case antagonist
}

// MARK: - SportVariant

/// Sub-discipline within a sport. Changes demand weighting (PhaseRule variant
/// overrides) and movement filters (SPEC §2/§3.4/§4.4). M1 default `.inbounds`.
enum SportVariant: String, Codable, CaseIterable, Hashable {
    // skiing
    case inbounds
    case backcountry
    case skimo
    case park
    // climbing (M3)
    case boulder
    case sportRoute
    case tradAlpine
}

// MARK: - ProgressionMode

/// How the generator adjusts load/reps session-to-session within a phase
/// (SPEC §2). Exactly the spec's four cases — `eventPrep` reuses
/// `autoregulateHold` and lets the existing `MesocycleProgression` taper/peak
/// logic (daysUntilPeak-gated) drive the countdown, so there is no `.taper`.
enum ProgressionMode: String, Codable, Hashable {
    case progressiveOverload  // add load/reps when performance allows (off-season)
    case autoregulateHold     // hold loads, regulate by readiness (pre-season / eventPrep)
    case maintainMinimal      // lightest dose that preserves strength (in-season)
    case deload               // intentional reduction (transition)
}

// MARK: - SetScheme

/// The prescription for one movement in one phase (SPEC §2). Decoded from the
/// seed's `default_scheme_by_phase` JSON, then flattened by the generator into
/// `GeneratedExercise`'s string fields. `fatigueCost` (1 low … 5 high) is the
/// in-season volume-cap currency; it is summed inside the generator and never
/// written to the persisted `GeneratedExercise`.
struct SetScheme: Codable, Hashable {
    var setsLow: Int
    var setsHigh: Int
    /// nil for timed / isometric movements (use `holdSeconds`).
    var repsLow: Int?
    var repsHigh: Int?
    var holdSeconds: Int?
    var intensityRPELow: Int?
    var intensityRPEHigh: Int?
    var pctOneRMLow: Int?
    var pctOneRMHigh: Int?
    /// Seconds of the eccentric (lowering) phase, e.g. 4 for a 4s ski-braking
    /// tempo. Flattened to a 4-digit `tempo` string ("4-0-1-0").
    var eccentricTempoSeconds: Int?
    var restSeconds: Int
    /// 1 (low) … 5 (high). Drives the in-season fatigue ceiling.
    var fatigueCost: Int

    /// "4-6", "5", or "45-90s hold" — the `GeneratedExercise.reps` string.
    var repsString: String {
        if let hold = holdSeconds {
            return "\(hold)s hold"
        }
        guard let lo = repsLow else { return "—" }
        if let hi = repsHigh, hi != lo { return "\(lo)-\(hi)" }
        return "\(lo)"
    }

    /// "6-7" / "8" / nil — the `GeneratedExercise.rpe` string.
    var rpeString: String? {
        guard let lo = intensityRPELow else { return nil }
        if let hi = intensityRPEHigh, hi != lo { return "\(lo)-\(hi)" }
        return "\(lo)"
    }

    /// 4-digit eccentric-emphasis tempo ("4-0-1-0") or nil when unset.
    var tempoString: String? {
        guard let ecc = eccentricTempoSeconds else { return nil }
        return "\(ecc)-0-1-0"
    }

    /// Midpoint of the set range, used when a single set count is needed.
    var setsMid: Int { (setsLow + setsHigh) / 2 }
}

// MARK: - SportMovement

/// A curated pool entry (one `sport_movements` row joined with its catalog
/// exercise). The season-specific axes (demands/phases/variants/fatigueCost)
/// come from the seed; name + scheme + compound/unilateral come from the
/// catalog. Produced by `CoachDatabase.sportMovements(sport:)`.
struct SportMovement: Hashable, Identifiable {
    let exerciseId: Int
    var id: Int { exerciseId }
    let name: String
    let catalogSlug: String
    let demands: [Demand]                 // primary first
    let allowedPhases: [SeasonPhase]
    let allowedVariants: [SportVariant]?  // nil = all variants of the sport
    let fatigueCost: Int
    let minExperienceRank: Int            // 0 novice … 2 advanced
    let injuryCaution: String?
    // Joined catalog scheme
    let isCompound: Bool
    let isUnilateral: Bool
    let defaultSets: Int
    let defaultReps: String
    let defaultRestSeconds: Int
    let defaultTempo: String?

    var primaryDemand: Demand? { demands.first }
    func serves(_ demand: Demand) -> Bool { demands.contains(demand) }
    func allowed(in phase: SeasonPhase) -> Bool { allowedPhases.contains(phase) }
    func allowed(for variant: SportVariant) -> Bool {
        guard let v = allowedVariants else { return true }
        return v.contains(variant)
    }

    /// Parse a catalog `default_rest` string ("2 min", "90 sec", "2-3 min")
    /// into seconds. Takes the low end of a range; defaults to 90s.
    static func parseRestSeconds(_ raw: String?) -> Int {
        guard let raw = raw?.lowercased() else { return 90 }
        let firstNum = raw.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
        guard let n = firstNum else { return 90 }
        return raw.contains("min") ? n * 60 : n
    }
}
