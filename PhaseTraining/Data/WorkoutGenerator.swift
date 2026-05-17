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
    static func generateLift(
        liftIndex: Int,
        totalLifts: Int,
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String
    ) -> GeneratedWorkout {
        let focus = WorkoutFocus.lift(liftIndex: liftIndex, totalLifts: totalLifts)
        return generate(focus: focus, memory: memory, profile: profile, hashSeed: hashSeed, liftIndex: liftIndex, totalLifts: totalLifts)
    }

    /// Generate a mobility day's flow.
    static func generateMobility(
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String
    ) -> GeneratedWorkout {
        generate(focus: .mobility, memory: memory, profile: profile, hashSeed: hashSeed, liftIndex: 0, totalLifts: 0)
    }

    // MARK: - Core loop

    private static func generate(
        focus: WorkoutFocus,
        memory: TrainingMemory,
        profile: DemographicProfile,
        hashSeed: String,
        liftIndex: Int,
        totalLifts: Int
    ) -> GeneratedWorkout {
        let budgetSec = max(15 * 60, memory.sessionMinutes * 60 - warmupBufferSec)
        var elapsedSec = 0
        var pickedIds: Set<Int> = []
        var picks: [GeneratedExercise] = []

        // Constraints applied at the SQL boundary.
        let envs = profile.allowedEnvironments
        let excludeKws = profile.excludedNameKeywords + memory.dislikes.map { $0.lowercased() }

        for (slotIdx, slot) in focus.slots.enumerated() {
            guard let picked = pickForSlot(
                slot: slot,
                slotIdx: slotIdx,
                profile: profile,
                envs: envs,
                excludeKws: excludeKws,
                excludeIds: pickedIds,
                hashSeed: hashSeed
            ) else { continue }

            let (sets, reps, restSec) = prescription(
                for: picked,
                slotIdx: slotIdx,
                focus: focus,
                memory: memory,
                profile: profile
            )

            let durSec = sets * (45 + restSec) + 30   // ~45s work + rest + 30s transition

            // Optional slots that bust the budget get dropped; required slots
            // override (we'd rather give a slightly-over workout than skip a
            // primary compound).
            if elapsedSec + durSec > budgetSec, slot.optional, !picks.isEmpty {
                continue
            }

            picks.append(GeneratedExercise(
                id: "\(hashSeed)-\(slotIdx)-\(picked.id)",
                exerciseId: picked.id,
                name: picked.name,
                pattern: slot.satisfiedBy,
                isCompound: picked.isCompound,
                sets: sets,
                reps: reps,
                restSeconds: restSec,
                notes: nil
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
    /// exercise. Mutates the slot's `satisfiedBy` field implicitly via the
    /// return tuple (caller stores it on the GeneratedExercise).
    private static func pickForSlot(
        slot: PatternSlot,
        slotIdx: Int,
        profile: DemographicProfile,
        envs: Set<String>,
        excludeKws: [String],
        excludeIds: Set<Int>,
        hashSeed: String
    ) -> Exercise? {
        for pattern in slot.alternatives {
            // Try preferred difficulties first, then fall back across the
            // whole allowed set (so a beginner-only catalog still returns
            // something for an advanced user).
            for bucket in profile.preferredDifficulties {
                let candidates = CoachDatabase.shared.exercises(
                    matchingPattern: pattern,
                    difficulties: [bucket],
                    environments: envs,
                    excludeKeywords: excludeKws,
                    excludeIds: excludeIds,
                    modalities: slot.requiredModalities
                )
                if let pick = deterministicPick(from: candidates, slotIdx: slotIdx, hashSeed: hashSeed) {
                    slot.satisfiedBy = pattern
                    return pick
                }
            }
            // Difficulty-relaxed pass — env + constraints still hold.
            let relaxed = CoachDatabase.shared.exercises(
                matchingPattern: pattern,
                environments: envs,
                excludeKeywords: excludeKws,
                excludeIds: excludeIds,
                modalities: slot.requiredModalities
            )
            if let pick = deterministicPick(from: relaxed, slotIdx: slotIdx, hashSeed: hashSeed) {
                slot.satisfiedBy = pattern
                return pick
            }
        }
        return nil
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

        // Reps — coach.db default wins when set; otherwise from formula.
        let reps = exercise.defaultReps?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? defaultRepsFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)

        // Rest — parse coach.db default if present; otherwise from formula.
        let restSec = exercise.defaultRest.flatMap(parseRestSeconds)
            ?? defaultRestFromFormula(isPrimary: isPrimary, isCompound: isCompound, focus: focus)

        return (sets, reps, restSec)
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
