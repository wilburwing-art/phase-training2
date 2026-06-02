// ProgressionSuggestion.swift — deterministic next-weight rule.
//
// Build 103. The generator already knows the user's prior best (PriorBest in
// GeneratorContext), and coach.db ships progression/regression strings per
// exercise, but the user never sees a concrete number suggested for next
// session — autofill just pre-fills the LAST weight. This module turns
// PriorBest into "next session: 185 → 190 (+5)" so progressive overload is
// a visible story, not an LLM-driven black box.
//
// Rules are intentionally simple linear progression — the bands are noise-
// tolerant for beginner and intermediate lifters, and the conservatism
// matches what an actual coach would write on a whiteboard:
//
//   · Hit the target reps last time → bump up
//        compound          : +5 lb  /  +2.5 kg
//        isolation / DB    : +2.5 lb / +1.25 kg
//   · Missed reps by 1            → hold weight
//   · Missed reps by 2+           → drop a small notch (one band down)
//   · No prior data               → hold (no suggestion, generator default)
//
// The output is metric-agnostic: callers pass a `unit` string ("lb" / "kg")
// and we return the suggestion in the same unit. The bump table is hard-
// coded for both unit systems so 2.5 kg doesn't get rounded to "5.5 lb".

import Foundation

enum ProgressionSuggestion {

    /// Snapshot of last session's top set + whether the user hit the
    /// programmed target. Build this from PriorBest at the call site.
    struct PriorPerformance: Equatable {
        let weight: Double
        let repsAchieved: Int
        let targetReps: Int
    }

    /// What to render on the exercise tile.
    struct Result: Equatable {
        let suggestedWeight: Double
        let delta: Double
        /// Short tag for the meta line — "+5", "hold", "-5", or "—" when
        /// nothing to suggest.
        let label: String
        /// Free-text rationale for tooltips / accessibility.
        let rationale: String
    }

    /// True for movements where the smallest meaningful jump on the available
    /// plate set is the small one. Resolved by name match against a curated
    /// list. Anything we don't recognize defaults to "isolation" so we err on
    /// the side of conservative bumps — pushing 5 lb every session on a
    /// lateral raise is a fast way to break form.
    private static let compoundKeywords: Set<String> = [
        "squat", "deadlift", "bench press", "overhead press", "ohp",
        "press", "row", "pull-up", "pullup", "chin-up", "chinup",
        "clean", "snatch", "front squat", "back squat", "split squat",
        "rdl", "romanian deadlift", "sumo", "good morning",
        "hip thrust", "thrust", "lunge", "step-up", "stepup",
        "dip"
    ]

    static func isCompound(name: String) -> Bool {
        let lower = name.lowercased()
        return compoundKeywords.contains(where: { lower.contains($0) })
    }

    /// Resolve the bump for one exercise. Pass `isCompound` to override the
    /// keyword default for known cases.
    static func bumpFor(
        unit: String,
        compound: Bool
    ) -> Double {
        let lower = unit.lowercased()
        if lower == "kg" {
            return compound ? 2.5 : 1.25
        }
        return compound ? 5.0 : 2.5
    }

    static func suggest(
        prior: PriorPerformance?,
        exerciseName: String,
        unit: String
    ) -> Result? {
        guard let prior else { return nil }
        let compound = isCompound(name: exerciseName)
        let bump = bumpFor(unit: unit, compound: compound)
        let missed = prior.targetReps - prior.repsAchieved

        switch missed {
        case ..<0:  // beat reps — still bump (could go bigger, but keep linear)
            return Result(
                suggestedWeight: prior.weight + bump,
                delta: bump,
                label: signedLabel(bump),
                rationale: "Beat reps last time. Bump \(formatBump(bump, unit: unit))."
            )
        case 0:  // hit reps exactly
            return Result(
                suggestedWeight: prior.weight + bump,
                delta: bump,
                label: signedLabel(bump),
                rationale: "Hit reps last time. Bump \(formatBump(bump, unit: unit))."
            )
        case 1:  // missed by 1 — hold
            return Result(
                suggestedWeight: prior.weight,
                delta: 0,
                label: "hold",
                rationale: "Missed reps by 1 last time. Hold and earn them."
            )
        default:  // missed by 2+ — back off a notch
            let backoff = bump
            return Result(
                suggestedWeight: max(0, prior.weight - backoff),
                delta: -backoff,
                label: signedLabel(-backoff),
                rationale: "Missed reps by \(missed) last time. Back off \(formatBump(backoff, unit: unit))."
            )
        }
    }

    private static func signedLabel(_ v: Double) -> String {
        if v == 0 { return "hold" }
        let prefix = v > 0 ? "+" : "−"
        let n = abs(v)
        // Strip trailing zero from whole numbers ("+5" not "+5.0").
        if n.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(prefix)\(Int(n))"
        }
        return String(format: "%@%.1f", prefix, n)
    }

    private static func formatBump(_ v: Double, unit: String) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(v)) \(unit)"
        }
        return String(format: "%.2g %@", v, unit)
    }
}
