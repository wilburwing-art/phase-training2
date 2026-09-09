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
        case .chest:      return String(localized: "Chest", comment: "Muscle group")
        case .back:       return String(localized: "Back", comment: "Muscle group")
        case .shoulders:  return String(localized: "Shoulders", comment: "Muscle group")
        case .biceps:     return String(localized: "Biceps", comment: "Muscle group")
        case .triceps:    return String(localized: "Triceps", comment: "Muscle group")
        case .forearms:   return String(localized: "Forearms", comment: "Muscle group")
        case .quads:      return String(localized: "Quads", comment: "Muscle group")
        case .hamstrings: return String(localized: "Hamstrings", comment: "Muscle group")
        case .glutes:     return String(localized: "Glutes", comment: "Muscle group")
        case .calves:     return String(localized: "Calves", comment: "Muscle group")
        case .core:       return String(localized: "Core", comment: "Muscle group")
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
        case .chest:      return String(localized: "Chest", comment: "Muscle group")
        case .back:       return String(localized: "Back", comment: "Muscle group")
        case .shoulders:  return String(localized: "Shoulders", comment: "Muscle group")
        case .arms:       return String(localized: "Arms", comment: "Muscle group")
        case .quads:      return String(localized: "Quads", comment: "Muscle group")
        case .hamsGlutes: return String(localized: "Hams + Glutes", comment: "Muscle group")
        case .core:       return String(localized: "Core", comment: "Muscle group")
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
        case .push:         return String(localized: "Push", comment: "Movement pattern")
        case .pull:         return String(localized: "Pull", comment: "Movement pattern")
        case .legs:         return String(localized: "Legs", comment: "Movement pattern")
        case .core:         return String(localized: "Core", comment: "Movement pattern")
        case .conditioning: return String(localized: "Conditioning", comment: "Movement pattern")
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
        // `hideOtherSports` is deliberately NOT counted: it defaults ON, so
        // counting it would pin the badge at "(1)" in the untouched state and
        // mean nothing. Its discoverability problem — the user couldn't tell
        // ~44% of the catalog was hidden — is solved by the Sports section in
        // ExerciseFilterSheet instead, which names the filter and lets the user
        // switch it off. `clearSecondary()` does reset it, since Reset means
        // "stop narrowing".
        return n
    }

    /// Reset secondary filters (everything except the primary muscle bucket).
    mutating func clearSecondary() {
        category = nil
        modality = nil
        difficulty = nil
        environment = nil
        compoundOnly = nil
        // Reset must be able to clear the one filter that is actually removing
        // rows, otherwise "Reset" leaves the catalog still ~44% hidden.
        hideOtherSports = false
    }
}

// MARK: - WorkoutTile

/// Goal-grouping tiles for the Library Workouts segment's "by goal" grid.
/// Mirrors LibraryTile's role for exercises: coarse buckets over the bundled
/// `routines.goal` column. `other` is the catch-all — it must claim null and
/// any goal no tile lists so no routine is orphaned (the exercise redesign
/// hit exactly this with 19 unreachable rows).
///
/// The known-goal list here is duplicated inside
/// CoachDatabase.listRoutines(goals:) when building the catch-all WHERE
/// clause — keep the two in sync via memberGoals, which is the single source
/// of truth for "what does a tile claim".
enum WorkoutGoalTile: String, CaseIterable, Identifiable, Hashable {
    case strength, prehab, power, warmUp, endurance, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strength:  return String(localized: "Strength", comment: "Workout goal tile")
        case .prehab:    return String(localized: "Prehab", comment: "Workout goal tile")
        case .power:     return String(localized: "Power", comment: "Workout goal tile")
        case .warmUp:    return String(localized: "Warm-up", comment: "Workout goal tile")
        case .endurance: return String(localized: "Endurance", comment: "Workout goal tile")
        case .other:     return String(localized: "Mobility & Recovery", comment: "Workout goal tile")
        }
    }

    /// routines.goal values that belong to this tile. `other` claims nothing
    /// — the DB layer expresses it as "null OR not in any tile".
    var memberGoals: [String] {
        switch self {
        case .strength:  return ["strength", "direct_strength"]
        case .prehab:    return ["prehab", "pt_rehab"]
        case .power:     return ["power"]
        case .warmUp:    return ["warm_up"]
        case .endurance: return ["endurance"]
        case .other:     return []
        }
    }

    /// SF Symbol shown on the tile face. Same icon style across all tiles so
    /// the grid reads as a family.
    var symbol: String {
        switch self {
        case .strength:  return "dumbbell.fill"
        case .prehab:    return "cross.case.fill"
        case .power:     return "bolt.fill"
        case .warmUp:    return "flame.fill"
        case .endurance: return "heart.fill"
        case .other:     return "leaf.fill"
        }
    }
}

/// "By sport" tile for the Workouts segment grid. Built at runtime from
/// sport_categories rows that carry linked routines
/// (CoachDatabase.listRoutineSports) — unlike WorkoutGoalTile this is NOT
/// a static allCases enum; the slug/name come from the DB so new sports in
/// coach.db surface without a Swift change.
struct WorkoutSportTile: Identifiable, Hashable {
    let slug: String
    let name: String
    let routineCount: Int

    var id: String { slug }

    /// SF Symbol per sport family. Falls back to a generic ball/figure when
    /// no mapping matches so an unmapped sport still renders as a tile.
    var symbol: String {
        switch slug {
        case "snowboarding", "alpine-skiing", "skiing":
            return "figure.skiing.downhill"
        case "climbing", "bouldering", "mountaineering":
            return "figure.climbing"
        case "tennis", "pickleball", "racquet-sports", "squash", "badminton",
             "racquetball", "table-tennis", "padel", "beach-tennis":
            return "figure.racquetball"
        case "golf":
            return "figure.golf"
        case "soccer", "flag-football", "rugby", "lacrosse", "ultimate-frisbee",
             "team-handball", "dodgeball-kickball", "cricket", "polo":
            return "figure.soccer"
        case "basketball", "volleyball", "softball", "baseball-adult":
            return "figure.basketball"
        case "bjj", "mma", "boxing", "judo", "karate", "muay-thai", "kickboxing",
             "taekwondo", "wrestling":
            return "figure.combat.sports"
        case "running", "road-running", "trail-running", "marathon",
             "obstacle-course-racing":
            return "figure.run"
        case "cycling", "road-cycling", "gravel-cycling", "mountain-biking",
             "cyclocross":
            return "figure.outdoor.cycle"
        case "hiking-trekking", "backpacking", "thru-hiking", "snowshoeing":
            return "figure.hiking"
        case "swimming", "lap-swimming", "open-water-swimming":
            return "figure.pool.swim"
        case "paddle-sports", "canoeing", "kayaking", "sup", "rafting",
             "surfing", "surf-wave-sports", "wakeboarding", "wakesurfing",
             "kitesurfing", "wing-foiling", "bodyboarding":
            return "figure.waterpolo"
        case "yoga", "yoga-movement", "pilates", "tai-chi-qigong":
            return "figure.mind.and.body"
        case "hockey", "roller-derby", "skating-wheeled", "inline-skating":
            return "figure.skating"
        case "strength-fitness-sports", "powerlifting", "bodybuilding",
             "crossfit", "olympic-weightlifting", "kettlebell-sport",
             "strongman", "highland-games", "calisthenics":
            return "dumbbell.fill"
        case "equestrian", "dressage", "show-jumping", "equestrian-eventing",
             "equestrian-trail", "equestrian-endurance", "polo":
            return "figure.equestrian.sports"
        case "dance-fitness", "contemporary-dance", "hip-hop-dance",
             "ballroom-latin", "salsa-bachata", "swing-dance", "irish-dance",
             "pole-fitness":
            return "figure.dance"
        case "fencing", "archery", "hang-gliding", "paragliding", "sailing-air-sports":
            return "figure.archery"
        default:
            return "figure.socialsports"
        }
    }
}
