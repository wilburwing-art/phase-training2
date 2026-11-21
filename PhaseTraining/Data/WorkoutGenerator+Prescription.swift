// WorkoutGenerator+Prescription.swift
//
// Progressive-overload load math: the "target: X" note the custom-day
// refresh and the authored routines attach to a row. Pure, no state. Sets,
// reps, rest and RPE come from the season engine (`SportSeasonGenerator`).

import Foundation

extension WorkoutGenerator {
    /// "target: 195 lb" style hint — a LOAD to work up to at the prescribed
    /// reps. Priority order:
    ///   1. LLM strategy targetWeightOverrides — explicit prescriptions ("bench at 90%").
    ///   2. priorBest → e1RM → load for the prescribed rep band, +2.5% step.
    ///   3. Nothing — no signal, no note.
    static func progressiveOverloadHint(
        for exercise: Exercise,
        context: GeneratorContext,
        memory: TrainingMemory,
        prescribedReps: String,
        strategy: GeneratorStrategy = .auto
    ) -> String? {
        let key = exercise.name.lowercased()
        // Layer 1: explicit LLM override — a load to work up to, as given.
        if let override = strategy.targetWeightOverrides[key] {
            return formatTargetHint(weightLb: override, memory: memory)
        }
        // Layer 2: priorBest mapped to the prescribed rep range, then stepped.
        guard let prior = ExerciseKey.lookup(context.priorBest, name: exercise.name) else { return nil }
        // Bodyweight movement (weight 0): a load target is meaningless, so
        // progress by REPS — beat the best set by one rep. (T2.1)
        if prior.weight == 0 {
            return prior.reps > 0 ? "target: \(prior.reps + 1) reps" : nil
        }
        // T2-9: the step is no longer unconditional. A missed last attempt at
        // the best-ever weight holds the load; a badly missed one steps it
        // down. Everything else (no history, a lighter day) steps up as before.
        let decision = ProgressionDecision.decide(prior: prior,
                                                  last: ExerciseKey.lookup(context.lastAttempt, name: exercise.name))
        // PR 10B — autoregulation: fold the multi-week completion pattern
        // in. Soften (−5%) or amplify (+5 lb) ride on top of the base
        // decision; stepDown is never overridden (see AutoregulationEngine
        // doc — an injury-risk signal outranks the optimistic aggregate,
        // so `effectiveDecision` is always the base decision here and the
        // amplify add is skipped when it fired).
        let adjustment = AutoregulationEngine.classify(
            ExerciseKey.lookup(context.attemptHistory, name: exercise.name) ?? []
        )
        var target = targetLb(
            priorWeight: prior.weight,
            priorReps: prior.reps,
            prescribedReps: prescribedReps,
            decision: decision
        )
        if !(decision == .stepDown && adjustment.isActive) {
            target = (target * adjustment.loadMultiplier) + adjustment.flatAddLb
        }
        return formatTargetHint(weightLb: target, memory: memory)
    }

    /// Rep-mapped load with the progression decision applied.
    /// `progressiveTargetLb` stays as the step-up-only form for its existing
    /// tests; this is the general one.
    static func targetLb(priorWeight: Double, priorReps: Int, prescribedReps: String,
                         decision: ProgressionDecision) -> Double {
        let base: Double
        if priorReps > 0, let targetReps = repBandMidpoint(prescribedReps) {
            let e1rm = StrengthStandards.epley1RM(weight: priorWeight, reps: priorReps)
            base = e1rm / (1 + Double(targetReps) / 30.0)
        } else {
            base = priorWeight
        }
        let scaled = (base * decision.loadMultiplier / 2.5).rounded() * 2.5
        // A step-up never lands below the rep-mapped base (matches
        // steppedTargetLb); a hold or step-down may.
        return decision == .stepUp ? max(base, scaled) : scaled
    }

    /// Target working load for the prescribed rep band, progressed 2.5%.
    /// `priorBest` is the heaviest set at ANY rep count, so a 3-rep top set
    /// must NOT be shown as the target for a 12-rep prescription. Estimate 1RM
    /// (Epley) from the prior set, then map it back down to the band's midpoint
    /// reps before the step-up: 225×3 → e1RM ~248 → ~195 lb for a 6-12 set
    /// (vs the old rep-blind 230). Returns nil when the band has no numeric
    /// reps (AMRAP, "30s hold") so the caller falls back to the raw stepped
    /// prior weight. Internal for testability.
    static func progressiveTargetLb(priorWeight: Double, priorReps: Int, prescribedReps: String) -> Double? {
        guard priorReps > 0, let targetReps = repBandMidpoint(prescribedReps) else { return nil }
        let e1rm = StrengthStandards.epley1RM(weight: priorWeight, reps: priorReps)
        let loadForReps = e1rm / (1 + Double(targetReps) / 30.0)
        return steppedTargetLb(priorWeightLb: loadForReps)
    }

    /// Midpoint rep count of a prescription string: "5" → 5, "6-12" → 9,
    /// "8-15" → 12. Returns nil for non-numeric bands ("AMRAP", "30s hold").
    static func repBandMidpoint(_ reps: String) -> Int? {
        let parts = reps.split(separator: "-")
        if parts.count == 1, let r = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
            return r
        }
        if parts.count == 2,
           let lo = Int(parts[0].trimmingCharacters(in: .whitespaces)),
           let hi = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
            return Int((Double(lo + hi) / 2).rounded())
        }
        return nil
    }

    /// 2.5% step-up snapped to the nearest 2.5 lb, floored at the prior
    /// weight. Internal for testability. Rounding to 2.5 (not 5) lets mid
    /// loads progress — a 5-lb grid zeroed the 2.5% step for every working
    /// weight <= 100 lb (e.g. 95 -> 95, 100 -> 100). Loads under ~50 lb still
    /// no-op, which is intended: you can't micro-load below the smallest
    /// plate, so progression there comes from reps/RPE, not added weight.
    static func steppedTargetLb(priorWeightLb w: Double) -> Double {
        let stepped = (w * 1.025 / 2.5).rounded() * 2.5
        return max(w, stepped)
    }

    /// The note is a LOAD to work up to at the prescribed reps shown on the
    /// row — NOT a rep prescription, so it omits a rep count. The prior-best
    /// reps (often a low-rep top set) contradicted the row's focus band
    /// ("target 230 × 3" over a "6-12" set). Deeper open issue: the load isn't
    /// yet adjusted to the prescribed rep range — see docs/generator-audit.md.
    private static func formatTargetHint(weightLb: Double, memory: TrainingMemory) -> String {
        let display: String
        if memory.usesImperial {
            let snapped = (weightLb * 2).rounded() / 2   // nearest 0.5 lb
            let wStr = snapped == snapped.rounded() ? "\(Int(snapped))" : "\(snapped)"
            display = "\(wStr) lb"
        } else {
            let kg = BodyMetrics.lbToKg(weightLb)
            display = "\(Int(kg.rounded())) kg"
        }
        return "target: \(display)"
    }
}
