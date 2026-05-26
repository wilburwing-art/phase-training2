// ExerciseTaxonomy.swift — Body Part + Equipment Category enums for the
// two-dropdown filter UI (PR 3).
//
// Both taxonomies mirror the structure of the Strong iOS app's exercise
// library so users coming from other tracking apps see the dimensions they
// already think in. Both are derived (not stored) — the SQL DB stores the
// fine-grained slugs (`muscle_groups.slug`, `equipment.slug`, etc.) and we
// project up to these coarser categories at query / display time.
//
// Two responsibilities per enum:
//   1. `members*`: which DB slugs roll into this category. Used at query
//      time to translate a picked category to a WHERE clause.
//   2. `classify(...)`: pure function that takes an exercise's joined slug
//      arrays and returns its single canonical category. Used at display
//      time so each exercise has exactly one BodyPart badge + one
//      Equipment Category badge in the library row.
//
// The source app's categorization is *inconsistent* — Romanian Deadlift
// (Barbell) is filed under Back, Romanian Deadlift (Dumbbell) under Legs,
// same lift. We resolve via a fixed priority order in `classify(...)` so
// our taxonomy is consistent.

import Foundation

// MARK: - BodyPartCategory

/// The 10 body-part buckets the Library filter dropdown surfaces.
/// Order is the display order in the dropdown.
enum BodyPartCategory: String, CaseIterable, Identifiable, Hashable {
    case arms, back, chest, core, legs, shoulders
    case cardio, olympic, fullBody, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arms:      return "Arms"
        case .back:      return "Back"
        case .chest:     return "Chest"
        case .core:      return "Core"
        case .legs:      return "Legs"
        case .shoulders: return "Shoulders"
        case .cardio:    return "Cardio"
        case .olympic:   return "Olympic"
        case .fullBody:  return "Full Body"
        case .other:     return "Other"
        }
    }

    /// `muscle_groups.slug` values that roll up into this category. Drives
    /// the SQL WHERE clause when the user picks this body part. The
    /// non-muscle cases (cardio, olympic, fullBody, other) use modality /
    /// pattern filters instead — see `modalityFilter` / `patternFilter`.
    var memberMuscleSlugs: [String] {
        switch self {
        case .arms:
            return ["arms", "biceps", "brachialis", "brachioradialis", "triceps",
                    "forearm-flexors", "forearm-extensors",
                    "grip-crush", "grip-pinch", "grip-support",
                    "finger-flexors", "finger-extensors"]
        case .back:
            return ["back", "lats", "traps", "upper-traps", "mid-traps", "lower-traps",
                    "rhomboids", "teres-major", "teres-minor",
                    "erector-thoracic", "erector-lumbar", "multifidus",
                    "levator-scapulae"]
        case .chest:
            return ["chest", "pec-major-sternal", "pec-major-clav", "pec-minor",
                    "serratus-anterior"]
        case .core:
            return ["core", "rectus-abdominis", "external-obliques", "internal-obliques",
                    "transverse-abdominis", "quadratus-lumborum", "diaphragm",
                    "pelvic-floor", "hip-flexors", "iliopsoas"]
        case .legs:
            return ["lower-body", "quadriceps", "vastus-medialis", "vastus-lateralis",
                    "vastus-intermedius", "rectus-femoris", "sartorius",
                    "hamstrings", "biceps-femoris", "semitendinosus", "semimembranosus",
                    "glutes", "glute-max", "glute-med", "glute-min",
                    "calves", "gastrocnemius", "soleus", "tib-anterior",
                    "peroneals", "intrinsic-foot", "adductors", "tfl",
                    "piriformis", "hip-rotators"]
        case .shoulders:
            return ["shoulders", "delt-anterior", "delt-lateral", "delt-posterior",
                    "rotator-cuff", "supraspinatus", "infraspinatus",
                    "teres-minor", "subscapularis"]
        case .cardio, .olympic, .fullBody, .other:
            // Non-muscle cases — these use modality / pattern filters.
            return []
        }
    }

    /// Modality column filter (`exercises.modality = ?`). Only used by
    /// `.cardio` (modality=endurance) and `.other` (flexibility / mobility).
    var modalityFilter: String? {
        switch self {
        case .cardio: return "endurance"
        case .other:  return nil  // handled by exclusion — see classify()
        default:      return nil
        }
    }

    /// `movement_patterns.slug` filter. `.olympic` matches any of the Olympic
    /// pattern slugs.
    var patternFilters: [String] {
        switch self {
        case .olympic: return ["olympic-derivative"]
        default:       return []
        }
    }

    // MARK: - classify

    /// Decide the single canonical body part for an exercise given its
    /// joined slug arrays. Priority order resolves multi-fit cases (an
    /// Olympic lift hits legs + back + shoulders muscle-wise; we want one
    /// answer).
    ///
    /// Order:
    ///   1. Cardio (modality=endurance) — most distinctive
    ///   2. Olympic (pattern=olympic-derivative or modality=power)
    ///   3. Full Body (muscles_primary contains "full-body")
    ///   4. Muscle-based: chest > back > shoulders > legs > arms > core
    ///      (the order mirrors the source app's mental hierarchy)
    ///   5. Other (flexibility / mobility / unmatched)
    static func classify(
        modality: String?,
        primaryMuscleSlugs: [String],
        secondaryMuscleSlugs: [String],
        patternSlugs: [String]
    ) -> BodyPartCategory {
        // 1. Cardio
        if modality == "endurance" {
            return .cardio
        }

        // 2. Olympic — pattern is the strongest signal
        if patternSlugs.contains("olympic-derivative") {
            return .olympic
        }
        if modality == "power" {
            return .olympic
        }

        // 3. Full Body
        if primaryMuscleSlugs.contains("full-body") {
            return .fullBody
        }

        // 4. Muscle-based, primary muscles only (secondary is too lossy)
        let primary = Set(primaryMuscleSlugs)
        // Order matters — pick the first match in this priority. Chest before
        // shoulders before back so a bench press (which involves all three)
        // lands in Chest rather than Shoulders.
        let muscleOrder: [BodyPartCategory] = [.chest, .back, .shoulders, .legs, .arms, .core]
        for category in muscleOrder {
            for slug in category.memberMuscleSlugs {
                if primary.contains(slug) {
                    return category
                }
            }
        }

        // 5. Fallback for flexibility / mobility / breathing / unmatched
        return .other
    }
}

// MARK: - EquipmentCategory

/// The 8 equipment / tracking-mode buckets the Library filter dropdown
/// surfaces. Drives both query filtering and the per-exercise badge in
/// list rows.
///
/// Note: these mix equipment families (Barbell, Dumbbell) with logging
/// modes (Reps Only, Duration). That's deliberate — the source app does
/// the same and the values map cleanly to how users think about logging.
enum EquipmentCategory: String, CaseIterable, Identifiable, Hashable {
    case barbell, dumbbell, machineOther
    case weightedBodyweight, assistedBodyweight, repsOnly
    case cardio, duration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell:             return "Barbell"
        case .dumbbell:            return "Dumbbell"
        case .machineOther:        return "Machine / Other"
        case .weightedBodyweight:  return "Weighted Bodyweight"
        case .assistedBodyweight:  return "Assisted Bodyweight"
        case .repsOnly:            return "Reps Only"
        case .cardio:              return "Cardio"
        case .duration:            return "Duration"
        }
    }

    /// `equipment.slug` values that count as belonging to this category.
    /// The classifier walks these in priority order.
    var memberEquipmentSlugs: [String] {
        switch self {
        case .barbell:
            return ["barbell", "ez-bar"]  // ez-bar isn't a current slug; future-proofing.
        case .dumbbell:
            return ["dumbbells"]
        case .machineOther:
            // Catch-all for machines + specialty implements. Anything not in
            // barbell/dumbbell/bodyweight buckets ends up here.
            return ["cable-machine", "smith-machine", "leg-press", "leg-curl-machine",
                    "leg-extension", "lat-pulldown", "cable-crossover",
                    "ghd", "reverse-hyper", "hip-ad-ab-machine", "hack-squat",
                    "belt-squat", "chest-press-machine", "shoulder-press-machine",
                    "iso-lateral-machine", "preacher-bench", "captains-chair",
                    "torso-rotation-machine", "shrug-machine", "glute-kickback-machine",
                    "back-extension-machine", "bicep-curl-machine",
                    "tricep-extension-machine", "pec-deck",
                    "kettlebell", "medicine-ball", "sandbag", "slam-ball",
                    "landmine", "weight-plates", "clubbell-mace",
                    "battle-ropes", "trap-bar",
                    "balance-board", "bosu-ball", "stability-ball",
                    "ab-wheel", "suspension-trainer"]
        case .weightedBodyweight:
            return ["pull-up-bar", "dip-station", "parallettes", "gymnastic-rings",
                    "weight-vest"]
        case .assistedBodyweight:
            return ["band-light", "band-medium", "band-heavy", "mini-band"]
        case .repsOnly:
            return ["bodyweight"]
        case .cardio:
            return ["jump-rope", "cycling-trainer", "rowing-erg", "ski-erg",
                    "paddle-erg", "treadmill", "elliptical", "stair-climber",
                    "assault-bike", "swim-cords"]
        case .duration:
            // Duration is mostly modality-driven (timed holds) — no
            // exclusive equipment slugs. Classifier handles via modality
            // / default_duration.
            return []
        }
    }

    // MARK: - classify

    /// Decide the canonical equipment category for an exercise. Priority:
    ///   1. Cardio  — modality=endurance OR cardio equipment slug
    ///   2. Duration — modality=flexibility / mobility / hold (no reps)
    ///   3. Barbell  — has a barbell-family slug
    ///   4. Dumbbell — has dumbbells (and not barbell)
    ///   5. Machine / Other — has machine-family or specialty equipment
    ///   6. Weighted Bodyweight — bodyweight + pull-up-bar / weight-vest / etc.
    ///   7. Assisted Bodyweight — bodyweight + band
    ///   8. Reps Only — bodyweight alone
    static func classify(
        modality: String?,
        defaultReps: String?,
        defaultDuration: String?,
        equipmentSlugs: [String]
    ) -> EquipmentCategory {
        let equip = Set(equipmentSlugs)

        // 1. Cardio
        if modality == "endurance" {
            return .cardio
        }
        if !equip.intersection(EquipmentCategory.cardio.memberEquipmentSlugs).isEmpty {
            return .cardio
        }

        // 2. Duration — anything that is fundamentally a timed hold
        if modality == "flexibility" {
            return .duration
        }
        // No default_reps but has default_duration → timed work
        let hasReps = !(defaultReps ?? "").isEmpty
        let hasDuration = !(defaultDuration ?? "").isEmpty
        if hasDuration && !hasReps {
            return .duration
        }

        // 3. Barbell
        if !equip.intersection(EquipmentCategory.barbell.memberEquipmentSlugs).isEmpty {
            return .barbell
        }

        // 4. Dumbbell (only if not barbell)
        if !equip.intersection(EquipmentCategory.dumbbell.memberEquipmentSlugs).isEmpty {
            return .dumbbell
        }

        // 5. Machine / Other
        if !equip.intersection(EquipmentCategory.machineOther.memberEquipmentSlugs).isEmpty {
            return .machineOther
        }

        // 6. Weighted Bodyweight
        if !equip.intersection(EquipmentCategory.weightedBodyweight.memberEquipmentSlugs).isEmpty {
            return .weightedBodyweight
        }

        // 7. Assisted Bodyweight
        if !equip.intersection(EquipmentCategory.assistedBodyweight.memberEquipmentSlugs).isEmpty {
            return .assistedBodyweight
        }

        // 8. Reps Only — bodyweight alone, or no equipment at all
        return .repsOnly
    }
}

// MARK: - Convenience: apply to ExerciseFilters

extension ExerciseFilters {
    /// Translate a picked BodyPartCategory + EquipmentCategory into the
    /// existing ExerciseFilters fields. Used by the new two-dropdown UI
    /// (PR 3) so the SQL query layer doesn't need new params.
    static func from(
        bodyPart: BodyPartCategory? = nil,
        equipment: EquipmentCategory? = nil,
        baseFilters: ExerciseFilters = ExerciseFilters()
    ) -> (filters: ExerciseFilters, muscleSlugs: [String], equipmentSlugs: [String], patternSlugs: [String]) {
        var filters = baseFilters
        var muscleSlugs: [String] = []
        var equipmentSlugs: [String] = []
        var patternSlugs: [String] = []

        if let bp = bodyPart {
            muscleSlugs = bp.memberMuscleSlugs
            patternSlugs = bp.patternFilters
            if let mod = bp.modalityFilter {
                filters.modality = mod
            }
            if bp == .olympic {
                // Olympic = modality=power if not pattern-tagged. ORed in the
                // query layer; here we just hint via modality if no patterns.
                if patternSlugs.isEmpty {
                    filters.modality = "power"
                }
            }
        }

        if let eq = equipment {
            equipmentSlugs = eq.memberEquipmentSlugs
            if eq == .cardio {
                filters.modality = "endurance"
            }
        }

        return (filters, muscleSlugs, equipmentSlugs, patternSlugs)
    }
}
