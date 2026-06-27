// AthleteState.swift — the season-aware generator's input, assembled (not
// persisted) from the live `TrainingMemory` + the derived `DemographicProfile`.
//
// SPEC §2 defines `AthleteState` as a fresh struct; here it is an ADAPTER so we
// reuse the app's existing derivations instead of duplicating them:
//   - equipment / injury contraindication / difficulty / environment come from
//     `DemographicProfile.from(memory)` (which already bridges the Equipment
//     enum → coach.db slugs and resolves injury → contraindicated exercise ids).
//   - season comes from `memory.seasonForPlanner`; the objective date from
//     `memory.peakDate`; recent picks are threaded in by the caller
//     (`RecentPicksStore.recentlyPickedIds`) so the generator stays pure.

import Foundation

extension ExperienceLevel {
    /// Ordering for `sport_movements.min_experience` gating
    /// (SPEC `Experience{novice,intermediate,advanced}`; beginner ↔ novice).
    var seasonRank: Int {
        switch self {
        case .beginner:     return 0
        case .intermediate: return 1
        case .advanced:     return 2
        }
    }

    /// Parse a seed `min_experience` token ("novice"/"intermediate"/"advanced").
    static func seasonRank(forSeedToken token: String) -> Int {
        switch token.lowercased() {
        case "novice", "beginner": return 0
        case "intermediate":       return 1
        case "advanced":           return 2
        default:                   return 0
        }
    }
}

struct AthleteState: Equatable {
    let sportSlug: String
    let variant: SportVariant
    let experience: ExperienceLevel
    let season: SeasonPhase

    /// coach.db equipment slugs the athlete can use (any-of per movement,
    /// SPEC §5). Sourced from `DemographicProfile.allowedEquipmentSlugs`.
    let availableEquipmentSlugs: Set<String>
    let sessionsPerWeek: Int

    /// Set for `.eventPrep` (a trip / objective); drives the taper countdown
    /// via `MesocycleProgression`. nil ⇒ no peak.
    let targetObjectiveDate: Date?
    /// 1-indexed week inside the current phase (determinism + mesocycle).
    let weekNumber: Int

    /// Exercise ids picked in the recent window — deprioritized for rotation
    /// (SPEC `recentMovementIDs`). Threaded in by the caller; [] in eval.
    let recentMovementIDs: Set<Int>

    /// Exercise ids contraindicated by the athlete's injuries (already resolved
    /// by `DemographicProfile`) — subtracted from every pool.
    let contraindicatedExerciseIDs: Set<Int>
    /// Demands a flagged injury zeroes; their weight is redistributed to
    /// antagonist/prehab (SPEC §5 `applyInjuryRedistribution`). Empty for
    /// skiing M1 (mechanism encoded; the finger-injury case is M3/climbing).
    let flaggedDemands: Set<Demand>

    /// The full derived profile, kept for the selection filters the generator
    /// shares with the legacy path (difficulties, environments, exclusions).
    let profile: DemographicProfile

    // MARK: - Adapter

    /// Build from live memory. `variant` defaults to `.inbounds` until the M4
    /// variant UI lands; `recentMovementIDs`/`weekNumber` are threaded by the
    /// caller so the generator is deterministic and pure.
    static func from(
        _ memory: TrainingMemory,
        variant: SportVariant = .inbounds,
        weekNumber: Int = 1,
        recentMovementIDs: Set<Int> = []
    ) -> AthleteState {
        let profile = DemographicProfile.from(memory)
        return AthleteState(
            sportSlug: memory.primarySport?.slug ?? "general-fitness",
            variant: variant,
            experience: memory.experience,
            season: memory.seasonForPlanner,
            availableEquipmentSlugs: profile.allowedEquipmentSlugs,
            sessionsPerWeek: memory.liftDaysPerWeek,
            targetObjectiveDate: memory.peakDate,
            weekNumber: weekNumber,
            recentMovementIDs: recentMovementIDs,
            contraindicatedExerciseIDs: profile.excludedExerciseIds,
            flaggedDemands: [],
            profile: profile
        )
    }
}
