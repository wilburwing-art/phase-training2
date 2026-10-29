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

    enum Basis: Equatable {
        /// Linear rule on the previous session's top set.
        case lastSession
        /// Proven strength, for an exercise never logged in the app.
        case history
        /// Proven strength mapped to today's reps, which differ too much
        /// from last session's for the linear rule to be fair.
        case repRemap
        /// Plateau: same weight, one more rep.
        case addRep
    }

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
        /// What the number rests on, so a screen can word it: a lower load
        /// for more reps is not a "back off".
        var basis: Basis = .lastSession

        /// Suggested weight as a tidy string ("190" or "187.5"). Shared by
        /// the Today tile + Log pill so they format identically.
        var suggestedWeightString: String {
            if suggestedWeight.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(suggestedWeight))"
            }
            return String(format: "%.1f", suggestedWeight)
        }
    }

    /// Derive the prior top-set from a session's logged sets. Picks the
    /// HEAVIEST set that actually MET the target reps as the working top set,
    /// so a heavy low-rep top single in a pyramid (e.g. 200×3 over 185×8×8,
    /// target 8) doesn't read as a missed target and trigger a spurious
    /// BACK OFF. Falls back to the heaviest set overall only when no set hit
    /// the target — there the user genuinely failed and a hold/back-off is
    /// the right call. Warm-ups and undone sets are excluded.
    static func priorPerformance(from prevSets: [LoggedSet], targetReps: Int) -> PriorPerformance? {
        let working = prevSets
            .filter { $0.done && !$0.isWarmup }
            .compactMap { set -> (weight: Double, reps: Int)? in
                guard let w = set.weightValue, w > 0,
                      let r = set.repsValue, r > 0 else { return nil }
                return (w, r)
            }
        guard !working.isEmpty else { return nil }
        let metTarget = working.filter { $0.reps >= targetReps }
        let chosen = metTarget.max(by: { $0.weight < $1.weight })
            ?? working.max(by: { $0.weight < $1.weight })!
        return PriorPerformance(weight: chosen.weight, repsAchieved: chosen.reps, targetReps: targetReps)
    }

    /// One-shot convenience: extract the prior top-set from a session's logged
    /// sets and produce a suggestion. Used by both the Today tile and the Log
    /// pill so the extraction rule + suggestion stay in lockstep.
    static func suggest(
        prevSets: [LoggedSet],
        targetReps: Int,
        exerciseName: String,
        unit: String
    ) -> Result? {
        suggest(
            prior: priorPerformance(from: prevSets, targetReps: targetReps),
            exerciseName: exerciseName,
            unit: unit
        )
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

    /// A working load for `targetReps` from a proven-strength estimate
    /// (`ProvenStrength`, in lb), for an exercise with no previous native
    /// session to progress from. Epley maps the estimate to the target reps,
    /// then the load snaps DOWN to the unit's small step (2.5 lb / 1.25 kg):
    /// a first suggestion from history should never round up. Nil for
    /// bodyweight estimates or a non-numeric target.
    static func fromHistory(_ prior: PriorBest, targetReps: Int, unit: String) -> Result? {
        guard prior.weight > 0, prior.reps > 0, targetReps > 0 else { return nil }
        let e1rm = StrengthStandards.epley1RM(weight: prior.weight, reps: prior.reps)
        var load = e1rm / (1 + Double(targetReps) / 30)
        let step: Double
        if unit.lowercased() == "kg" {
            load *= ImportUnitCorrection.kgPerLb
            step = 1.25
        } else {
            step = 2.5
        }
        // The tolerance absorbs kg round-trips: 225 lb stored as kg reads
        // back as 224.99999 and would otherwise snap down to 222.5.
        let snapped = ((load + 1e-6) / step).rounded(.down) * step
        guard snapped > 0 else { return nil }
        return Result(suggestedWeight: snapped, delta: 0, label: "from history",
                      rationale: "From your recent logged and imported sets", basis: .history)
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

    /// Past this many reps between last session's working set and today's
    /// target, the last top set stops being a fair base: the goal re-bands
    /// rows (build 155), so 135x10 last time and 5 reps today is routine.
    static let repGapLimit = 2

    /// The suggestion both the Log pill and the Today tile show, using the
    /// lifter's history profile when there is one:
    ///   - today's reps far from last session's -> proven strength mapped to
    ///     today's reps ("for 5 reps")
    ///   - a plateau whose last session hit its target -> same weight, add a rep
    ///   - otherwise the linear rule, stepping by the lifter's own usual jump
    /// Without a profile this is exactly the old rule.
    static func suggest(
        prevSets: [LoggedSet],
        targetReps: Int,
        exerciseName: String,
        unit: String,
        profile: HistoryProfile.ExerciseProfile?
    ) -> Result? {
        guard let prior = priorPerformance(from: prevSets, targetReps: targetReps) else { return nil }
        guard let profile else { return suggest(prior: prior, exerciseName: exerciseName, unit: unit) }

        if abs(prior.repsAchieved - targetReps) > repGapLimit, let estimate = profile.estimate,
           let mapped = fromHistory(estimate, targetReps: targetReps, unit: unit) {
            return Result(suggestedWeight: mapped.suggestedWeight,
                          delta: mapped.suggestedWeight - prior.weight,
                          label: "for \(targetReps) reps",
                          rationale: "Last time was \(prior.repsAchieved) reps; today asks for \(targetReps).",
                          basis: .repRemap)
        }
        if profile.plateau, prior.repsAchieved >= targetReps {
            return Result(suggestedWeight: prior.weight, delta: 0, label: "add a rep",
                          rationale: "Your estimate has been flat. Same weight, one more rep.",
                          basis: .addRep)
        }
        let step = personalStep(profile: profile, workingWeight: prior.weight, unit: unit,
                                compound: isCompound(name: exerciseName))
        return suggest(prior: prior, exerciseName: exerciseName, unit: unit, bump: step)
    }

    /// The lifter's usual jump (`HistoryProfile.typicalStepLb`) in `unit`,
    /// snapped to 1.25 kg for kg users. Falls back to the table when there is
    /// none, or when it is bigger than both twice the table step and 10% of
    /// the working weight (a sparse history should not produce a +20 lb jump;
    /// a 5 lb dumbbell pair on a 25 lb curl is fine).
    static func personalStep(profile: HistoryProfile.ExerciseProfile?, workingWeight: Double,
                             unit: String, compound: Bool) -> Double {
        let table = bumpFor(unit: unit, compound: compound)
        guard let lb = profile?.typicalStepLb, lb > 0 else { return table }
        let step = unit.lowercased() == "kg"
            ? max(1.25, (lb * ImportUnitCorrection.kgPerLb / 1.25).rounded() * 1.25)
            : lb
        return step > max(2 * table, workingWeight * 0.10) ? table : step
    }

    static func suggest(
        prior: PriorPerformance?,
        exerciseName: String,
        unit: String,
        bump stepOverride: Double? = nil
    ) -> Result? {
        guard let prior else { return nil }
        let compound = isCompound(name: exerciseName)
        let bump = stepOverride ?? bumpFor(unit: unit, compound: compound)
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
