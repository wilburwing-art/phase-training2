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
    /// Upper-body pull/press strength. Added 2026-09-04 from the owner's own
    /// off-season program (shralpinism: Press 3x5 @ RPE 7; Weighted Pull-Ups
    /// 5 x 3 rounds), which the 44-row ski pool had none of, so a skier's
    /// off-season "muscle base" was legs and trunk only.
    case upperStrength
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

    /// Human wording for a demand, used where a session has to explain itself
    /// to the athlete (R3-2). Only the demands that can appear in that copy
    /// need an entry; the rest fall back to the raw value.
    var plainLabel: String {
        switch self {
        case .fingerStrength: return "finger"
        case .eccentricLeg:   return "eccentric leg"
        case .upperStrength:  return "upper body"
        case .maxStrength:    return "max strength"
        default:              return rawValue
        }
    }
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
    /// Explosive concentric (power / contact work) — flattens to "2-0-X-0".
    /// Takes precedence over `eccentricTempoSeconds` in `tempoString`.
    var explosiveConcentric: Bool
    var restSeconds: Int
    /// 1 (low) … 5 (high). Drives the in-season fatigue ceiling.
    var fatigueCost: Int

    /// Keyword init with sane defaults so a `DemandScheme` row only spells out
    /// the fields that matter for that demand.
    init(setsLow: Int, setsHigh: Int,
         repsLow: Int? = nil, repsHigh: Int? = nil, holdSeconds: Int? = nil,
         intensityRPELow: Int? = nil, intensityRPEHigh: Int? = nil,
         pctOneRMLow: Int? = nil, pctOneRMHigh: Int? = nil,
         eccentricTempoSeconds: Int? = nil, explosiveConcentric: Bool = false,
         restSeconds: Int, fatigueCost: Int = 2) {
        self.setsLow = setsLow
        self.setsHigh = setsHigh
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.holdSeconds = holdSeconds
        self.intensityRPELow = intensityRPELow
        self.intensityRPEHigh = intensityRPEHigh
        self.pctOneRMLow = pctOneRMLow
        self.pctOneRMHigh = pctOneRMHigh
        self.eccentricTempoSeconds = eccentricTempoSeconds
        self.explosiveConcentric = explosiveConcentric
        self.restSeconds = restSeconds
        self.fatigueCost = fatigueCost
    }

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

    /// 4-digit tempo: explosive ("2-0-X-0") wins, then eccentric-emphasis
    /// ("4-0-1-0"), else nil when unset.
    var tempoString: String? {
        if explosiveConcentric { return "2-0-X-0" }
        guard let ecc = eccentricTempoSeconds else { return nil }
        return "\(ecc)-0-1-0"
    }

    /// Midpoint of the set range, used when a single set count is needed.
    var setsMid: Int { (setsLow + setsHigh) / 2 }

    /// Apply a phase's progression to this base band. Volume + intensity move;
    /// the demand's rep/tempo character is preserved. Folds in the logic the
    /// generator used before demand schemes (`progressedSets` + `rpe(for:)`).
    func modulated(by mode: ProgressionMode) -> SetScheme {
        var s = self
        switch mode {
        case .progressiveOverload, .autoregulateHold:
            break                                    // full dose / autoregulated hold
        case .maintainMinimal:
            s.setsLow = max(1, s.setsLow - 1)
            s.setsHigh = max(s.setsLow, s.setsHigh - 1)
            s.shiftRPE(by: -1)
        case .deload:
            s.setsHigh = max(1, s.setsLow - 1)
            s.setsLow = s.setsHigh
            s.shiftRPE(by: -2)
        }
        return s
    }

    /// Nudge the RPE band by `delta`, floored at 5 (nothing below light-moderate).
    private mutating func shiftRPE(by delta: Int) {
        if let lo = intensityRPELow { intensityRPELow = max(5, lo + delta) }
        if let hi = intensityRPEHigh { intensityRPEHigh = max(intensityRPELow ?? 5, hi + delta) }
    }
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
    // Joined catalog facts (the prescription itself is demand-driven — see
    // DemandScheme — so the catalog's generic sets/reps/rest/tempo are not read).
    let isCompound: Bool
    let isUnilateral: Bool
    /// A cited protocol that overrides the demand scheme's sets, reps and rest
    /// when present (R3-9). Nil for the ordinary movement, which is most of them.
    var protocolSets: Int? = nil
    var protocolReps: String? = nil
    var protocolRestSeconds: Int? = nil

    var primaryDemand: Demand? { demands.first }
    func serves(_ demand: Demand) -> Bool { demands.contains(demand) }
    func allowed(in phase: SeasonPhase) -> Bool { allowedPhases.contains(phase) }
    func allowed(for variant: SportVariant) -> Bool {
        guard let v = allowedVariants else { return true }
        return v.contains(variant)
    }
}
