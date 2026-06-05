// EraAffinity.swift — Age-derived "training era" cohort table that biases
// the generator's split style, rep-range, exercise aesthetic, and LLM
// vocabulary toward the training culture the user came up in.
//
// Routing discipline (per phase-training-personalization-three-axes skill):
//   Era affinity controls ONLY split style + rep-range bias + exercise
//   aesthetic tiebreak + LLM vocabulary. It DOES NOT touch movement
//   competency (that's `ExperienceLevel`) or volume/intensity scaling
//   (that's `readinessScore`, Phase 2). A 58-year-old advanced lifter
//   still gets barbell back squats — the era just nudges toward an
//   Arnold/bro-split structure with 8-12 rep biases.
//
// Cohort boundaries are keyed by *formative-years* heuristic (late teens
// to mid-20s, when most lifters absorb their first training culture).
// Today's date is 2026, so age bands map to formative windows like:
//   age 55+ → late-70s / mid-90s magazines (Joe Weider era)
//   age 40-54 → 1990-2010 (T-Nation forums, Westside, DC, early 5/3/1)
//   age 28-39 → 2010-2018 (Reddit /r/fitness, Starting Strength, 5/3/1 BBB)
//   age 20-27 → 2018-now (Nippard/RP science-based hypertrophy)
//   age <20  → now (TikTok fitness, current meta)
//
// Persistence note: `eraOverride` lives on `TrainingMemory` as a String
// (the cohort's rawValue). This file owns the table; consumers store
// only the slug, mirroring the precedent set by `Sport` (slug-stored,
// catalog-resolved at decode time).
//
// Enum shape mirrors ExerciseTaxonomy.swift (PR 12) — String-backed,
// CaseIterable, Identifiable, Hashable, with display ordering encoded
// in case order. Co-located here rather than in EraTaxonomy.swift
// because era enums are only consumed by the affinity engine.

import Foundation

// MARK: - EraCohort

/// The six training-culture cohorts. Case order is also display order
/// in any picker UI (oldest → newest).
enum EraCohort: String, CaseIterable, Identifiable, Hashable {
    case veteranStrength      = "veteran_strength"     // 70+
    case magazineBodybuilding = "magazine_bodybuilding" // 55-69
    case tNationForum         = "t_nation_forum"
    case redditFitness        = "reddit_fitness"
    case scienceBased         = "science_based"
    case currentMeta          = "current_meta"

    var id: String { rawValue }
}

// MARK: - AestheticTag

/// Implement-family preference used as a deterministic-pick tiebreaker
/// in `WorkoutGenerator.generateLift` when two candidates score equally
/// on SFR + staple + variety filters.
enum AestheticTag: String, CaseIterable, Identifiable, Hashable {
    case machineFavor
    case barbellFavor
    case cableFavor
    case dbFavor

    var id: String { rawValue }
}

// MARK: - RepBand

/// Rep-range bias buckets. Compose two of these into a (compound, isolation)
/// tuple per cohort and let the generator's prescription path widen its
/// reps toward the chosen band.
///
/// Bands chosen to align with the existing rep-prescription tables in
/// `WorkoutGenerator.focusBias(...)` — low ~= strength, mid ~= hypertrophy,
/// high ~= endurance / pump.
enum RepBand: String, CaseIterable, Identifiable, Hashable {
    case low       // 3-6
    case mid       // 8-12
    case high      // 12-20

    var id: String { rawValue }

    /// Human-display range, also used by `EraStyle.repsString(forRole:)` if
    /// the generator needs a plain "8-12" string.
    var range: ClosedRange<Int> {
        switch self {
        case .low:  return 3...6
        case .mid:  return 8...12
        case .high: return 12...20
        }
    }

    var display: String { "\(range.lowerBound)-\(range.upperBound)" }
}

// MARK: - EraStyle

/// All era-derived modulation lives in this struct. Pure data — no I/O,
/// no DB calls. Consumed by `DemographicProfile.eraStyle`,
/// `WeeklyShape` focus rotation, `WorkoutGenerator` rep prescription +
/// deterministic-pick tiebreak, and `CoachContext.snapshot(...)` for
/// LLM vocabulary.
struct EraStyle: Hashable {
    let cohort: EraCohort

    /// Short noun-phrase shown in onboarding ("Magazine bodybuilding era").
    let displayName: String

    /// One-liner shown under the displayName in onboarding.
    let narrativeBlurb: String

    /// Per-lift-day focus rotation the cohort prefers. The generator
    /// consults this when picking which `WorkoutFocus` to assign to a
    /// lift slot — e.g. magazineBodybuilding biases toward 5-day body-
    /// part split rotations (push/pull/legs/upper/lower), redditFitness
    /// biases toward PPL, etc. Empty means "no preference, fall through
    /// to the existing focus selection logic."
    let splitPreference: [WorkoutFocus]

    /// Rep-range bias for the prescription path. `.compound` applies to
    /// the primary slot (slotIdx 0) when isCompound; `.isolation`
    /// applies to accessory slots.
    let repRangeBias: (compound: RepBand, isolation: RepBand)

    /// Implement-family preferences. Used as a tiebreak when two
    /// candidates are otherwise equivalent — exercise whose equipment
    /// slug matches a preferred tag wins.
    let aestheticTags: Set<AestheticTag>

    /// Vocabulary nudges the LLM coach should incorporate. Things like
    /// "pump", "burn", "stretch under load" for magazineBodybuilding;
    /// "RPE", "MEV/MAV/MRV" for scienceBased; "AMRAP", "training max"
    /// for redditFitness.
    let terminologyHints: [String]

    /// Phase 4 hook — IDs of canonical programs this cohort would
    /// recognize. Phase 1 only uses these for display; Phase 4 will
    /// surface them as a "programs lifters like you have run" list.
    let archetypalPrograms: [String]

    // Hashable / Equatable — tuples aren't auto-synthesizable, so the
    // synthesized conformance would error. Hand-roll on the cohort
    // (the table is total, so cohort identity implies the rest).
    static func == (lhs: EraStyle, rhs: EraStyle) -> Bool {
        lhs.cohort == rhs.cohort
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(cohort)
    }
}

// MARK: - EraAffinity

/// Pure functions for deriving and resolving era cohorts. Date-injectable
/// so tests can pin the "today" anchor.
enum EraAffinity {

    /// Derived cohort from age. `forAge: nil` → returns nil (no prior,
    /// generator behaves identically to pre-era code).
    ///
    /// `asOf` is reserved for the day the cohort boundaries themselves
    /// shift (e.g. in 2028 the redditFitness window will move because
    /// the formative-years anchor advances). Phase 1 ignores asOf — the
    /// table is static today — but the parameter exists so downstream
    /// callers don't have to refactor when we make boundaries date-
    /// dependent.
    static func derivedCohort(forAge age: Int?, asOf: Date = Date()) -> EraCohort? {
        guard let age else { return nil }
        switch age {
        case ..<20:    return .currentMeta
        case 20...27:  return .scienceBased
        case 28...39:  return .redditFitness
        case 40...54:  return .tNationForum
        case 55...69:  return .magazineBodybuilding
        default:       return .veteranStrength         // 70+
        }
    }

    /// Table lookup. Total over `EraCohort`, so this never returns nil.
    static func style(for cohort: EraCohort) -> EraStyle {
        switch cohort {
        case .veteranStrength:
            return EraStyle(
                cohort: .veteranStrength,
                displayName: "Veteran strength era",
                narrativeBlurb: "70+ programming: power-focused low-rep compounds for neural drive, single-leg and balance work, and extra recovery built in.",
                // Upper-lower keeps volume manageable and co-locates push/pull
                // pairs for supersets without the fatigue of a full-body day.
                splitPreference: [.upper, .lower, .upper, .lower],
                // Low rep band on compounds (3-6) for power/neural drive;
                // mid on isolations (8-12) for joint-friendly hypertrophy.
                repRangeBias: (compound: .low, isolation: .mid),
                aestheticTags: [.barbellFavor, .dbFavor],
                terminologyHints: ["power", "neural drive", "movement quality",
                                   "balance", "compound first", "controlled tempo"],
                archetypalPrograms: ["greyskull-lp", "531-perennial", "basic-strength"]
            )

        case .magazineBodybuilding:
            return EraStyle(
                cohort: .magazineBodybuilding,
                displayName: "Magazine bodybuilding era",
                narrativeBlurb: "Bro splits, machines and dumbbells, pump-and-burn cues. Joe Weider, Arnold, HIT.",
                // 5-day body-part split: chest day, back day, shoulders, arms, legs.
                // Maps to the existing focus enum as push (chest+shoulders+tris)
                // / pull (back+bis) / legs / upper / lower for the 5-day rotation.
                splitPreference: [.push, .pull, .legs, .upper, .lower],
                repRangeBias: (compound: .mid, isolation: .mid),
                aestheticTags: [.machineFavor, .dbFavor],
                // "drop set" was removed in build 103 — we don't model
                // drop sets anywhere (no set-grouping, no descending-load
                // logger), so coaching with the term would write checks
                // the app can't cash. Re-add once the logger gains a
                // drop-set primitive.
                terminologyHints: ["pump", "burn", "feel the squeeze", "mind-muscle connection",
                                   "stretch under load", "bro split"],
                archetypalPrograms: ["arnold-split", "bro-split", "hit-heavy-duty"]
            )

        case .tNationForum:
            return EraStyle(
                cohort: .tNationForum,
                displayName: "T-Nation / forum era",
                narrativeBlurb: "Westside-influenced, 5×5 revival, DC training, early 5/3/1. Heavy compounds, dynamic-effort work.",
                // Upper-lower split with conjugate flavor; falls through to
                // upper/lower on 4-day weeks, push/pull/legs on 3-day weeks.
                splitPreference: [.upper, .lower, .upper, .lower],
                repRangeBias: (compound: .low, isolation: .mid),
                aestheticTags: [.barbellFavor],
                terminologyHints: ["max effort", "dynamic effort", "training max",
                                   "5x5", "speed work", "accessories"],
                archetypalPrograms: ["531-bbb", "westside-conjugate", "doggcrapp", "madcow-5x5"]
            )

        case .redditFitness:
            return EraStyle(
                cohort: .redditFitness,
                displayName: "Reddit /r/fitness era",
                narrativeBlurb: "Starting Strength, StrongLifts, 5/3/1 BBB, Reddit PPL, GZCL. AMRAP top sets, RPE-aware progression.",
                // Classic PPL rotation.
                splitPreference: [.push, .pull, .legs, .push, .pull, .legs],
                repRangeBias: (compound: .low, isolation: .mid),
                aestheticTags: [.barbellFavor],
                terminologyHints: ["AMRAP", "RPE", "training max", "PR", "linear progression",
                                   "deload", "joker sets"],
                archetypalPrograms: ["reddit-ppl", "531-bbb", "gzclp", "starting-strength", "stronglifts-5x5"]
            )

        case .scienceBased:
            return EraStyle(
                cohort: .scienceBased,
                displayName: "Science-based era",
                narrativeBlurb: "Nippard/RP style high-volume hypertrophy, autoregulation, MEV/MAV/MRV, RIR-based progression.",
                // Upper-lower or PPL — both are canonical in the science-based
                // crowd. Pick upper-lower as the primary because RP-style
                // weekly volume math fits cleanly with 4-day upper/lower.
                splitPreference: [.upper, .lower, .upper, .lower],
                repRangeBias: (compound: .mid, isolation: .mid),
                aestheticTags: [.cableFavor, .dbFavor, .machineFavor],
                terminologyHints: ["RIR", "MEV", "MAV", "MRV", "stimulus-to-fatigue ratio",
                                   "lengthened partials", "mechanical tension", "junk volume"],
                archetypalPrograms: ["rp-hypertrophy", "nippard-hypertrophy", "gvs"]
            )

        case .currentMeta:
            return EraStyle(
                cohort: .currentMeta,
                displayName: "Current meta",
                narrativeBlurb: "TikTok fitness, science-based with shorter feedback loops, lengthened-partial heavy, cable-isolation forward.",
                splitPreference: [.push, .pull, .legs, .upper, .lower],
                repRangeBias: (compound: .mid, isolation: .high),
                aestheticTags: [.cableFavor, .machineFavor],
                terminologyHints: ["lengthened partial", "stretch-mediated hypertrophy",
                                   "myo-reps", "constant tension", "0 RIR"],
                archetypalPrograms: ["nippard-hypertrophy", "rp-hypertrophy"]
            )
        }
    }
}
