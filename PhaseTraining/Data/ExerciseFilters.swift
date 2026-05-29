// ExerciseFilters.swift — primary muscle buckets, movement categories, and
// the value type both ExercisePickerSheet + LibraryScreen consume.
//
// The DB's muscle_groups table is 80+ fine-grained slugs (vastus-medialis,
// pec-major-sternal, glute-min). Lifters don't think in those terms — they
// think "Chest", "Back", "Quads". MuscleBucket canonicalizes the granular
// slugs into 11 broad chip-strip buckets.
//
// MovementCategory does the same for movement_patterns — Push, Pull, Legs,
// Core, Conditioning — collapsing 40 fine-grained pattern slugs into the
// lifters'-mental-model groupings.

import SwiftUI

// MARK: - MuscleBucket

/// Primary chip-strip buckets. Order is the display order in the chip strip.
enum MuscleBucket: String, CaseIterable, Identifiable, Hashable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, core

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest:      return "Chest"
        case .back:       return "Back"
        case .shoulders:  return "Shoulders"
        case .biceps:     return "Biceps"
        case .triceps:    return "Triceps"
        case .forearms:   return "Forearms"
        case .quads:      return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes:     return "Glutes"
        case .calves:     return "Calves"
        case .core:       return "Core"
        }
    }

    /// muscle_groups.slug values that roll up into this bucket. The DB tags
    /// exercises with whatever granularity the data import used — some
    /// presses are tagged "chest", others "pec-major-sternal". We OR across
    /// all member slugs to catch both.
    var memberSlugs: [String] {
        switch self {
        case .chest:
            return ["chest", "pec-major-sternal", "pec-major-clav", "pec-minor", "serratus-anterior"]
        case .back:
            return ["back", "lats", "mid-traps", "rhomboids", "lower-traps", "upper-traps",
                    "traps", "teres-major", "teres-minor", "levator-scapulae",
                    "erector-thoracic", "erector-lumbar", "multifidus"]
        case .shoulders:
            return ["shoulders", "delt-anterior", "delt-lateral", "delt-posterior",
                    "rotator-cuff", "infraspinatus", "supraspinatus", "subscapularis"]
        case .biceps:
            return ["biceps", "brachialis", "brachioradialis"]
        case .triceps:
            return ["triceps"]
        case .forearms:
            return ["forearm-flexors", "forearm-extensors", "finger-flexors", "finger-extensors",
                    "grip-crush", "grip-pinch", "grip-support"]
        case .quads:
            return ["quadriceps", "vastus-medialis", "vastus-lateralis",
                    "vastus-intermedius", "rectus-femoris", "sartorius"]
        case .hamstrings:
            return ["hamstrings", "biceps-femoris", "semimembranosus", "semitendinosus"]
        case .glutes:
            return ["glutes", "glute-max", "glute-med", "glute-min", "tfl", "piriformis", "hip-rotators"]
        case .calves:
            return ["calves", "gastrocnemius", "soleus", "tib-anterior",
                    "peroneals", "intrinsic-foot"]
        case .core:
            return ["core", "rectus-abdominis", "external-obliques", "internal-obliques",
                    "transverse-abdominis", "quadratus-lumborum", "pelvic-floor", "diaphragm",
                    "hip-flexors", "iliopsoas"]
        }
    }

    /// Buckets surfaced in the soreness check-in (and downstream coach
    /// summaries). All 11 buckets are selectable: the accessory groups —
    /// biceps, triceps, forearms, calves — genuinely get sore (curl/extension
    /// volume, sprint/calf-raise work) and, when flagged, must be able to drive
    /// the RPE-7 down-regulation and warm-up suppression in WorkoutGenerator.
    /// Omitting them left those paths permanently unreachable for arms/calves.
    static let sorenessPrimaryCases: [MuscleBucket] = MuscleBucket.allCases

    /// Lower-cased rawValue set for fast filter-on-read of `SorenessEntry.areas`.
    /// Used to suppress legacy entries that tagged buckets we no longer surface,
    /// so coach summaries don't say "areas: calves" after the UI stopped offering it.
    static let sorenessPrimarySlugs: Set<String> = Set(
        sorenessPrimaryCases.map { $0.rawValue }
    )

    /// Reverse map: given a muscle_groups.slug, which bucket does it fall in?
    /// Returns nil for slugs we don't surface (full-body, neck, etc.) — those
    /// exercises simply won't match any bucket filter, which is intended.
    static func bucket(forSlug slug: String) -> MuscleBucket? {
        for bucket in MuscleBucket.allCases where bucket.memberSlugs.contains(slug) {
            return bucket
        }
        return nil
    }

    /// Canonical muscle_groups.slug to feed BodyAnatomyView when this bucket
    /// is the primary muscle. Picks the most visually-recognizable region per
    /// bucket so the chip-scale badge reads correctly.
    var primarySlug: String {
        switch self {
        case .chest:      return "chest"
        case .back:       return "lats"
        case .shoulders:  return "shoulders"
        case .biceps:     return "biceps"
        case .triceps:    return "triceps"
        case .forearms:   return "forearm-flexors"
        case .quads:      return "quadriceps"
        case .hamstrings: return "hamstrings"
        case .glutes:     return "glutes"
        case .calves:     return "calves"
        case .core:       return "rectus-abdominis"
        }
    }

    /// Whether this bucket naturally reads on the front or back of the body.
    /// Drives the default `side` of the chip badge — callers can override per
    /// exercise (e.g. a deadlift reads as back even though it works the legs).
    var naturalSide: BodyAnatomyView.AnatomySide {
        switch self {
        case .back, .triceps, .hamstrings, .glutes, .calves:
            return .back
        case .chest, .shoulders, .biceps, .forearms, .quads, .core:
            return .front
        }
    }
}

// MARK: - LibraryTile

/// Coarser muscle grouping the Library tab uses as its landing grid (7 tiles
/// instead of the 11 MuscleBucket chips). Pre-scopes the exercise list so
/// users never face the 551-row firehose: tap "Arms" → 33 exercises across
/// biceps+triceps+forearms; tap "Hams + Glutes" → posterior-chain set
/// including calves. MuscleBucket stays the source of truth — LibraryTile
/// just rolls members together.
enum LibraryTile: String, CaseIterable, Identifiable, Hashable {
    case chest, back, shoulders, arms, quads, hamsGlutes, core

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest:      return "Chest"
        case .back:       return "Back"
        case .shoulders:  return "Shoulders"
        case .arms:       return "Arms"
        case .quads:      return "Quads"
        case .hamsGlutes: return "Hams + Glutes"
        case .core:       return "Core"
        }
    }

    /// Which MuscleBucket(s) roll into this tile. Compound tiles (Arms,
    /// Hams + Glutes) have multiple members — the drill-down screen surfaces
    /// them as sub-chips so users can narrow to a single muscle.
    var members: [MuscleBucket] {
        switch self {
        case .chest:      return [.chest]
        case .back:       return [.back]
        case .shoulders:  return [.shoulders]
        case .arms:       return [.biceps, .triceps, .forearms]
        case .quads:      return [.quads]
        case .hamsGlutes: return [.hamstrings, .glutes, .calves]
        case .core:       return [.core]
        }
    }

    /// Flat OR'd list of muscle_groups.slug values to pass into
    /// CoachDatabase.listExercises(muscleSlugs:). Already handles the
    /// multi-bucket case for Arms / Hams + Glutes.
    var memberSlugs: [String] {
        members.flatMap { $0.memberSlugs }
    }

    /// SF Symbol shown on the tile face. Same icon style across all 7 so the
    /// grid reads as a family.
    var symbol: String {
        switch self {
        case .chest:      return "figure.cooldown"
        case .back:       return "figure.strengthtraining.functional"
        case .shoulders:  return "figure.boxing"
        case .arms:       return "dumbbell.fill"
        case .quads:      return "figure.run"
        case .hamsGlutes: return "figure.walk"
        case .core:       return "figure.core.training"
        }
    }
}

// MARK: - MovementCategory

/// Lifter-mental-model groupings of movement_patterns. Lives in the
/// secondary filter sheet — it's a refinement of muscle bucket, not a
/// parallel primary axis (push already implies chest+shoulders+triceps,
/// so two parallel primaries would double-count).
enum MovementCategory: String, CaseIterable, Identifiable, Hashable {
    case push, pull, legs, core, conditioning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .push:         return "Push"
        case .pull:         return "Pull"
        case .legs:         return "Legs"
        case .core:         return "Core"
        case .conditioning: return "Conditioning"
        }
    }

    /// Reverse map: given a movement_patterns.slug, which category does it
    /// roll into? Returns nil for slugs we don't surface as a category.
    static func category(forSlug slug: String) -> MovementCategory? {
        for cat in MovementCategory.allCases where cat.memberPatternSlugs.contains(slug) {
            return cat
        }
        return nil
    }

    /// movement_patterns.slug values that roll up into this category.
    var memberPatternSlugs: [String] {
        switch self {
        case .push:
            return ["horizontal-push", "vertical-push", "scapular-protraction"]
        case .pull:
            return ["horizontal-pull", "vertical-pull", "scapular-retraction",
                    "elbow-flexion", "climbing-pull"]
        case .legs:
            return ["squat", "hip-hinge", "single-leg-squat", "step-up",
                    "calf-raise", "hip-abduction", "hip-adduction",
                    "terminal-knee-extension", "olympic-derivative"]
        case .core:
            return ["anti-extension", "anti-rotation", "anti-lateral-flexion",
                    "trunk-rotation", "breathing-bracing", "hip-flexion",
                    "loaded-carry"]
        case .conditioning:
            return ["locomotion", "jumping-landing", "deceleration", "cutting",
                    "throwing-casting", "striking", "rotational-strike",
                    "swim-stroke", "pedal-stroke", "paddle-stroke",
                    "skating-stride", "racquet-swing", "takedown-sprawl",
                    "crawling", "ground-to-standing"]
        }
    }
}

// MARK: - ExerciseFilters

/// Value type that ExercisePickerSheet + LibraryScreen pass to
/// CoachDatabase.listExercises. nil/empty = no filter applied.
struct ExerciseFilters: Hashable {
    var bucket: MuscleBucket? = nil
    var category: MovementCategory? = nil
    var modality: String? = nil
    var difficulty: String? = nil
    var environment: String? = nil
    /// nil = either, true = compound only, false = isolation only.
    var compoundOnly: Bool? = nil
    /// When true, the caller passes the user's sport slugs (primary +
    /// secondaries) to listExercises so niche sport-specific drills hide
    /// for users who don't train those sports, foundation lifts always
    /// show, and matching-sport rows rank highest. Default off so callers
    /// (e.g. picker sheets used from inside a routine builder) can opt in.
    var hideOtherSports: Bool = true

    /// Count of non-default secondary filters — used for the "All filters (N)"
    /// button label so the user sees a chip count without expanding.
    var secondaryCount: Int {
        var n = 0
        if category != nil    { n += 1 }
        if modality != nil    { n += 1 }
        if difficulty != nil  { n += 1 }
        if environment != nil { n += 1 }
        if compoundOnly != nil { n += 1 }
        return n
    }

    /// Reset secondary filters (everything except the primary muscle bucket).
    mutating func clearSecondary() {
        category = nil
        modality = nil
        difficulty = nil
        environment = nil
        compoundOnly = nil
    }
}
