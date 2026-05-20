// WorkoutGenerator.swift — composes a workout exercise-by-exercise from
// coach.db, shaped by the user's DemographicProfile + a movement-pattern
// recipe. Replaces the previous "pick one bundled routine" path for lift +
// mobility days in the planner.
//
// Bundled routines are still browsable in the routine library as inspiration
// and remain the source for explicit dayOverrides + the custom-workout
// builder. The weekly plan itself is generated.
//
// Generation is deterministic: same TrainingMemory + lift index + total
// lifts always yields the same workout. The planner's inputsHash drift
// detector still works because every id derives from (hash, slot, exercise).
//
// Algorithm:
//   1. Choose a WorkoutFocus from (liftIndex, totalLifts).
//      - 0-1 lifts → fullBodyA
//      - 2        → A / B
//      - 3        → push / pull / legs
//      - 4        → upper / lower / upper / lower
//      - 5+       → push / pull / legs / upper / lower rotation
//   2. Walk the focus's pattern slot recipe. Each slot lists 1+ alternative
//      pattern slugs; the first slug with non-empty candidate set wins.
//   3. Pick deterministically from candidates using hash + slotIndex.
//   4. Assign sets / reps / rest from coach.db defaults when present,
//      adjusted by experience + age. Heavy compound at position 1 gets
//      higher sets and longer rest; isolation at the back gets shorter.
//   5. Drop optional slots that would push estimated duration past
//      `memory.sessionMinutes - warmup buffer`.

import Foundation

enum WorkoutGenerator {

    // MARK: - Public API

    /// Generate a lift day's workout.
    ///
    /// `context` carries runtime-history signals — defaults to `.empty` so
    /// every existing caller works unchanged. When populated (build 66+)
    /// the generator emits progressive-overload weight targets, biases
    /// against recently-sore body areas, prefers under-trained patterns,
    /// and swaps stagnant canonical lifts for substitutes.
    ///
    /// `strategy` is the LLM-supplied override layer (build 68+). Defaults
    /// to `.auto` (identity — generator behaves exactly as before). When
    /// the LLM coach calls `build_workout`, it produces a strategy that
    /// flows in here and shifts the focus / pattern emphasis / intensity.
    static func generateLift(
        liftIndex: Int,
        totalLifts: Int,
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        recentlyPicked: Set<Int> = [],
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> GeneratedWorkout {
        // Strategy's focus wins over the (liftIndex, totalLifts) derivation
        // when set — the LLM can explicitly ask for "push day" even on what
        // would normally be a leg slot.
        let focus = strategy.focus ?? WorkoutFocus.lift(liftIndex: liftIndex, totalLifts: totalLifts)
        return generate(focus: focus, memory: memory, profile: profile,
                        hashSeed: hashSeed, liftIndex: liftIndex,
                        totalLifts: totalLifts, recentlyPicked: recentlyPicked,
                        context: context, strategy: strategy)
    }

    /// Generate a mobility day's flow.
    static func generateMobility(
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        recentlyPicked: Set<Int> = [],
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> GeneratedWorkout {
        generate(focus: .mobility, memory: memory, profile: profile,
                 hashSeed: hashSeed, liftIndex: 0, totalLifts: 0,
                 recentlyPicked: recentlyPicked, context: context,
                 strategy: strategy)
    }

    // MARK: - Core loop

    private static func generate(
        focus: WorkoutFocus,
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        liftIndex: Int,
        totalLifts: Int,
        recentlyPicked: Set<Int>,
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> GeneratedWorkout {
        // Strategy's duration override beats memory's default. Clamped to
        // [15, 180] so a hallucinated 9999 doesn't produce a 10-hour workout.
        let effectiveMinutes: Int = {
            if let m = strategy.durationMinutes { return min(180, max(15, m)) }
            return memory.sessionMinutes
        }()
        let budgetSec = max(15 * 60, effectiveMinutes * 60 - warmupBufferSec)
        var elapsedSec = 0
        // Union of: exercises already picked in THIS workout (dedup within
        // session) + exercises the user's injuries contraindicate.
        var pickedIds: Set<Int> = profile.excludedExerciseIds
        var picks: [GeneratedExercise] = []

        // Constraints applied at the SQL boundary.
        let envs = profile.allowedEnvironments
        let excludeKws = profile.excludedNameKeywords + memory.dislikes.map { $0.lowercased() }

        for (slotIdx, slot) in focus.slots.enumerated() {
            guard let initial = pickForSlot(
                slot: slot,
                slotIdx: slotIdx,
                profile: profile,
                envs: envs,
                excludeKws: excludeKws,
                excludeIds: pickedIds,
                recentlyPicked: recentlyPicked,
                hashSeed: hashSeed,
                context: context,
                strategy: strategy
            ) else { continue }

            // Stagnation swap: if the user's pick is on the stagnant list
            // (canonical lift with no PR in 4 weeks) and a substitute is
            // available + still within their constraints, prefer the swap.
            let picked = applyStagnationSwap(
                original: initial,
                context: context,
                envs: envs,
                excludeKws: excludeKws,
                excludeIds: pickedIds,
                slot: slot
            )

            let (baseSets, reps, restSec) = prescription(
                for: picked,
                slotIdx: slotIdx,
                focus: focus,
                memory: memory,
                profile: profile
            )
            // Apply LLM-supplied intensity multiplier — guarded so a hostile
            // strategy can't produce 0 sets or runaway volume.
            let sets = max(1, min(8, Int((Double(baseSets) * strategy.intensityBias.setsMultiplier).rounded())))

            let durSec = sets * (45 + restSec) + 30   // ~45s work + rest + 30s transition

            // Optional slots that bust the budget get dropped; required slots
            // override (we'd rather give a slightly-over workout than skip a
            // primary compound).
            if elapsedSec + durSec > budgetSec, slot.optional, !picks.isEmpty {
                continue
            }

            // Progressive-overload target: when the user has a prior best
            // for this exercise, emit it in notes so the LogScreen can
            // surface a coaching prompt above the autofill column. LLM
            // strategy can override the target ("bench at 90% today").
            let notes = progressiveOverloadHint(for: picked, context: context, memory: memory, strategy: strategy)
            // RPE + tempo prescription (build 70). Defaults from focus +
            // slot position; LLM strategy overrides win per-exercise.
            let (rpe, tempo) = rpeTempoHints(
                for: picked,
                slotIdx: slotIdx,
                focus: focus,
                memory: memory,
                strategy: strategy
            )

            picks.append(GeneratedExercise(
                id: "\(hashSeed)-\(slotIdx)-\(picked.id)",
                exerciseId: picked.id,
                name: picked.name,
                pattern: slot.satisfiedBy,
                isCompound: picked.isCompound,
                sets: sets,
                reps: reps,
                restSeconds: restSec,
                notes: notes,
                rpe: rpe,
                tempo: tempo
            ))
            pickedIds.insert(picked.id)
            elapsedSec += durSec
        }

        let estMin = max(1, Int((Double(elapsedSec) / 60.0).rounded()))
        let summary = "\(picks.count) movements · ~\(estMin) min"
        let prov = provenanceLine(
            focus: focus,
            memory: memory,
            liftIndex: liftIndex,
            totalLifts: totalLifts
        )

        return GeneratedWorkout(
            title: focus.title,
            summary: summary,
            exercises: picks,
            estimatedMinutes: estMin,
            provenance: prov
        )
    }

    // MARK: - Slot fulfillment

    /// Walk the alternative patterns in a slot, return the first picked
    /// exercise. Variety soft-filter: when the candidate pool has any
    /// not-recently-picked entries, restrict the pick to those. When the
    /// pool is entirely recent (small slot, well-worn user), fall back to
    /// the full pool — we'd rather repeat than leave the slot empty.
    private static func pickForSlot(
        slot: PatternSlot,
        slotIdx: Int,
        profile: DemographicProfile,
        envs: Set<String>,
        excludeKws: [String],
        excludeIds: Set<Int>,
        recentlyPicked: Set<Int>,
        hashSeed: String,
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> Exercise? {
        let applyVariety: ([Exercise]) -> [Exercise] = { candidates in
            guard !recentlyPicked.isEmpty else { return candidates }
            let fresh = candidates.filter { !recentlyPicked.contains($0.id) }
            return fresh.isEmpty ? candidates : fresh
        }

        // Apply sore-area exclude: drop exercises whose primary muscle group
        // matches anything in context.recentSoreAreas (case-insensitive
        // substring match against the muscle-group label, since user-typed
        // areas can be "knee" while coach.db labels are "Quadriceps").
        // Empty context = no filtering, preserves old behavior.
        let applySoreFilter: ([Exercise]) -> [Exercise] = { candidates in
            guard !context.recentSoreAreas.isEmpty else { return candidates }
            return candidates.filter { ex in
                let muscles = CoachDatabase.shared.musclesForExercise(ex.id)
                    .filter { $0.role == "primary" }
                    .map { $0.label.lowercased() }
                for area in context.recentSoreAreas {
                    if muscles.contains(where: { $0.contains(area) || area.contains($0) }) {
                        return false
                    }
                }
                return true
            }
        }

        // Reorder slot.alternatives. Two layers:
        //   1. LLM strategy (emphasize / deprioritize) — definitive: an
        //      emphasized pattern jumps to the front; a deprioritized one
        //      is dropped from consideration (the slot can fall through if
        //      ALL its alternatives are deprioritized — fine, the LLM can
        //      do that on purpose).
        //   2. Context-derived frequency boost — under-trained patterns
        //      lift higher within whatever survives layer 1.
        var alternatives = slot.alternatives
        if !strategy.deprioritizePatterns.isEmpty {
            alternatives.removeAll(where: { strategy.deprioritizePatterns.contains($0) })
        }
        if !strategy.emphasizePatterns.isEmpty {
            // Stable partition: emphasized ones first (preserving relative
            // order), the rest after.
            let emphasized = alternatives.filter { strategy.emphasizePatterns.contains($0) }
            let rest = alternatives.filter { !strategy.emphasizePatterns.contains($0) }
            alternatives = emphasized + rest
        }
        alternatives = reorderByPatternFrequency(alternatives, context: context)

        for pattern in alternatives {
            // Try preferred difficulties first, then fall back across the
            // whole allowed set (so a beginner-only catalog still returns
            // something for an advanced user).
            for bucket in profile.preferredDifficulties {
                let raw = CoachDatabase.shared.exercises(
                    matchingPattern: pattern,
                    difficulties: [bucket],
                    environments: envs,
                    excludeKeywords: excludeKws,
                    excludeIds: excludeIds,
                    modalities: slot.requiredModalities
                )
                let candidates = applySoreFilter(raw)
                if let pick = deterministicPick(from: applyVariety(candidates), slotIdx: slotIdx, hashSeed: hashSeed) {
                    slot.satisfiedBy = pattern
                    return pick
                }
            }
            // Difficulty-relaxed pass — env + constraints still hold.
            let relaxedRaw = CoachDatabase.shared.exercises(
                matchingPattern: pattern,
                environments: envs,
                excludeKeywords: excludeKws,
                excludeIds: excludeIds,
                modalities: slot.requiredModalities
            )
            let relaxed = applySoreFilter(relaxedRaw)
            if let pick = deterministicPick(from: applyVariety(relaxed), slotIdx: slotIdx, hashSeed: hashSeed) {
                slot.satisfiedBy = pattern
                return pick
            }
        }
        return nil
    }

    /// Boost under-trained patterns by sorting `slot.alternatives` so the
    /// pattern with the lowest count in `context.patternFrequency` (or absent
    /// from it entirely) comes first. Stable for an empty context (returns
    /// original order). Does NOT add new patterns — only reorders what the
    /// slot already declares.
    private static func reorderByPatternFrequency(
        _ alternatives: [String],
        context: GeneratorContext
    ) -> [String] {
        guard !context.patternFrequency.isEmpty, alternatives.count > 1 else {
            return alternatives
        }
        return alternatives.enumerated()
            .sorted { lhs, rhs in
                let leftCount = context.patternFrequency[lhs.element] ?? 0
                let rightCount = context.patternFrequency[rhs.element] ?? 0
                if leftCount != rightCount { return leftCount < rightCount }
                return lhs.offset < rhs.offset   // stable tiebreaker
            }
            .map(\.element)
    }

    /// If the initial pick is flagged stagnant (no PR in 4w), try to swap
    /// it for the highest-scoring substitute that still passes the same
    /// constraints. Returns the original pick when no acceptable swap
    /// exists. Conservative — won't bust env / dislike / injury filters.
    private static func applyStagnationSwap(
        original: Exercise,
        context: GeneratorContext,
        envs: Set<String>,
        excludeKws: [String],
        excludeIds: Set<Int>,
        slot: PatternSlot
    ) -> Exercise {
        guard context.stagnantExercises.contains(original.name.lowercased()) else {
            return original
        }
        let substitutes = CoachDatabase.shared.substitutes(forExerciseId: original.id)
        for sub in substitutes {
            let candidate = sub.exercise
            if excludeIds.contains(candidate.id) { continue }
            // Env filter: empty envs = no restriction (e.g. fullGym user).
            if !envs.isEmpty, let env = candidate.environment, !envs.contains(env) {
                continue
            }
            // Dislike-keyword filter.
            let lowerName = candidate.name.lowercased()
            if excludeKws.contains(where: { lowerName.contains($0) }) { continue }
            // Modality filter from the slot.
            if !slot.requiredModalities.isEmpty,
               let mod = candidate.modality,
               !slot.requiredModalities.contains(mod) {
                continue
            }
            return candidate
        }
        return original
    }

    /// "target: 230 lb × 5" style hint. Priority order:
    ///   1. LLM strategy targetWeightOverrides — explicit prescriptions ("bench at 90%").
    ///   2. Context priorBest + 2.5% step-up — progressive overload from history.
    ///   3. Nothing — no signal, no note.
    private static func progressiveOverloadHint(
        for exercise: Exercise,
        context: GeneratorContext,
        memory: TrainingMemory,
        strategy: GeneratorStrategy = .auto
    ) -> String? {
        let key = exercise.name.lowercased()
        // Layer 1: explicit LLM override.
        if let override = strategy.targetWeightOverrides[key] {
            // Reps for the override default to the prior best's reps when
            // available — the LLM is suggesting a load, not a rep scheme.
            let reps = context.priorBest[key]?.reps ?? 5
            return formatTargetHint(weightLb: override, reps: reps, memory: memory)
        }
        // Layer 2: priorBest + step-up.
        guard let prior = context.priorBest[key] else { return nil }
        // Small step-up — 2.5% rounded to nearest 5 lb, or the same weight
        // back if the user is below the floor. Conservative: we'd rather
        // prescribe last week's weight than push too hard blindly.
        let stepped = (prior.weight * 1.025 / 5.0).rounded() * 5.0
        let target = max(prior.weight, stepped)
        return formatTargetHint(weightLb: target, reps: prior.reps, memory: memory)
    }

    private static func formatTargetHint(weightLb: Double, reps: Int, memory: TrainingMemory) -> String {
        let display: String
        if memory.usesImperial {
            display = "\(Int(weightLb)) lb × \(reps)"
        } else {
            let kg = BodyMetrics.lbToKg(weightLb)
            display = "\(Int(kg.rounded())) kg × \(reps)"
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

        // Mobility flows: no RPE; slow controlled tempo on every move.
        if focus == .mobility {
            return (nil, "3-1-3-0")
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
        case .mobility:
            // Mobility focus on a non-mobility day — still emphasize control.
            rpe = "6-7"
            tempo = "3-1-2-1"
        case .weightLoss:
            rpe = isPrimary ? "7-8" : "7"
            tempo = "2-0-1-0"
        case .longevity:
            rpe = isPrimary ? "7" : "6-7"
            tempo = "3-1-1-1"
        case .rehab:
            // Conservative — controlled tempo, sub-failure intensity.
            rpe = "5-6"
            tempo = "3-1-2-0"
        }
        return (rpe, tempo)
    }

    /// djb2 fold of (hashSeed + slotIdx) → modulo array size. Same machinery
    /// the routine picker uses so the same memory produces the same plan.
    private static func deterministicPick<T>(from arr: [T], slotIdx: Int, hashSeed: String) -> T? {
        guard !arr.isEmpty else { return nil }
        var folded: UInt64 = 5381
        for byte in hashSeed.utf8 { folded = (folded &* 33) &+ UInt64(byte) }
        folded = (folded &* 33) &+ UInt64(slotIdx)
        return arr[Int(folded % UInt64(arr.count))]
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

        // Sets — start from coach.db default, then clamp by experience + age.
        let defaultSets = exercise.defaultSets ?? defaultSetsFromFormula(isPrimary: isPrimary, isCompound: isCompound)
        var sets = defaultSets
        switch memory.experience {
        case .beginner:     sets = min(sets, 3)
        case .intermediate: sets = min(sets, 4)
        case .advanced:     break
        }
        if let age = memory.age, age >= 55 {
            sets = max(1, sets - 1)
        }
        // Mobility flows: cap at 2 sets so the day stays sustainable.
        if focus == .mobility { sets = min(sets, 2) }

        // Reps + rest.
        //
        // For mobility workouts: keep the hold-style defaults (existing path).
        // For everything else: when the user's primaryFocus carries a bias,
        // the bias wins over coach.db's per-exercise reps. We treat focus as
        // a coarse goal-setting knob — if you said "hypertrophy" every lift
        // should run in 8-12 reps, even if coach.db tagged Bench as "5".
        let reps: String
        let restSec: Int
        if focus == .mobility {
            reps = exercise.defaultReps?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                ?? defaultRepsFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)
            restSec = exercise.defaultRest.flatMap(parseRestSeconds)
                ?? defaultRestFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)
        } else if let bias = focusBias(memory.primaryFocus, isPrimary: isPrimary) {
            reps = bias.reps
            restSec = bias.restSec
        } else {
            reps = exercise.defaultReps?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                ?? defaultRepsFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)
            restSec = exercise.defaultRest.flatMap(parseRestSeconds)
                ?? defaultRestFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)
        }

        return (sets, reps, restSec)
    }

    /// Map the user's stated goal to a rep-scheme + rest interval. Returns
    /// nil when the focus is "no opinion" (general strength) — falls back to
    /// coach.db defaults + the movement-position formula. Primary compound
    /// gets a heavier scheme than accessories within the same focus.
    ///
    /// Schemes target the consensus middle of evidence-based programming:
    /// hypertrophy 6-12 + 60-90s rest, strength 1-6 + 2-3min, endurance
    /// 12-20 + 30-60s. Not gospel — directional defaults the coach can
    /// further tune via tool calls.
    static func focusBias(_ focus: PrimaryFocus, isPrimary: Bool) -> (reps: String, restSec: Int)? {
        switch focus {
        case .generalStrength:
            return nil
        case .hypertrophy:
            return (reps: isPrimary ? "6-10" : "8-12", restSec: isPrimary ? 90 : 60)
        case .sportPerformance:
            return (reps: isPrimary ? "3-5" : "5-8", restSec: isPrimary ? 180 : 120)
        case .endurance:
            return (reps: isPrimary ? "10-15" : "12-20", restSec: isPrimary ? 60 : 45)
        case .mobility:
            return nil
        case .weightLoss:
            return (reps: isPrimary ? "8-12" : "10-15", restSec: 60)
        case .longevity:
            return (reps: isPrimary ? "5-8" : "8-10", restSec: 90)
        case .rehab:
            return (reps: "10-12", restSec: 60)
        }
    }

    private static func defaultSetsFromFormula(isPrimary: Bool, isCompound: Bool) -> Int {
        if isPrimary && isCompound { return 4 }
        if isCompound              { return 3 }
        return 3
    }

    private static func defaultRepsFromFormula(isPrimary: Bool, isCompound: Bool, focus: WorkoutFocus) -> String {
        if focus == .mobility { return "30s hold" }
        if isPrimary && isCompound { return "5-6" }
        if isCompound              { return "6-8" }
        return "10-12"
    }

    private static func defaultRestFromFormula(isPrimary: Bool, isCompound: Bool, focus: WorkoutFocus) -> Int {
        if focus == .mobility { return 30 }
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

    private static let warmupBufferSec = 5 * 60

    // MARK: - Provenance copy

    private static func provenanceLine(
        focus: WorkoutFocus,
        memory: TrainingMemory,
        liftIndex: Int,
        totalLifts: Int
    ) -> String {
        let exp = memory.experience.label.lowercased()
        switch focus {
        case .mobility:
            return "Mobility flow for \(exp)"
        case .fullBodyA, .fullBodyB:
            return "Full-body day · tuned for \(exp)"
        case .push, .pull, .legs:
            return "Push / pull / legs day \(liftIndex + 1) of \(totalLifts) · \(exp)"
        case .upper, .lower:
            return "Upper / lower split day \(liftIndex + 1) of \(totalLifts) · \(exp)"
        }
    }
}

// MARK: - Workout focuses + slot recipes

enum WorkoutFocus: String, Hashable, Codable {
    case fullBodyA, fullBodyB
    case push, pull, legs
    case upper, lower
    case mobility

    static func lift(liftIndex: Int, totalLifts: Int) -> WorkoutFocus {
        switch totalLifts {
        case 0, 1:
            return .fullBodyA
        case 2:
            return liftIndex == 0 ? .fullBodyA : .fullBodyB
        case 3:
            switch liftIndex % 3 {
            case 0: return .push
            case 1: return .pull
            default: return .legs
            }
        case 4:
            return liftIndex % 2 == 0 ? .upper : .lower
        default:
            switch liftIndex % 5 {
            case 0: return .push
            case 1: return .pull
            case 2: return .legs
            case 3: return .upper
            default: return .lower
            }
        }
    }

    var title: String {
        switch self {
        case .fullBodyA: return "Full body A"
        case .fullBodyB: return "Full body B"
        case .push:      return "Push day"
        case .pull:      return "Pull day"
        case .legs:      return "Leg day"
        case .upper:     return "Upper body"
        case .lower:     return "Lower body"
        case .mobility:  return "Mobility flow"
        }
    }

    /// Ordered slot recipe. Generator walks top-down; for each slot it tries
    /// the alternative patterns in order and takes the first that yields a
    /// candidate. Optional slots get dropped if duration runs over.
    var slots: [PatternSlot] {
        switch self {
        case .fullBodyA:
            return [
                PatternSlot(alternatives: ["squat"],            optional: false),
                PatternSlot(alternatives: ["horizontal-push"],  optional: false),
                PatternSlot(alternatives: ["horizontal-pull"],  optional: false),
                PatternSlot(alternatives: ["anti-extension"],   optional: true),
                PatternSlot(alternatives: ["loaded-carry", "single-leg-squat"], optional: true)
            ]
        case .fullBodyB:
            return [
                PatternSlot(alternatives: ["hip-hinge"],        optional: false),
                PatternSlot(alternatives: ["vertical-push"],    optional: false),
                PatternSlot(alternatives: ["vertical-pull"],    optional: false),
                PatternSlot(alternatives: ["anti-rotation"],    optional: true),
                PatternSlot(alternatives: ["calf-raise", "single-leg-squat"], optional: true)
            ]
        case .push:
            return [
                PatternSlot(alternatives: ["horizontal-push"],        optional: false),
                PatternSlot(alternatives: ["vertical-push"],          optional: false),
                PatternSlot(alternatives: ["scapular-protraction"],   optional: true),
                PatternSlot(alternatives: ["elbow-extension"],        optional: true),
                PatternSlot(alternatives: ["anti-extension"],         optional: true)
            ]
        case .pull:
            return [
                PatternSlot(alternatives: ["vertical-pull"],          optional: false),
                PatternSlot(alternatives: ["horizontal-pull"],        optional: false),
                PatternSlot(alternatives: ["scapular-retraction"],    optional: true),
                PatternSlot(alternatives: ["elbow-flexion"],          optional: true),
                PatternSlot(alternatives: ["loaded-carry"],           optional: true)
            ]
        case .legs:
            return [
                PatternSlot(alternatives: ["squat"],                  optional: false),
                PatternSlot(alternatives: ["hip-hinge"],              optional: false),
                PatternSlot(alternatives: ["single-leg-squat"],       optional: true),
                PatternSlot(alternatives: ["calf-raise"],             optional: true),
                PatternSlot(alternatives: ["hip-abduction"],          optional: true)
            ]
        case .upper:
            return [
                PatternSlot(alternatives: ["horizontal-push"],        optional: false),
                PatternSlot(alternatives: ["horizontal-pull"],        optional: false),
                PatternSlot(alternatives: ["vertical-push"],          optional: false),
                PatternSlot(alternatives: ["vertical-pull"],          optional: false),
                PatternSlot(alternatives: ["anti-extension"],         optional: true)
            ]
        case .lower:
            return [
                PatternSlot(alternatives: ["squat"],                  optional: false),
                PatternSlot(alternatives: ["hip-hinge"],              optional: false),
                PatternSlot(alternatives: ["single-leg-squat"],       optional: true),
                PatternSlot(alternatives: ["calf-raise"],             optional: true),
                PatternSlot(alternatives: ["loaded-carry"],           optional: true)
            ]
        case .mobility:
            return [
                PatternSlot(alternatives: ["breathing-bracing"],      optional: false, modalities: ["mobility", "breathing", "recovery"]),
                PatternSlot(alternatives: ["anti-extension"],         optional: false, modalities: ["mobility", "recovery", "prehab"]),
                PatternSlot(alternatives: ["scapular-retraction"],    optional: true,  modalities: ["mobility", "prehab"]),
                PatternSlot(alternatives: ["hip-flexion"],            optional: true,  modalities: ["mobility", "prehab"]),
                PatternSlot(alternatives: ["hip-abduction"],          optional: true,  modalities: ["mobility", "prehab"])
            ]
        }
    }
}

/// One slot in a workout recipe. `alternatives` is a fallback list — first
/// pattern with candidates wins. `optional` slots are dropped if duration
/// over budget. `satisfiedBy` is set by the generator when it picks; used
/// downstream for the "Hip Hinge" badge in the UI.
final class PatternSlot {
    let alternatives: [String]
    let optional: Bool
    let requiredModalities: Set<String>
    var satisfiedBy: String? = nil

    init(alternatives: [String], optional: Bool, modalities: Set<String> = []) {
        self.alternatives = alternatives
        self.optional = optional
        self.requiredModalities = modalities
    }
}

// MARK: - Small string helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
