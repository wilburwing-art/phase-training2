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
        strategy: GeneratorStrategy = .auto,
        adjacentSportDay: Bool = false
    ) -> GeneratedWorkout {
        // The season-aware engine (ski / climb) is the only generator. Every
        // caller routes here; onboarding gates to a supported sport (M2b), so the
        // no-supported-sport branch is an unreachable safety net, not a real path.
        // `context` / `strategy` are accepted for signature stability but the
        // season engine doesn't consume them yet — parked for a future adaptive
        // wiring milestone (readiness/soreness/overload + LLM build_workout).
        guard SportSeasonGenerator.supports(memory.primarySport?.slug) else {
            return GeneratedWorkout(
                title: "Rest",
                summary: "No supported sport set",
                exercises: [],
                estimatedMinutes: 0,
                provenance: "no-supported-sport",
                focus: WorkoutFocus.lift(liftIndex: liftIndex, totalLifts: totalLifts))
        }
        let athlete = AthleteState.from(
            memory,
            variant: SportSeasonGenerator.defaultVariant(forSport: memory.primarySport?.slug),
            weekNumber: memory.weeksInCurrentPhase ?? 1,
            recentMovementIDs: recentlyPicked)
        return SportSeasonGenerator.generateSession(
            athlete, sessionIndex: liftIndex, adjacentSportDay: adjacentSportDay)
    }

    /// Generate a workout for a consolidated (merged) day. The season engine has
    /// no separate consolidation concept — a consolidated day is just one season
    /// session — so this routes straight through `generateLift`. `day` is kept in
    /// the signature for call-site stability; its focus pairing is unused now that
    /// the legacy recipe path is gone.
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
        return generateLift(
            liftIndex: liftIndex, totalLifts: totalLifts, memory: memory,
            profile: profile, hashSeed: hashSeed, recentlyPicked: recentlyPicked,
            context: context, strategy: strategy)
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
