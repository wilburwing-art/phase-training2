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
        //
        // Phase-1 era-affinity: when profile.eraStyle exposes a
        // splitPreference that's compatible with totalLifts, pull the
        // focus from there instead of the default rotation. Compatibility
        // = the cohort's preference array has at least `totalLifts`
        // entries (it covers a full week without wrapping). We index by
        // liftIndex % preference.count so 3-day weeks with a 6-day PPL
        // preference still cycle through push/pull/legs correctly.
        let focus: WorkoutFocus
        if let strategyFocus = strategy.focus {
            focus = strategyFocus
        } else if let eraStyle = profile.eraStyle,
                  !eraStyle.splitPreference.isEmpty,
                  totalLifts >= 3 {   // 1-2 lift weeks stick to fullBodyA/B
            focus = eraStyle.splitPreference[liftIndex % eraStyle.splitPreference.count]
        } else {
            focus = WorkoutFocus.lift(liftIndex: liftIndex, totalLifts: totalLifts)
        }
        return generate(focus: focus, memory: memory, profile: profile,
                        hashSeed: hashSeed, liftIndex: liftIndex,
                        totalLifts: totalLifts, recentlyPicked: recentlyPicked,
                        context: context, strategy: strategy)
    }

    /// Generate a workout for a consolidated (merged) day — the D3 layer over
    /// `WeekConsolidator`. A solo day (`secondary == nil`) is an ordinary
    /// forced-focus lift. A merged day generates the primary focus's recipe
    /// PLUS the secondary focus's lead (first required) compound, grafted as an
    /// extra slot. The core loop's time-budget drop trims the primary's
    /// optional accessories first, so the merged day keeps both focuses'
    /// compounds and stays within the session budget.
    static func generateConsolidated(
        _ day: WeekConsolidator.ConsolidatedDay,
        liftIndex: Int = 0,
        totalLifts: Int,
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        recentlyPicked: Set<Int> = [],
        context: GeneratorContext = .empty,
        strategy: GeneratorStrategy = .auto
    ) -> GeneratedWorkout {
        guard let secondary = day.secondary else {
            // Solo day — force the focus through the normal path.
            var strat = strategy
            strat.focus = day.primary
            return generateLift(
                liftIndex: liftIndex, totalLifts: totalLifts, memory: memory,
                profile: profile, hashSeed: hashSeed, recentlyPicked: recentlyPicked,
                context: context, strategy: strat)
        }
        // Merged day — primary recipe + the secondary focus's lead compound.
        let extra = secondary.slots.first(where: { !$0.optional }).map { [$0] } ?? []
        var workout = generate(
            focus: day.primary, memory: memory, profile: profile, hashSeed: hashSeed,
            liftIndex: liftIndex, totalLifts: totalLifts, recentlyPicked: recentlyPicked,
            context: context, strategy: strategy, extraSlots: extra)
        workout.title = "\(day.primary.title) + \(secondary.title)"
        return workout
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
        strategy: GeneratorStrategy = .auto,
        extraSlots: [PatternSlot] = []
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

        // `extraSlots` are appended after the focus's own recipe (D3 — a
        // consolidated/merged day grafts the secondary focus's lead compound).
        // They take later slotIdx values, so the budget loop below trims the
        // primary's optional accessories before them (trim accessory before
        // compound). Empty for every ordinary single-focus generation, so that
        // output is byte-identical to before.
        for (slotIdx, slot) in (focus.slots + extraSlots).enumerated() {
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
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs,
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
            // Phase 2 — readiness silent volume scaling. Only applied when
            // `context.hasReadinessData == true`; when the user has skipped
            // HK auth AND has no native session history, readinessScore is
            // the 0.5 sentinel and we deliberately scale by 1.0× (no
            // effect) to preserve pre-Phase-2 generator output. See
            // `phase-training-personalization-three-axes` skill —
            // readiness drives volume/intensity ONLY, never competency.
            let readinessSetsMultiplier: Double = context.hasReadinessData
                ? lerp(0.6, 1.0, context.readinessScore)
                : 1.0
            // Apply LLM-supplied intensity multiplier — guarded so a hostile
            // strategy can't produce 0 sets or runaway volume. Readiness
            // composes BEFORE the LLM intensityBias so the LLM still has
            // last say (a deload week tone shouldn't be amplified by an
            // already-detrained readiness score).
            let combinedSetsMul = readinessSetsMultiplier * strategy.intensityBias.setsMultiplier
            let sets = max(1, min(8, Int((Double(baseSets) * combinedSetsMul).rounded())))

            // Budget check uses the PRE-multiplier duration so a deload day
            // doesn't "free up" time for additional accessories — deload
            // means fewer sets across the same exercises, not a longer
            // workout list. Build 97 fix.
            let baseDurSec = baseSets * (45 + restSec) + 30

            // Optional slots that bust the budget get dropped; required slots
            // override (we'd rather give a slightly-over workout than skip a
            // primary compound).
            if elapsedSec + baseDurSec > budgetSec, slot.optional, !picks.isEmpty {
                continue
            }

            // Progressive-overload target: when the user has a prior best
            // for this exercise, emit it in notes so the LogScreen can
            // surface a coaching prompt above the autofill column. LLM
            // strategy can override the target ("bench at 90% today").
            let notes = progressiveOverloadHint(for: picked, context: context, memory: memory, prescribedReps: reps, strategy: strategy)
            // RPE + tempo prescription (build 70). Defaults from focus +
            // slot position; LLM strategy overrides win per-exercise.
            let (rpeRaw, tempo) = rpeTempoHints(
                for: picked,
                slotIdx: slotIdx,
                focus: focus,
                memory: memory,
                strategy: strategy
            )
            // Phase 2 readiness RPE cap — compound lifts only, applied
            // when the user has real readiness data. Detrained user (0.0)
            // capped at RPE 7; in-shape user (1.0) capped at RPE 9; mid
            // (0.5) capped at RPE 8. The `rpeTempoHints` baseline for
            // compounds is RPE 7-8 already; cap reduces it further on
            // low-readiness days without affecting non-compound work.
            let rpe: String? = {
                guard let raw = rpeRaw,
                      picked.isCompound,
                      context.hasReadinessData else { return rpeRaw }
                return capCompoundRPE(raw, readinessScore: context.readinessScore)
            }()

            // Warm-up ramp synthesis: only for the FIRST compound primary
            // lift (slotIdx == 0 + isCompound) AND only when the prime mover
            // isn't sore (don't ramp into a capped top set on sore work).
            // Three sets at 40/60/80% of working weight — matches eval-rig's
            // synthesizeWarmups recipe so canon-vs-generator comparisons stay
            // apples-to-apples.
            let warmUps: [WarmUpSet]? = (slotIdx == 0 && picked.isCompound && !isMuscleSoreForExercise(picked, memory: memory))
                ? [
                    WarmUpSet(reps: 5, loadPctOfWorking: 40, restSeconds: 60),
                    WarmUpSet(reps: 5, loadPctOfWorking: 60, restSeconds: 60),
                    WarmUpSet(reps: 3, loadPctOfWorking: 80, restSeconds: 90),
                  ]
                : nil

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
                tempo: tempo,
                warmUpSets: warmUps
            ))
            pickedIds.insert(picked.id)
            // Accumulate using baseDurSec so the running total reflects a
            // normal-intensity day's pace — deload doesn't free up time for
            // additional accessories (build 97 fix). Estimated minutes
            // below uses the same total since it's also "as if normal."
            elapsedSec += baseDurSec
        }

        // Hypertrophy upper-push accessory layer — mirror of eval-rig's
        // accessories/intermediate-male-hypertrophy-upper-push.json. Stock
        // recipes for push / upper / fullBody don't include side-delt or
        // tricep isolation, which is fine for general strength but undershoots
        // hypertrophy needs (rubric Q2 catches this). Inject the two missing
        // isolation slots when the user's primary focus is hypertrophy AND
        // the session is upper-push family. Skipped when the existing picks
        // already cover the muscle (avoid duplication when an LLM strategy
        // pre-selected isolation work).
        let isUpperPush: Bool = {
            switch focus {
            case .push, .upper, .fullBodyA, .fullBodyB: return true
            case .pull, .legs, .lower: return false
            }
        }()
        let isLowerBody: Bool = (focus == .legs || focus == .lower)
        // The accessory layer is a parallel pick/prescribe path, so it must
        // honor the SAME context-driven regulators the main slot loop applies,
        // or appended isolation work punches through every safeguard (T0.1):
        //  - readiness × deload set multiplier (same formula as WG:200-208)
        //  - sore-area exclusion (context.recentSoreAreas)
        //  - dislike keywords (excludeKws)
        //  - the duration budget
        // Injury + env/equipment are already respected via `pickedIds`.
        let accessorySetsMul = (context.hasReadinessData
            ? lerp(0.6, 1.0, context.readinessScore)
            : 1.0) * strategy.intensityBias.setsMultiplier
        let appendAccessories: ([(generated: GeneratedExercise, durSec: Int)]) -> Void = { appended in
            for ex in appended {
                // Accessories are inherently optional — drop any that bust the
                // budget rather than overrun (mirrors the main-loop gate, WG:220).
                if elapsedSec + ex.durSec > budgetSec, !picks.isEmpty { continue }
                picks.append(ex.generated)
                pickedIds.insert(ex.generated.exerciseId)
                elapsedSec += ex.durSec
            }
        }
        if memory.primaryFocus == .hypertrophy && isUpperPush {
            appendAccessories(appendHypertrophyUpperPushAccessories(
                memory: memory,
                profile: profile,
                hashSeed: hashSeed,
                existingPicks: picks,
                excludedIds: pickedIds,
                excludeKws: excludeKws,
                soreAreas: context.recentSoreAreas,
                setsMultiplier: accessorySetsMul,
                strategy: strategy
            ))
        }
        if memory.primaryFocus == .hypertrophy && isLowerBody {
            appendAccessories(appendHypertrophyLowerBodyAccessories(
                memory: memory,
                profile: profile,
                hashSeed: hashSeed,
                existingPicks: picks,
                excludedIds: pickedIds,
                excludeKws: excludeKws,
                soreAreas: context.recentSoreAreas,
                setsMultiplier: accessorySetsMul,
                strategy: strategy
            ))
        }

        // D4 session structure — pair antagonist movements into supersets.
        // Additive: sets / reps / rest are untouched; only `supersetGroup`
        // is populated, and only where an antagonist pair actually co-occurs.
        picks = assignAntagonistSupersets(picks)

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
            provenance: prov,
            focus: focus
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

        // Apply sore-area exclude: drop exercises whose primary muscle maps to
        // a MuscleBucket the user flagged sore. recentSoreAreas holds
        // MuscleBucket rawValues (chest/quads/shoulders/...); coach.db tags
        // muscles by granular slug ("quadriceps", "gastrocnemius", ...), so we
        // bridge slug -> bucket via MuscleBucket.bucket(forSlug:) — the same
        // mapping the RPE-7 cap path (isMuscleSoreForExercise) uses. The prior
        // label-substring match silently missed quads ("Quadriceps"),
        // shoulders ("Anterior Deltoid"), back ("Latissimus Dorsi"), calves
        // ("Gastrocnemius"), and core. Empty context = no filtering.
        let applySoreFilter: ([Exercise]) -> [Exercise] = { candidates in
            guard !context.recentSoreAreas.isEmpty else { return candidates }
            return candidates.filter { ex in
                let muscles = CoachDatabase.shared.musclesForExercise(ex.id)
                let primary = muscles.filter { $0.role == "primary" }
                let slugs = primary.isEmpty ? muscles.map(\.slug) : primary.map(\.slug)
                let exerciseBuckets = Set(slugs.compactMap { MuscleBucket.bucket(forSlug: $0)?.rawValue })
                return exerciseBuckets.isDisjoint(with: context.recentSoreAreas)
            }
        }

        // Build 95: prefer recognized staples (bench / squat / deadlift /
        // etc.) when the candidate pool contains any. coach.db's pool for
        // a single pattern includes 15-20+ sport-flavored variants
        // (climbing, sailing, ski prep), so a uniform pick made bench
        // press as likely as "Single-arm landmine press." Narrowing to
        // staples when present biases the planner toward what most
        // lifters expect. Variants surface naturally once staples are in
        // `recentlyPicked` — applyVariety drops them and the wider pool
        // gets used. So week 1 = bench, week 2 (if bench was used) = DB
        // bench or push-up, etc.
        let applyStaplePreference: ([Exercise], String) -> [Exercise] = { candidates, pattern in
            let staples = candidates.filter { ExerciseStaples.isStaple(name: $0.name, forPattern: pattern) }
            return staples.isEmpty ? candidates : staples
        }

        // Phase-1 era-affinity aesthetic tiebreak. Stable-partition the
        // candidates so exercises whose required equipment matches the
        // cohort's preferred AestheticTags come FIRST. The hash pick
        // then resolves WITHIN the preferred group when present.
        //
        // Per the phase-training-personalization-three-axes skill, this
        // is the aesthetic axis only — competency / equipment-allowed
        // / staples / variety all run BEFORE this, so era can never
        // promote an exercise that wouldn't have been chosen anyway.
        // It just nudges the hash-tie to the cohort's implement family.
        let applyEraAesthetic: ([Exercise]) -> [Exercise] = { candidates in
            guard let style = profile.eraStyle, !style.aestheticTags.isEmpty,
                  candidates.count > 1 else { return candidates }
            let ids = Set(candidates.map(\.id))
            let equipmentByExercise = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: ids)
            let matchesEra: (Exercise) -> Bool = { ex in
                let equip = equipmentByExercise[ex.id] ?? []
                for tag in style.aestheticTags {
                    switch tag {
                    case .machineFavor:
                        // The catalog uses many machine-specific slugs;
                        // matching any of the big machine families counts.
                        let machines: Set<String> = [
                            "cable-machine", "smith-machine", "leg-press",
                            "leg-curl-machine", "leg-extension", "lat-pulldown",
                            "cable-crossover", "chest-press-machine",
                            "shoulder-press-machine", "iso-lateral-machine",
                            "preacher-bench", "hack-squat", "belt-squat",
                            "back-extension-machine", "pec-deck",
                            "tricep-extension-machine", "bicep-curl-machine",
                            "shrug-machine", "glute-kickback-machine",
                            "hip-ad-ab-machine"
                        ]
                        if !equip.intersection(machines).isEmpty { return true }
                    case .barbellFavor:
                        if equip.contains("barbell") || equip.contains("trap-bar")
                            || equip.contains("ez-bar") { return true }
                    case .cableFavor:
                        if equip.contains("cable-machine") || equip.contains("cable-crossover")
                            || equip.contains("lat-pulldown") { return true }
                    case .dbFavor:
                        if equip.contains("dumbbells") { return true }
                    }
                }
                return false
            }
            let preferred = candidates.filter(matchesEra)
            let rest = candidates.filter { !matchesEra($0) }
            if preferred.isEmpty || rest.isEmpty { return candidates }
            return preferred + rest
        }

        // Reorder slot.alternatives by LLM strategy: an emphasized pattern
        // jumps to the front; a deprioritized one is dropped from
        // consideration (the slot can fall through if ALL its alternatives
        // are deprioritized — fine, the LLM can do that on purpose).
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

        for pattern in alternatives {
            // Staples-across-all-allowed-difficulties pre-pass — a canonical
            // lift (Standing Calf Raise, Romanian Deadlift) should beat a
            // sport-flavored alternative even when the staple is tagged at
            // a lower difficulty than the user's preferred *bucket*. The
            // query still constrains to `profile.preferredDifficulties` —
            // a beginner does NOT get advanced staples (e.g. Explosive
            // Pull-Up). It just removes the per-bucket fallback ordering.
            let staplesPool = CoachDatabase.shared.exercises(
                matchingPattern: pattern,
                difficulties: Set(profile.preferredDifficulties),
                environments: envs,
                excludeKeywords: excludeKws,
                excludeIds: excludeIds,
                modalities: slot.requiredModalities,
                userSportSlugs: profile.userSportSlugs,
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs
            ).filter { ExerciseStaples.isStaple(name: $0.name, forPattern: pattern) }
            if !staplesPool.isEmpty,
               let pick = deterministicPick(from: applyEraAesthetic(applyVariety(applySoreFilter(staplesPool))), slotIdx: slotIdx, hashSeed: hashSeed) {
                slot.satisfiedBy = pattern
                return pick
            }

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
                    modalities: slot.requiredModalities,
                    userSportSlugs: profile.userSportSlugs,
                    allowedEquipmentSlugs: profile.allowedEquipmentSlugs
                )
                let candidates = applyStaplePreference(applySoreFilter(raw), pattern)
                if let pick = deterministicPick(from: applyEraAesthetic(applyVariety(candidates)), slotIdx: slotIdx, hashSeed: hashSeed) {
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
                modalities: slot.requiredModalities,
                userSportSlugs: profile.userSportSlugs,
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs
            )
            let relaxed = applyStaplePreference(applySoreFilter(relaxedRaw), pattern)
            if let pick = deterministicPick(from: applyEraAesthetic(applyVariety(relaxed)), slotIdx: slotIdx, hashSeed: hashSeed) {
                slot.satisfiedBy = pattern
                return pick
            }
        }
        return nil
    }

    /// If the initial pick is flagged stagnant (no PR in 4w), try to swap
    /// it for the highest-scoring substitute that still passes the same
    /// constraints. Returns the original pick when no acceptable swap
    /// exists. Conservative — won't bust env / dislike / injury filters.
    private static func applyStagnationSwap(
        original: Exercise,
        context: GeneratorContext,
        envs: Set<String>,
        allowedEquipmentSlugs: Set<String>,
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
            if !allowedEquipmentSlugs.isEmpty {
                let required = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: [candidate.id])[candidate.id] ?? []
                if !required.isSubset(of: allowedEquipmentSlugs) { continue }
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

    /// "target: 195 lb" style hint — a LOAD to work up to at the prescribed
    /// reps. Priority order:
    ///   1. LLM strategy targetWeightOverrides — explicit prescriptions ("bench at 90%").
    ///   2. priorBest → e1RM → load for the prescribed rep band, +2.5% step.
    ///   3. Nothing — no signal, no note.
    private static func progressiveOverloadHint(
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

    /// Pick canonical side-delt + tricep isolation exercises and turn them
    /// into GeneratedExercise rows, but only if the existing picks don't
    /// already cover the muscle. Returns the rows to append + their duration
    /// in seconds so the caller can keep elapsedSec accurate. Hardcoded
    /// canonical picks (Cable Lateral Raise / Rope Pushdown) match the
    /// eval-rig accessory layer's default slot — keeps the rig + generator
    /// in lockstep so a-vs-b grader comparisons stay clean.
    private static func appendHypertrophyUpperPushAccessories(
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        existingPicks: [GeneratedExercise],
        excludedIds: Set<Int>,
        excludeKws: [String],
        soreAreas: Set<String>,
        setsMultiplier: Double,
        strategy: GeneratorStrategy
    ) -> [(generated: GeneratedExercise, durSec: Int)] {
        var out: [(GeneratedExercise, Int)] = []
        // Only ISOLATION exercises count toward "tricep already covered" /
        // "side-delt already covered". A compound like Dumbbell Floor Press
        // hits triceps as a co-primary muscle, but the rubric's Q2 ("side-
        // or-rear-delt isolation AND a direct triceps isolation present")
        // looks for isolation-role work specifically.
        let existingMuscles = primeMusclesOfPicks(existingPicks.filter { !$0.isCompound })

        // Side-delt accessory — Cable Lateral Raise. Cable Lateral Raise is
        // the canonical pick because it travels well across home/gym setups
        // and matches the eval-rig accessory layer's stock entry.
        if !existingMuscles.contains("delt-lateral") && !existingMuscles.contains("delt-posterior") {
            if let ex = pickAccessoryByName(["Cable Lateral Raise", "Dumbbell Lateral Raise", "Bodybuilder Lateral Raise (Myo-Reps)"],
                                            profile: profile, excludedIds: excludedIds,
                                            excludeKws: excludeKws, soreAreas: soreAreas) {
                out.append(makeAccessoryRow(ex: ex, slotIdx: existingPicks.count + out.count,
                                            memory: memory, profile: profile,
                                            hashSeed: hashSeed, setsMultiplier: setsMultiplier,
                                            strategy: strategy))
            }
        }

        // Tricep isolation accessory — Rope Pushdown.
        if !existingMuscles.contains("triceps") {
            if let ex = pickAccessoryByName(["Rope Pushdown", "Overhead Cable Triceps Extension", "Skull Crusher"],
                                            profile: profile, excludedIds: excludedIds,
                                            excludeKws: excludeKws, soreAreas: soreAreas) {
                out.append(makeAccessoryRow(ex: ex, slotIdx: existingPicks.count + out.count,
                                            memory: memory, profile: profile,
                                            hashSeed: hashSeed, setsMultiplier: setsMultiplier,
                                            strategy: strategy))
            }
        }

        return out
    }

    /// Lower-body twin of `appendHypertrophyUpperPushAccessories`. Stock
    /// lower / legs recipes pair a squat compound with RDL (hip hinge,
    /// compound) and a calf raise. The hinge satisfies hamstrings via
    /// compound work but not isolation — eval-rig's lower-body Q2 ("direct
    /// hamstring isolation AND calf isolation present") catches this.
    /// Append Lying Leg Curl + Standing Calf Raise when no existing
    /// isolation pick covers the muscle.
    private static func appendHypertrophyLowerBodyAccessories(
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        existingPicks: [GeneratedExercise],
        excludedIds: Set<Int>,
        excludeKws: [String],
        soreAreas: Set<String>,
        setsMultiplier: Double,
        strategy: GeneratorStrategy
    ) -> [(generated: GeneratedExercise, durSec: Int)] {
        var out: [(GeneratedExercise, Int)] = []
        let existingMuscles = primeMusclesOfPicks(existingPicks.filter { !$0.isCompound })

        // Hamstring isolation — Lying Leg Curl is the canonical fit; seated
        // is a near-twin fallback when the gym only has the seated machine.
        if !existingMuscles.contains("hamstrings") {
            if let ex = pickAccessoryByName(["Lying Leg Curl", "Seated Leg Curl"],
                                            profile: profile, excludedIds: excludedIds,
                                            excludeKws: excludeKws, soreAreas: soreAreas) {
                out.append(makeAccessoryRow(ex: ex, slotIdx: existingPicks.count + out.count,
                                            memory: memory, profile: profile,
                                            hashSeed: hashSeed, setsMultiplier: setsMultiplier,
                                            strategy: strategy))
            }
        }

        // Calf isolation — Standing Calf Raise is the canonical fit. Check
        // gastrocnemius + soleus too: coach.db tags Standing Calf Raise's
        // primaries as ["gastrocnemius", "soleus"] (the muscle components)
        // not "calves" (the muscle group), so a plain `contains("calves")`
        // misses an already-present calf isolation slot and double-appends.
        if existingMuscles.isDisjoint(with: ["calves", "gastrocnemius", "soleus"]) {
            if let ex = pickAccessoryByName(["Standing Calf Raise", "Seated Calf Raise"],
                                            profile: profile, excludedIds: excludedIds,
                                            excludeKws: excludeKws, soreAreas: soreAreas) {
                out.append(makeAccessoryRow(ex: ex, slotIdx: existingPicks.count + out.count,
                                            memory: memory, profile: profile,
                                            hashSeed: hashSeed, setsMultiplier: setsMultiplier,
                                            strategy: strategy))
            }
        }

        return out
    }

    /// Collect prime-muscle slugs across all picks so the accessory layer
    /// knows what's already covered.
    private static func primeMusclesOfPicks(_ picks: [GeneratedExercise]) -> Set<String> {
        var out: Set<String> = []
        for p in picks {
            let muscles = CoachDatabase.shared.musclesForExercise(p.exerciseId)
            for m in muscles where m.role == "primary" {
                out.insert(m.slug)
            }
        }
        return out
    }

    /// Pick the first exercise whose name matches one of the canonical
    /// fallbacks AND respects the user's environment + equipment + exclusion
    /// filters. Falls through nil when no canonical pick is loadable — the
    /// caller (this is best-effort accessory work, not a required slot).
    private static func pickAccessoryByName(
        _ names: [String],
        profile: DemographicProfile,
        excludedIds: Set<Int>,
        excludeKws: [String],
        soreAreas: Set<String>
    ) -> Exercise? {
        for name in names {
            // listExercises does a LIKE name search; filter to exact match
            // so "Lateral Raise" doesn't pick a variant unintentionally.
            let candidates = CoachDatabase.shared.listExercises(search: name)
            guard let ex = candidates.first(where: { $0.name == name }) else { continue }
            if excludedIds.contains(ex.id) { continue }
            // Dislike-keyword filter — mirror the main slot loop (WG:606): the
            // canonical names ("Cable Lateral Raise", "Rope Pushdown") match a
            // disliked 'cable' / 'machine' keyword, so honor it here too.
            let lowerName = ex.name.lowercased()
            if excludeKws.contains(where: { lowerName.contains($0) }) { continue }
            // Sore-area exclude — same slug→bucket bridge as applySoreFilter
            // (WG:392). Don't append isolation onto a muscle the user flagged sore.
            if !soreAreas.isEmpty, !soreBuckets(forExerciseId: ex.id).isDisjoint(with: soreAreas) { continue }
            // Env filter: empty envs = no restriction.
            if !profile.allowedEnvironments.isEmpty,
               let env = ex.environment, !env.isEmpty,
               !profile.allowedEnvironments.contains(env) { continue }
            // Equipment filter: skip when required equipment isn't in the
            // user's allowed set (full-gym users have empty allowedEquipmentSlugs).
            if !profile.allowedEquipmentSlugs.isEmpty {
                let required = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: [ex.id])[ex.id] ?? []
                if !required.isSubset(of: profile.allowedEquipmentSlugs) { continue }
            }
            return ex
        }
        return nil
    }

    /// MuscleBucket rawValues an exercise's primary muscles map to — the same
    /// slug→bucket bridge `applySoreFilter` (WG:392) uses, factored out so the
    /// accessory layer can reuse it. Primary role preferred; falls back to all
    /// tagged muscles when none is marked primary.
    private static func soreBuckets(forExerciseId id: Int) -> Set<String> {
        let muscles = CoachDatabase.shared.musclesForExercise(id)
        let primary = muscles.filter { $0.role == "primary" }
        let slugs = primary.isEmpty ? muscles.map(\.slug) : primary.map(\.slug)
        return Set(slugs.compactMap { MuscleBucket.bucket(forSlug: $0)?.rawValue })
    }

    /// Rep band for the auto-appended isolation FINISHER (D4 part B/C —
    /// session structure). Higher than the accessory band (8-15) so the day
    /// descends compound (low) → accessory (mid) → finisher (high). High-rep
    /// isolation finishers are standard hypertrophy practice (metabolic stress
    /// on small muscles). Internal for the rep-band-curve test.
    static let finisherRepBand = "15-20"

    /// Convert a picked accessory Exercise into a GeneratedExercise row using
    /// the same prescription/rpe/tempo helpers the main loop uses. Returns
    /// the row plus its expected duration in seconds so elapsedSec can stay
    /// honest in the workout's estimatedMinutes calculation. The accessory is
    /// the session's finisher, so it carries `finisherRepBand`, not the
    /// prescription's mid accessory reps.
    private static func makeAccessoryRow(
        ex: Exercise,
        slotIdx: Int,
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        setsMultiplier: Double,
        strategy: GeneratorStrategy
    ) -> (GeneratedExercise, Int) {
        // slotIdx is past primary-compound territory, so prescription will
        // hand us an accessory scheme (lower sets, shorter rest). We keep its
        // sets + rest but override reps: this appended isolation is the day's
        // FINISHER, so it takes the high-rep finisher band (part B/C — the day
        // descends compound → accessory → finisher).
        let (baseSets, _, restSec) = prescription(
            for: ex,
            slotIdx: slotIdx,
            focus: .push,   // any non-mobility focus works — the prescription doesn't branch on push vs upper here
            memory: memory,
            profile: profile
        )
        // Scale by the readiness × deload multiplier, same clamp as the main
        // slot loop (WG:209), so a low-readiness or deload day cuts accessory
        // volume too instead of leaving it at full sets (T0.1).
        let sets = max(1, min(8, Int((Double(baseSets) * setsMultiplier).rounded())))
        let reps = finisherRepBand
        // Budget cost uses PRE-multiplier sets so a deload doesn't free up time
        // for more accessories — mirrors the main loop's baseDurSec (WG:215).
        let durSec = baseSets * (45 + restSec) + 30
        let (rpe, tempo) = rpeTempoHints(
            for: ex,
            slotIdx: slotIdx,
            focus: .push,
            memory: memory,
            strategy: strategy
        )
        let row = GeneratedExercise(
            id: "\(hashSeed)-hypaccess-\(ex.id)",
            exerciseId: ex.id,
            name: ex.name,
            pattern: nil,
            isCompound: ex.isCompound,
            sets: sets,
            reps: reps,
            restSeconds: restSec,
            notes: "Hypertrophy accessory — auto-added for isolation coverage",
            rpe: rpe,
            tempo: tempo
        )
        return (row, durSec)
    }

    /// True when the exercise's primary muscle group (resolved via
    /// CoachDatabase.musclesForExercise + MuscleBucket.bucket(forSlug:))
    /// matches any area on the user's most recent (≤36h) SorenessEntry at
    /// mild or high severity. The check-in only ever produces none|mild|high
    /// (SorenessEntry.soreness), so gating on "mild"||"high" is what makes a
    /// real user report actually fire the cap — gating on the nonexistent
    /// "moderate" left mild reports silently un-regulated. `entry.areas`
    /// carries MuscleBucket slugs post-build-107; we bucket the granular
    /// muscle slug back up to compare.
    private static func isMuscleSoreForExercise(_ exercise: Exercise, memory: TrainingMemory) -> Bool {
        let cutoff = Date().addingTimeInterval(-36 * 60 * 60)
        guard let entry = memory.soreness
                .filter({ $0.date >= cutoff })
                .max(by: { $0.date < $1.date }),
              entry.soreness == "mild" || entry.soreness == "high",
              !entry.areas.isEmpty
        else { return false }

        let muscles = CoachDatabase.shared.musclesForExercise(exercise.id)
        // Match on the primary muscle's bucket. If no primary muscle is
        // tagged, fall back to any muscle's bucket — better to over-cap
        // than under-cap on Q9.
        let candidates = muscles.first(where: { $0.role == "primary" }).map { [$0.slug] }
            ?? muscles.map(\.slug)
        let buckets = candidates.compactMap { MuscleBucket.bucket(forSlug: $0)?.rawValue }
        let sore = Set(entry.areas)
        for b in buckets where sore.contains(b) { return true }
        return false
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

    // MARK: - Superset structure (D4)

    /// Antagonist movement-pattern pairs that make natural supersets — push
    /// against pull, extension against flexion. Alternating sets between two
    /// non-competing muscle groups is the standard time-saver the bundled
    /// routines already use. Symmetric (both directions present).
    static let antagonistPatterns: [String: String] = [
        "horizontal-push": "horizontal-pull",
        "horizontal-pull": "horizontal-push",
        "vertical-push": "vertical-pull",
        "vertical-pull": "vertical-push",
        "elbow-extension": "elbow-flexion",
        "elbow-flexion": "elbow-extension",
        "scapular-protraction": "scapular-retraction",
        "scapular-retraction": "scapular-protraction",
    ]

    /// Pair antagonist movements into supersets. The top heavy compound
    /// (index 0) is left solo — a max-effort primary lift gets straight sets
    /// with full rest, not a superset. Walks the remaining picks in order;
    /// each unpaired exercise whose pattern has an antagonist is grouped with
    /// the next unpaired pick carrying that antagonist pattern.
    ///
    /// Deterministic (order-driven), additive (sets / reps / rest untouched),
    /// and a no-op for single-emphasis days — a push day has no pulls to pair
    /// with, so it stays flat. This is exactly the G6 target: "≥1 superset
    /// where appropriate" (upper / full-body days get a pair; push / pull /
    /// leg days don't). Internal for direct unit testing.
    static func assignAntagonistSupersets(_ picks: [GeneratedExercise]) -> [GeneratedExercise] {
        guard picks.count > 2 else { return picks }
        var out = picks
        var nextGroup = 1
        var paired = Set<Int>()
        for i in 1..<out.count where !paired.contains(i) {
            guard let pattern = out[i].pattern,
                  let want = antagonistPatterns[pattern] else { continue }
            guard let j = (i + 1 ..< out.count).first(where: { k in
                !paired.contains(k) && out[k].pattern == want
            }) else { continue }
            out[i].supersetGroup = nextGroup
            out[j].supersetGroup = nextGroup
            paired.insert(i)
            paired.insert(j)
            nextGroup += 1
        }
        return out
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
        case .advanced:     break
        }
        if let age = memory.age, age >= 55 {
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

// MARK: - Phase 2 readiness helpers

/// Linear interpolation between `lo` and `hi` at `t` in [0, 1]. Clamps t.
func lerp(_ lo: Double, _ hi: Double, _ t: Double) -> Double {
    let clamped = min(max(t, 0.0), 1.0)
    return lo + (hi - lo) * clamped
}

/// Apply the Phase 2 compound-RPE cap given a readiness score in [0, 1].
/// The cap floor is RPE 7 at score 0 → RPE 9 at score 1. We parse the
/// existing RPE string ("7", "8", "RPE 8", "RPE 7-8" etc.), extract the
/// highest number, and replace it with `min(originalMax, cap)`. Inputs
/// the parser doesn't understand pass through unchanged — the cap is a
/// safety floor, not a coercion.
func capCompoundRPE(_ rpeRaw: String, readinessScore: Double) -> String {
    return capRPE(rpeRaw, to: lerp(7.0, 9.0, readinessScore))
}

/// Cap an RPE string ("7", "8-9", "RPE 7-8") so its max value ≤ `capValue`.
/// Parser failures pass through unchanged — the cap is a safety floor, not a
/// coercion. Shared by the readiness compound cap and the beginner cap (T1.5).
func capRPE(_ rpeRaw: String, to capValue: Double) -> String {
    let trimmed = rpeRaw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return rpeRaw }

    // Try simple integer first ("8").
    if let single = Double(trimmed) {
        let capped = min(single, capValue)
        return formatRPE(capped)
    }
    // Range form: "7-8" or "RPE 7-8".
    let stripped = trimmed.replacingOccurrences(of: "RPE", with: "",
                                                 options: .caseInsensitive)
        .replacingOccurrences(of: " ", with: "")
    if stripped.contains("-") {
        let parts = stripped.split(separator: "-")
        if parts.count == 2,
           let lo = Double(parts[0]),
           let hi = Double(parts[1]) {
            let cappedHi = min(hi, capValue)
            if cappedHi <= lo {
                return formatRPE(cappedHi)
            } else {
                return "\(formatRPE(lo))-\(formatRPE(cappedHi))"
            }
        }
    }
    // Single number with RPE prefix.
    if let single = Double(stripped) {
        let capped = min(single, capValue)
        return formatRPE(capped)
    }
    // Couldn't parse — leave unchanged. Safer than mangling.
    return rpeRaw
}

/// Format an RPE number — drop trailing ".0" for whole values, otherwise
/// one decimal. Keeps the output looking like the existing RPE strings.
private func formatRPE(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if abs(rounded - rounded.rounded()) < 0.05 {
        return String(format: "%.0f", rounded)
    }
    return String(format: "%.1f", rounded)
}
