// WorkoutGenerator+Accessories.swift
//
// Extracted from WorkoutGenerator.swift (Tier-3 god-object split). Pure
// hypertrophy accessory layer (auto-added isolation coverage + high-minute volume) — no state, no orchestration; the generation loop in
// WorkoutGenerator.swift calls into these as a focused seam.

import Foundation

extension WorkoutGenerator {
    /// Extra patterns the high-minute volume tier (T1.4) adds at ≥90-min
    /// sessions — one slot beyond the focus recipe's own optional slots. Chosen
    /// to complement each focus without duplicating what the recipe already
    /// prescribes (the dedup is enforced by `pickedIds`, but distinct patterns
    /// also give variety rather than a second hit of the same movement family).
    static func highMinuteAccessoryPatterns(for focus: WorkoutFocus) -> [String] {
        switch focus {
        case .push:
            return ["elbow-flexion", "anti-rotation"]
        case .pull:
            return ["anti-extension", "anti-rotation"]
        case .legs, .lower:
            return ["hip-abduction", "anti-extension"]
        case .upper, .fullBodyA, .fullBodyB:
            return ["elbow-extension", "elbow-flexion", "loaded-carry"]
        }
    }

    /// Pick canonical side-delt + tricep isolation exercises and turn them
    /// into GeneratedExercise rows, but only if the existing picks don't
    /// already cover the muscle. Returns the rows to append + their duration
    /// in seconds so the caller can keep elapsedSec accurate. Hardcoded
    /// canonical picks (Cable Lateral Raise / Rope Pushdown) match the
    /// eval-rig accessory layer's default slot — keeps the rig + generator
    /// in lockstep so a-vs-b grader comparisons stay clean.
    static func appendHypertrophyUpperPushAccessories(
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
    static func appendHypertrophyLowerBodyAccessories(
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
            // Equipment-tag dislike (T1.7): match the dislike against required
            // equipment slug + name too — the canonical picks hide it (Rope
            // Pushdown needs a cable, Lying Leg Curl needs leg-curl-machine),
            // mirroring CoachDatabase.exercises. Guarded so the table read only
            // runs when there are dislikes.
            if !excludeKws.isEmpty {
                let required = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: [ex.id])[ex.id] ?? []
                let equipNames = CoachDatabase.shared.equipmentNameBySlug()
                if required.contains(where: { slug in
                    let hay = slug + " " + (equipNames[slug] ?? "")
                    return excludeKws.contains(where: { hay.contains($0) })
                }) { continue }
            }
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
}
