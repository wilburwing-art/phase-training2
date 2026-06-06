// WorkoutGenerator+Prescription.swift
//
// Extracted from WorkoutGenerator.swift (Tier-3 god-object split). Pure
// prescription / RPE / progressive-overload math — no state, no orchestration; the generation loop in
// WorkoutGenerator.swift calls into these as a focused seam.

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
        guard let prior = context.priorBest[key] else { return nil }
        // Bodyweight movement (weight 0): a load target is meaningless, so
        // progress by REPS — beat the best set by one rep. (T2.1)
        if prior.weight == 0 {
            return prior.reps > 0 ? "target: \(prior.reps + 1) reps" : nil
        }
        let target = progressiveTargetLb(
            priorWeight: prior.weight,
            priorReps: prior.reps,
            prescribedReps: prescribedReps
        ) ?? steppedTargetLb(priorWeightLb: prior.weight)
        return formatTargetHint(weightLb: target, memory: memory)
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

    /// RPE + tempo hints for a picked exercise. Defaults driven by the
    /// user's primaryFocus + the slot position (primary compound vs
    /// accessory). LLM strategy overrides win per-exercise.
    ///
    /// RPE scale: 1-10 where 10 is true failure. Hypertrophy lives in the
    /// 7-9 range; strength in 8-9; endurance in 5-7. Mobility skips RPE
    /// entirely (the cue doesn't translate to slow controlled work).
    ///
    /// Tempo is the 4-digit eccentric/pause/concentric/pause string. "X"
    /// in any slot means explosive — used for power work.
    static func rpeTempoHints(
        for exercise: Exercise,
        slotIdx: Int,
        focus: WorkoutFocus,
        memory: TrainingMemory,
        strategy: GeneratorStrategy = .auto
    ) -> (rpe: String?, tempo: String?) {
        let key = exercise.name.lowercased()
        // LLM overrides win whenever set.
        let overrideRpe = strategy.rpeOverrides[key]
        let overrideTempo = strategy.tempoOverrides[key]
        if overrideRpe != nil || overrideTempo != nil {
            return (overrideRpe, overrideTempo)
        }

        let isPrimary = slotIdx == 0
        let isCompound = exercise.isCompound

        // Default scheme keyed on primaryFocus. Primary compounds get a
        // slightly heavier RPE than accessories in every category.
        let rpe: String
        let tempo: String
        switch memory.primaryFocus {
        case .generalStrength:
            rpe = isPrimary ? "8" : "7-8"
            tempo = isCompound ? "2-0-1-0" : "2-1-1-0"
        case .hypertrophy:
            rpe = isPrimary ? "8-9" : "7-9"
            tempo = isCompound ? "3-0-1-0" : "3-1-1-0"
        case .sportPerformance:
            rpe = isPrimary ? "7-8" : "7"
            // Power emphasis: explosive concentric on compound primary work.
            tempo = isCompound && isPrimary ? "2-0-X-0" : "2-0-1-0"
        case .endurance:
            rpe = isPrimary ? "6-7" : "5-7"
            tempo = "1-0-1-0"
        case .weightLoss:
            rpe = isPrimary ? "7-8" : "7"
            tempo = "2-0-1-0"
        case .longevity:
            rpe = isPrimary ? "7" : "6-7"
            tempo = "3-1-1-1"
        }

        // Sore-area RPE cap: when the exercise's prime mover matches a
        // recent SorenessEntry at mild+ severity, the generator already
        // picked a softer movement (the recentSoreAreas filter in
        // pickForSlot prefers exercises that don't load the sore muscle as
        // primary). But the prescription still defaults to the focus's
        // standard intensity, which sends the user into RPE 8-9 work on a
        // sore chest — the eval rig's Q9 catches this. Cap to RPE 7 (3 RIR)
        // whenever the prime mover IS still sore at mild+, so the
        // intensity matches the movement softening.
        if isMuscleSoreForExercise(exercise, memory: memory) {
            return (rpe: "7", tempo: tempo)
        }

        // Beginner intensity guardrail (T1.5): a novice grooving technique
        // shouldn't be sent into RPE 8-9 grinders. Cap RPE to ≤7 (≥3 RIR)
        // across all lifts. Composes with the readiness compound cap applied
        // downstream in the main loop. (LLM rpeOverrides return early above,
        // so they keep last say; they're still readiness-capped downstream.)
        let cappedRpe = memory.experience == .beginner ? capRPE(rpe, to: 7.0) : rpe
        return (cappedRpe, tempo)
    }

    // MARK: - Prescription

    /// Decide sets / reps / rest for the picked exercise. Honors coach.db's
    /// expert defaults when present, adjusted by experience + age. Position
    /// 0 (primary compound) gets the heaviest scheme.
    ///
    /// Closes leak #3 from the loop audit: when `memory.primaryFocus` has a
    /// rep-scheme bias (hypertrophy, sport performance, endurance, etc.),
    /// the focus overrides coach.db reps + rest defaults. Lifters who said
    /// "I want hypertrophy" used to get the same 5×5 every workout because
    /// the generator only consumed focus to pick a movement-pattern shape.
    static func prescription(
        for exercise: Exercise,
        slotIdx: Int,
        focus: WorkoutFocus,
        memory: TrainingMemory,
        profile: DemographicProfile
    ) -> (sets: Int, reps: String, restSec: Int) {
        let isPrimary = slotIdx == 0
        let isCompound = exercise.isCompound

        // Focus-driven bias from the user's primary training focus.
        let bias = focusBias(memory.primaryFocus, isPrimary: isPrimary)

        // Sets — prefer the focus bias when present, otherwise fall back to
        // coach.db default, then the formula. Then apply experience + age
        // clamps so an advanced lifter gets the bias's full count but a
        // beginner stays capped at 3.
        var sets = bias?.sets
            ?? exercise.defaultSets
            ?? defaultSetsFromFormula(isPrimary: isPrimary, isCompound: isCompound)
        switch memory.experience {
        case .beginner:     sets = min(sets, 3)
        case .intermediate: sets = min(sets, 4)
        // Advanced earns +1 work set on COMPOUNDS over the intermediate clamp
        // (T1.6) — the old `break` left advanced ≡ intermediate whenever the raw
        // bias was already ≤4. Built on the intermediate clamp so it tops out at
        // 5: the canonical 5×5 stays 5 (general-strength raw 5 → min(5,4)+1 = 5),
        // while a raw-4 hypertrophy compound steps 4 → 5. Isolations keep the raw
        // bias (unchanged from the prior `break`).
        case .advanced:     if isCompound { sets = min(sets, 4) + 1 }
        }
        if let age = memory.age, age >= 55 {
            sets = max(1, sets - 1)
        }
        // 70+ earns an additional set reduction on top of the 55+ one (T2.2):
        // cumulative effect is -2 from the base, reflecting the tighter
        // recovery window and power-over-volume programming intent.
        if let age = memory.age, age >= 70 {
            sets = max(1, sets - 1)
        }

        // Reps + rest. Focus bias wins over per-exercise coach.db values —
        // a hypertrophy lifter should see 8-12 on every lift even if coach.db
        // tagged bench as "5". Fallback path is preserved as a safety net in
        // case a future focus addition forgets to populate the bias table.
        let reps: String
        var restSec: Int
        if let bias = bias {
            reps = bias.reps
            restSec = bias.restSec
        } else {
            reps = exercise.defaultReps?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                ?? defaultRepsFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)
            restSec = exercise.defaultRest.flatMap(parseRestSeconds)
                ?? defaultRestFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)
        }

        // Hypertrophy's default 90s rest is too short on heavy compound
        // lower-body work — eval-rig's lower-body Q7 expects 3-4 min on the
        // squat slot. Bump primary compound lower-body rest to 180s without
        // disturbing upper-push (90s is fine for bench / OHP). Full-body
        // days (A: squat-first / B: hinge-first) lead with the same heavy
        // compound lower-body movement and get the same treatment.
        if memory.primaryFocus == .hypertrophy
            && isPrimary && isCompound
            && (focus == .lower || focus == .legs
                || focus == .fullBodyA || focus == .fullBodyB) {
            restSec = max(restSec, 180)
        }

        // Hypertrophy compound pull (weighted pull-up / heavy row /
        // deadlift) sits between upper-push and squat for systemic load —
        // 2-3 min rest is the modern guidance, eval-rig's pull Q7 enforces
        // it. Bump compound pull primary to 120s. Picks up focus.pull
        // (PPL split) but NOT focus.upper (which mixes vertical/horizontal
        // push + pull — 90s default stays right for that aggregate).
        if memory.primaryFocus == .hypertrophy
            && isPrimary && isCompound
            && focus == .pull {
            restSec = max(restSec, 120)
        }

        // Rest differentiates COMPOUNDS from ISOLATIONS by movement type, not
        // just by slot position. The primary bumps above cover slot 0; a
        // SECONDARY compound (RDL, row, lunge) otherwise inherits the accessory
        // rest floor — the same as an isolation — which eval-rig Q7 (rest
        // differentiation, graded on every multi-archetype rubric) flags. Lift
        // secondary compounds to the focus's primary-rest tier so every
        // compound rests longer than every isolation. Isolations are untouched;
        // the extra per-set time still flows through the loop's time-budget
        // check, which drops optional slots to keep the session in budget.
        if isCompound, !isPrimary,
           let primaryRest = focusBias(memory.primaryFocus, isPrimary: true)?.restSec {
            restSec = max(restSec, primaryRest)
        }

        // Phase-1 era-affinity rep-range nudge.
        //
        // Only applies when memory.primaryFocus is .hypertrophy — that's
        // the focus most flavored by era (bro-split mid reps vs PPL low
        // reps vs current-meta high reps on isolation). Strength /
        // sport-performance / endurance focuses have their own
        // load-intent intent that should NOT be overridden by aesthetic
        // affinity (orthogonality rule:
        // phase-training-personalization-three-axes skill).
        //
        // For .hypertrophy users the era picks the rep band: low / mid /
        // high. Primary compound uses .compound band, accessories use
        // .isolation band. Sets + rest stay as focusBias computed them —
        // only the rep STRING is replaced.
        // Time / distance / hold prescriptions (coach.db stores Wall Sit as
        // "30-60 sec", a loaded carry as "40-60 ft", a hang as "5-10 sec hold")
        // are NOT rep counts, so the focus-bias and era numeric bands must not
        // overwrite them — preserve the native prescription. Without this a
        // hypertrophy user saw Wall Sit / Battle Ropes / Reverse Plank as
        // "8-15" reps. 71 catalog exercises are affected. (T1.2)
        let exerciseReps = exercise.defaultReps?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let finalReps: String
        if let exerciseReps, !isNumericRepBand(exerciseReps) {
            finalReps = exerciseReps
        } else if let eraStyle = profile.eraStyle, memory.primaryFocus == .hypertrophy {
            let band = (isPrimary && isCompound)
                ? eraStyle.repRangeBias.compound
                : eraStyle.repRangeBias.isolation
            finalReps = band.display
        } else {
            finalReps = reps
        }

        // Beginner rep floor (T1.5): keep novices out of sub-6-rep near-max
        // work. Only numeric bands are floored — time/distance prescriptions
        // (T1.2) pass through untouched. NOTE: this also raises a 5-rep scheme
        // to 6-8, so canonical novice 5×5 linear progression is nudged toward
        // a hypertrophy range — revisit if you want to special-case 5×5.
        let outReps = memory.experience == .beginner ? beginnerRepFloor(finalReps) : finalReps
        return (sets, outReps, restSec)
    }

    /// Map the user's stated goal to a coherent sets × reps × rest scheme.
    /// Primary compound gets a heavier scheme than accessories within the
    /// same focus. Returns nil only when the focus genuinely has no opinion
    /// on volume — currently just `mobility` (mobility lifts run on hold-
    /// style defaults in the mobility branch above).
    ///
    /// Schemes target the consensus middle of evidence-based programming:
    /// hypertrophy 6-15 + 60-90s rest, strength 3-6 + 2-3min, endurance
    /// 10-20 + 30-60s. Build 97 added sets to the contract — the old
    /// version only adjusted reps + rest, so a hypertrophy day still
    /// got coach.db's per-exercise set count which varied wildly (bench
    /// 5 sets, fly 3 sets) and made workouts feel inconsistent.
    /// `generalStrength` went from nil → a real 4-5 set strength scheme;
    /// previously it inherited coach.db defaults which mixed strength
    /// and hypertrophy schemes in the same workout.
    static func focusBias(_ focus: PrimaryFocus, isPrimary: Bool) -> (sets: Int, reps: String, restSec: Int)? {
        switch focus {
        case .generalStrength:
            // True strength: low-rep heavy work, long rest. 5×5 on the
            // primary lift, 3×6-8 on accessories.
            return (sets: isPrimary ? 5 : 3,
                    reps: isPrimary ? "5" : "6-8",
                    restSec: isPrimary ? 180 : 120)
        case .hypertrophy:
            // Slightly wider rep range than build 96 — modern guidance is
            // 5-30 reps drives growth, so 6-12 primary / 8-15 accessory
            // captures the "effort matters more than load" middle.
            return (sets: isPrimary ? 4 : 3,
                    reps: isPrimary ? "6-12" : "8-15",
                    restSec: isPrimary ? 90 : 60)
        case .sportPerformance:
            // Power scheme — heavy doubles/triples need volume across sets
            // to drive adaptation. Same rep range, more sets than the
            // previous default (which gave only 3-4 sets via coach.db).
            return (sets: isPrimary ? 5 : 3,
                    reps: isPrimary ? "3-5" : "5-8",
                    restSec: isPrimary ? 180 : 120)
        case .endurance:
            return (sets: isPrimary ? 3 : 3,
                    reps: isPrimary ? "10-15" : "12-20",
                    restSec: isPrimary ? 60 : 45)
        case .weightLoss:
            // Circuit-friendly volume — keep sets moderate so total time
            // stays short and density stays high.
            return (sets: 3,
                    reps: isPrimary ? "8-12" : "10-15",
                    restSec: 60)
        case .longevity:
            // Lower volume, controlled tempo. Hits the stimulus floor
            // without overreaching.
            return (sets: 3,
                    reps: isPrimary ? "5-8" : "8-10",
                    restSec: 90)
        }
    }

    /// A plain rep prescription — a count ("5") or numeric range ("6-12").
    /// Everything else coach.db stores (time "30-60 sec", distance "40-60 ft",
    /// holds "5-10 sec hold", "AMRAP") is a non-rep prescription the focus-bias
    /// / era numeric band must NOT overwrite. (T1.2)
    static func isNumericRepBand(_ s: String) -> Bool {
        s.range(of: #"^\d+(\s*-\s*\d+)?$"#, options: .regularExpression) != nil
    }

    /// Raise a numeric rep band whose low end is below 6 to "6-8" so beginners
    /// groove technique in moderate ranges rather than near-max triples.
    /// Non-numeric prescriptions (time/distance/hold) and bands already ≥6
    /// pass through unchanged. (T1.5)
    static func beginnerRepFloor(_ reps: String) -> String {
        guard isNumericRepBand(reps) else { return reps }
        let lows = reps.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let low = lows.first else { return reps }
        return low < 6 ? "6-8" : reps
    }

    private static func defaultSetsFromFormula(isPrimary: Bool, isCompound: Bool) -> Int {
        if isPrimary && isCompound { return 4 }
        if isCompound              { return 3 }
        return 3
    }

    private static func defaultRepsFromFormula(isPrimary: Bool, isCompound: Bool, focus: WorkoutFocus) -> String {
        if isPrimary && isCompound { return "5-6" }
        if isCompound              { return "6-8" }
        return "10-12"
    }

    private static func defaultRestFromFormula(isPrimary: Bool, isCompound: Bool, focus: WorkoutFocus) -> Int {
        if isPrimary && isCompound { return 120 }
        if isCompound              { return 90 }
        return 60
    }

    /// Parse coach.db's free-form rest text ("90s", "2 min", "1:30") into seconds.
    private static func parseRestSeconds(_ s: String) -> Int? {
        let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.isEmpty { return nil }
        if lower.contains(":") {
            let parts = lower.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
        }
        let digits = lower.prefix(while: { $0.isNumber || $0 == "." })
        guard let n = Double(digits) else { return nil }
        if lower.contains("min") { return Int(n * 60) }
        return Int(n)
    }
}
