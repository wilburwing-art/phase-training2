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
        // Strategy's duration override beats memory's default. Clamped to the
        // hard range so a hallucinated 9999 doesn't produce a 10-hour workout.
        let effectiveMinutes: Int = {
            if let m = strategy.durationMinutes {
                let hard = TrainingConstraints.sessionMinutesHardRange
                return min(hard.upperBound, max(hard.lowerBound, m))
            }
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

        // Memoizes repeated identical catalog queries for THIS pass only —
        // user-DB edits between generations are always picked up.
        let queryCache = ExerciseQueryCache()

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
                cache: queryCache,
                context: context,
                strategy: strategy
            ) else { continue }

            // Stagnation swap: if the user's pick is on the stagnant list
            // (canonical lift with no PR in 4 weeks) and a substitute is
            // available + still within their constraints, prefer the swap.
            // recentlyPicked = hysteresis against A↔B swap oscillation; the
            // lazy fallbackPool (slot's own pattern pool, satisfiedBy is set
            // by pickForSlot — PatternSlot is a class) covers exercises with
            // no curated substitution rows.
            let picked = applyStagnationSwap(
                original: initial,
                context: context,
                envs: envs,
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs,
                excludeKws: excludeKws,
                excludeIds: pickedIds,
                recentlyPicked: recentlyPicked,
                slot: slot,
                fallbackPool: {
                    guard let pattern = slot.satisfiedBy else { return [] }
                    return queryCache.exercises(
                        matchingPattern: pattern,
                        environments: envs,
                        excludeKeywords: excludeKws,
                        excludeIds: pickedIds,
                        modalities: slot.requiredModalities,
                        userSportSlugs: profile.userSportSlugs,
                        allowedEquipmentSlugs: profile.allowedEquipmentSlugs
                    )
                }
            )

            // Required slots TRIM their set count to fit the remaining budget
            // (T2.4) rather than overrun a short session; optional slots pass
            // nil and are dropped below if they don't fit.
            let (row, baseDurSec) = makePickedRow(
                picked: picked, pattern: slot.satisfiedBy, slotIdx: slotIdx, focus: focus,
                memory: memory, profile: profile, context: context,
                strategy: strategy, hashSeed: hashSeed,
                budgetRemainingSec: slot.optional ? nil : max(0, budgetSec - elapsedSec))

            // Optional slots that bust the budget get dropped; required slots
            // were trimmed to fit above. Budget uses the PRE-multiplier duration
            // so a deload day doesn't "free up" time for extra accessories (build 97).
            if elapsedSec + baseDurSec > budgetSec, slot.optional, !picks.isEmpty {
                continue
            }

            picks.append(row)
            pickedIds.insert(picked.id)
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
                affinities: context.exerciseAffinities,
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
                affinities: context.exerciseAffinities,
                setsMultiplier: accessorySetsMul,
                strategy: strategy
            ))
        }

        // Graceful-degradation floor (T1.1b / T1.3): when equipment-starved
        // required slots drop out — e.g. a bodyweight pull day, where no
        // apparatus-free vertical pull exists — the day can collapse to one or
        // two movements. Backfill from focus-appropriate fallback patterns
        // through the SAME pickForSlot + makePickedRow pipeline, so every
        // filter and scaler still applies, until a minimum movement count or
        // the fallbacks run dry. Budget-gated, so a legitimately short day
        // (tight session minutes) is never padded past its budget.
        let minMovements = 3
        if picks.count < minMovements {
            for pattern in degradationFallbackPatterns(for: focus) {
                if picks.count >= minMovements { break }
                let slot = PatternSlot(alternatives: [pattern], optional: true)
                guard let pick = pickForSlot(
                    slot: slot, slotIdx: picks.count, profile: profile, envs: envs,
                    excludeKws: excludeKws, excludeIds: pickedIds,
                    recentlyPicked: recentlyPicked, hashSeed: hashSeed,
                    cache: queryCache, context: context, strategy: strategy) else { continue }
                let (row, durSec) = makePickedRow(
                    picked: pick, pattern: slot.satisfiedBy, slotIdx: picks.count, focus: focus,
                    memory: memory, profile: profile, context: context,
                    strategy: strategy, hashSeed: hashSeed)
                if elapsedSec + durSec > budgetSec, !picks.isEmpty { continue }
                picks.append(row)
                pickedIds.insert(pick.id)
                elapsedSec += durSec
            }
        }

        // High-minute volume tier (T1.4): the budget only *drops* optional slots
        // when minutes are low. Mirror that upward: a generous budget earns extra
        // work. Two tiers, both budget-gated.
        //  ≥90 min → one additional focus-appropriate accessory slot
        // ≥120 min → +1 set on every compound already in the workout (cap 6),
        //             with elapsedSec updated so estimatedMinutes stays accurate.
        if effectiveMinutes >= 90 {
            for pattern in highMinuteAccessoryPatterns(for: focus) {
                let slot = PatternSlot(alternatives: [pattern], optional: true)
                guard let pick = pickForSlot(
                    slot: slot, slotIdx: picks.count, profile: profile, envs: envs,
                    excludeKws: excludeKws, excludeIds: pickedIds,
                    recentlyPicked: recentlyPicked, hashSeed: hashSeed,
                    cache: queryCache, context: context, strategy: strategy) else { continue }
                let (row, durSec) = makePickedRow(
                    picked: pick, pattern: slot.satisfiedBy, slotIdx: picks.count, focus: focus,
                    memory: memory, profile: profile, context: context,
                    strategy: strategy, hashSeed: hashSeed)
                guard elapsedSec + durSec <= budgetSec else { break }
                picks.append(row)
                pickedIds.insert(pick.id)
                elapsedSec += durSec
                break
            }
        }
        if effectiveMinutes >= 120 {
            for i in picks.indices where picks[i].isCompound {
                picks[i].sets = min(6, picks[i].sets + 1)
                elapsedSec += 45 + picks[i].restSeconds
            }
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

    /// Build a `GeneratedExercise` row for a picked exercise, applying the
    /// same prescription, readiness/deload set-scaling, progressive-overload
    /// note, compound RPE cap, and warm-up rules the main slot loop uses.
    /// Returns the row plus its PRE-multiplier duration (the budget-accounting
    /// cost). Shared by the main loop, the degradation floor, AND the
    /// represcribe path (WorkoutGenerator+Represcribe) so they never drift
    /// apart (the dual-path trap — see the prescription skill). `pattern` is
    /// the slot's satisfiedBy at the loop call sites; nil for represcribe.
    static func makePickedRow(
        picked: Exercise,
        pattern: String?,
        slotIdx: Int,
        focus: WorkoutFocus,
        memory: TrainingMemory,
        profile: DemographicProfile,
        context: GeneratorContext,
        strategy: GeneratorStrategy,
        hashSeed: String,
        budgetRemainingSec: Int? = nil
    ) -> (row: GeneratedExercise, baseDurSec: Int) {
        let (rawBaseSets, reps, restSec) = prescription(
            for: picked, slotIdx: slotIdx, focus: focus, memory: memory, profile: profile)
        // Tight-budget set trim (T2.4): a required slot on a very short session
        // shrinks its set count to fit the remaining budget rather than overrun
        // (e.g. a 20-min day used to ship a 33-min leg day). Floor at 1 set;
        // optional slots pass nil and are dropped by the caller instead.
        let baseSets: Int = {
            guard let rem = budgetRemainingSec else { return rawBaseSets }
            let maxFit = max(1, (rem - 30) / (45 + restSec))
            return min(rawBaseSets, maxFit)
        }()
        // Readiness × deload set multiplier (no effect when no readiness data).
        let readinessSetsMultiplier: Double = context.hasReadinessData
            ? lerp(0.6, 1.0, context.readinessScore) : 1.0
        let combinedSetsMul = readinessSetsMultiplier * strategy.intensityBias.setsMultiplier
        let sets = max(1, min(8, Int((Double(baseSets) * combinedSetsMul).rounded())))
        // Budget accounting uses pre-multiplier duration (build 97).
        let baseDurSec = baseSets * (45 + restSec) + 30
        let notes = progressiveOverloadHint(
            for: picked, context: context, memory: memory, prescribedReps: reps, strategy: strategy)
        let (rpeRaw, tempo) = rpeTempoHints(
            for: picked, slotIdx: slotIdx, focus: focus, memory: memory, strategy: strategy)
        // Phase 2 readiness RPE cap — compound lifts only, when readiness data exists.
        let rpe: String? = {
            guard let raw = rpeRaw, picked.isCompound, context.hasReadinessData else { return rpeRaw }
            return capCompoundRPE(raw, readinessScore: context.readinessScore)
        }()
        // Warm-up ramp only for the first compound primary, and not when sore.
        let warmUps: [WarmUpSet]? = (slotIdx == 0 && picked.isCompound && !isMuscleSoreForExercise(picked, memory: memory))
            ? [
                WarmUpSet(reps: 5, loadPctOfWorking: 40, restSeconds: 60),
                WarmUpSet(reps: 5, loadPctOfWorking: 60, restSeconds: 60),
                WarmUpSet(reps: 3, loadPctOfWorking: 80, restSeconds: 90),
              ]
            : nil
        let row = GeneratedExercise(
            id: "\(hashSeed)-\(slotIdx)-\(picked.id)",
            exerciseId: picked.id,
            name: picked.name,
            pattern: pattern,
            isCompound: picked.isCompound,
            sets: sets,
            reps: reps,
            restSeconds: restSec,
            notes: notes,
            rpe: rpe,
            tempo: tempo,
            warmUpSets: warmUps
        )
        return (row, baseDurSec)
    }

    /// Focus-appropriate patterns the degradation floor backfills from when the
    /// recipe's own slots can't fill (equipment-starved). Curated so the
    /// fallback stays on-theme — a pull day degrades to scapular/back-isometric
    /// work (which has bodyweight options post-resync), a push day to core /
    /// extension, a leg day to core / hinge. Ordered by preference. (T1.1b/T1.3)
    private static func degradationFallbackPatterns(for focus: WorkoutFocus) -> [String] {
        switch focus {
        case .pull:
            return ["scapular-retraction", "scapular-protraction", "elbow-flexion"]
        case .push, .upper, .fullBodyA, .fullBodyB:
            return ["scapular-protraction", "anti-extension", "elbow-extension"]
        case .legs, .lower:
            return ["anti-extension", "anti-rotation", "hip-hinge"]
        }
    }

    // MARK: - Slot fulfillment

    /// Memoizes `CoachDatabase.exercises(...)` reads for the duration of ONE
    /// generate() pass. pickForSlot issues up to ~9 catalog queries per slot
    /// (staples pool + per-difficulty buckets + the relaxed pass, per
    /// alternative pattern); identical parameter sets within a pass return the
    /// cached rows instead of re-hitting SQLite. Deliberately per-generation —
    /// NOT global — so user-DB changes between generations are always seen.
    private final class ExerciseQueryCache {
        private struct Key: Hashable {
            let pattern: String
            let difficulties: Set<String>
            let environments: Set<String>
            let excludeKeywords: [String]
            let excludeIds: Set<Int>
            let modalities: Set<String>
            let userSportSlugs: [String]
            let allowedEquipmentSlugs: Set<String>
        }
        private var cached: [Key: [Exercise]] = [:]

        func exercises(
            matchingPattern pattern: String,
            difficulties: Set<String> = [],
            environments: Set<String> = [],
            excludeKeywords: [String] = [],
            excludeIds: Set<Int> = [],
            modalities: Set<String> = [],
            userSportSlugs: [String] = [],
            allowedEquipmentSlugs: Set<String> = []
        ) -> [Exercise] {
            let key = Key(pattern: pattern, difficulties: difficulties,
                          environments: environments, excludeKeywords: excludeKeywords,
                          excludeIds: excludeIds, modalities: modalities,
                          userSportSlugs: userSportSlugs,
                          allowedEquipmentSlugs: allowedEquipmentSlugs)
            if let hit = cached[key] { return hit }
            let rows = CoachDatabase.shared.exercises(
                matchingPattern: pattern, difficulties: difficulties,
                environments: environments, excludeKeywords: excludeKeywords,
                excludeIds: excludeIds, modalities: modalities,
                userSportSlugs: userSportSlugs,
                allowedEquipmentSlugs: allowedEquipmentSlugs)
            cached[key] = rows
            return rows
        }
    }

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
        cache: ExerciseQueryCache,
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

        // Swap-memory affinity weighting. The user's exercise swaps land in
        // TrainingMemory.exerciseAffinities (positive = swapped toward / asked
        // for more; negative = swapped away from). deterministicPick is a
        // uniform hash-index into the pool, so we bias by MULTIPLICITY: a
        // preferred exercise appears (1 + affinity) times (capped at 4×) and is
        // proportionally more likely to win; a strongly-demoted one (≤ -2) is
        // dropped when alternatives remain. Runs LAST — after applyVariety — so
        // a just-picked exercise is still rotated out; the bias makes a favorite
        // frequent, not permanent. Exact case-insensitive name match (not
        // substring) so "Row" doesn't boost every row variant.
        let applyAffinityWeighting: ([Exercise]) -> [Exercise] = { candidates in
            let affinities = context.exerciseAffinities
            guard !affinities.isEmpty, candidates.count > 1 else { return candidates }
            let scoreFor: (String) -> Int = { name in
                for (key, value) in affinities where key.caseInsensitiveCompare(name) == .orderedSame {
                    return value
                }
                return 0
            }
            var weighted: [Exercise] = []
            for ex in candidates {
                let score = scoreFor(ex.name)
                if score <= -2 { continue }
                weighted.append(contentsOf: Array(repeating: ex, count: min(max(1, 1 + score), 4)))
            }
            return weighted.isEmpty ? candidates : weighted
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
            let staplesPool = cache.exercises(
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
               let pick = deterministicPick(from: applyAffinityWeighting(applyEraAesthetic(applyVariety(applySoreFilter(staplesPool)))), slotIdx: slotIdx, hashSeed: hashSeed) {
                slot.satisfiedBy = pattern
                return pick
            }

            // Try preferred difficulties first, then fall back across the
            // whole allowed set (so a beginner-only catalog still returns
            // something for an advanced user).
            for bucket in profile.preferredDifficulties {
                let raw = cache.exercises(
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
                if let pick = deterministicPick(from: applyAffinityWeighting(applyEraAesthetic(applyVariety(candidates))), slotIdx: slotIdx, hashSeed: hashSeed) {
                    slot.satisfiedBy = pattern
                    return pick
                }
            }
            // Difficulty-relaxed pass — env + constraints still hold.
            let relaxedRaw = cache.exercises(
                matchingPattern: pattern,
                environments: envs,
                excludeKeywords: excludeKws,
                excludeIds: excludeIds,
                modalities: slot.requiredModalities,
                userSportSlugs: profile.userSportSlugs,
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs
            )
            let relaxed = applyStaplePreference(applySoreFilter(relaxedRaw), pattern)
            if let pick = deterministicPick(from: applyAffinityWeighting(applyEraAesthetic(applyVariety(relaxed))), slotIdx: slotIdx, hashSeed: hashSeed) {
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
    ///
    /// `recentlyPicked` is the HYSTERESIS guard (generator-audit oscillation
    /// finding): an exercise swapped away weeks ago is still in the
    /// cross-week recently-picked set, so excluding recent ids here blocks
    /// the A → B → A swap-back for the rotation window. Hard exclusion on
    /// purpose — if every candidate is recent we keep the stagnant original
    /// for one more week rather than re-open the oscillation.
    ///
    /// `fallbackPool` covers the ~70% of the catalog with NO curated
    /// exercise_substitutions rows: when the curated loop fails, candidates
    /// from the slot's own pattern pool (already filtered for env /
    /// equipment / dislikes / modality / excludeIds at the SQL boundary)
    /// are ranked by primary-muscle overlap with the original — squat →
    /// leg press, not squat → any same-pattern outlier. Evaluated lazily so
    /// the query only runs when the curated path comes up empty.
    static func applyStagnationSwap(
        original: Exercise,
        context: GeneratorContext,
        envs: Set<String>,
        allowedEquipmentSlugs: Set<String>,
        excludeKws: [String],
        excludeIds: Set<Int>,
        recentlyPicked: Set<Int> = [],
        slot: PatternSlot,
        fallbackPool: () -> [Exercise] = { [] }
    ) -> Exercise {
        guard context.stagnantExercises.contains(original.name.lowercased()) else {
            return original
        }
        let substitutes = CoachDatabase.shared.substitutes(forExerciseId: original.id)
        for sub in substitutes {
            let candidate = sub.exercise
            if excludeIds.contains(candidate.id) { continue }
            if recentlyPicked.contains(candidate.id) { continue }   // hysteresis
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
            // Same-movement-pattern gate (T2.5): a stagnation swap must stay
            // within the slot's pattern. 56% of coach.db substitutions cross
            // movement patterns (e.g. a loaded-carry → a quad isometric, a
            // vertical-pull → a push), which would break the day's structure.
            // Require the candidate to share a pattern with the slot.
            let candidatePatterns = Set(CoachDatabase.shared.patternsForExercise(candidate.id))
            if candidatePatterns.isDisjoint(with: Set(slot.alternatives)) { continue }
            return candidate
        }

        // Curated path exhausted — deterministic pattern-pool fallback.
        // The pool arrives pre-filtered (env / equipment / dislikes /
        // modality / excludeIds applied at the cache query); the explicit
        // re-checks below only guard direct-call test usage. Require a
        // primary-muscle overlap with the original; rank overlap desc,
        // then id asc. No RNG.
        let originalPrimaries = Set(
            CoachDatabase.shared.musclesForExercise(original.id)
                .filter { $0.role == "primary" }.map(\.slug))
        guard !originalPrimaries.isEmpty else { return original }
        var best: (overlap: Int, exercise: Exercise)?
        for candidate in fallbackPool() {
            if candidate.id == original.id { continue }
            if excludeIds.contains(candidate.id) { continue }
            if recentlyPicked.contains(candidate.id) { continue }   // hysteresis
            let candPrimaries = Set(
                CoachDatabase.shared.musclesForExercise(candidate.id)
                    .filter { $0.role == "primary" }.map(\.slug))
            let overlap = candPrimaries.intersection(originalPrimaries).count
            guard overlap > 0 else { continue }
            if let current = best {
                if overlap > current.overlap
                    || (overlap == current.overlap && candidate.id < current.exercise.id) {
                    best = (overlap, candidate)
                }
            } else {
                best = (overlap, candidate)
            }
        }
        return best?.exercise ?? original
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
    static func isMuscleSoreForExercise(_ exercise: Exercise, memory: TrainingMemory) -> Bool {
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

// Internal (not fileprivate): `prescription` moved to WorkoutGenerator+Prescription.swift
// during the Tier-3 split still calls `.nilIfEmpty`, so it must be reachable across
// the file boundary. Sole definition repo-wide, so widening can't collide.
extension String {
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
/// coercion. Shared by the readiness compound cap, the beginner cap (T1.5),
/// and the build_workout decoder's RPE plausibility clamp.
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
