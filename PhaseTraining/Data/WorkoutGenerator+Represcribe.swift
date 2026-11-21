// WorkoutGenerator+Represcribe.swift
//
// "Refresh prescriptions" for a custom-routine override day (shape B of the
// saved-workout load options): map an EXISTING exercise list to refreshed
// prescriptions WITHOUT re-picking exercises. Each row is prescribed by
// `SportSeasonGenerator.prescribeRefresh`, the season engine's own
// `prescribe`, so a refreshed custom day and a planned day agree for the
// same athlete (the dual-path trap; see the prescription skill).
//
// Deterministic by construction: no RNG, and the caller
// (applyCustomRoutineOverrides) re-derives the refreshed workout on EVERY
// generate() from the persisted intent
// (WeekOverrides.prescriptionRefreshByDate) — so the refresh survives plan
// regeneration exactly like the custom override itself.

import Foundation

extension WorkoutGenerator {
    /// Refresh the prescriptions of a composed custom workout. Never
    /// re-picks: preserves order, ids, names, supersetGroup, and the user's
    /// own notes. Rows whose exerciseId doesn't resolve in coach.db are
    /// returned untouched.
    ///
    /// - `.fullRefresh`: sets, reps, rest, RPE and tempo from the season
    ///   engine (`prescribeRefresh`: demand scheme under the athlete's sport
    ///   and season rule, experience and age adjustment, strategy and
    ///   readiness set scaling), RPE 7 when the prime mover is sore, the
    ///   slot-0 compound warm-up ramp unless sore, and the
    ///   progressive-overload note.
    /// - `.weightsOnly`: ONLY the "target: X" note is recomputed, against
    ///   the STORED reps (the hint maps e1RM to the prescribed band's
    ///   midpoint, so refreshed reps would target the wrong band). Sets /
    ///   reps / rest / rpe / tempo untouched.
    static func represcribe(
        workout: GeneratedWorkout,
        mode: PrescriptionRefreshMode,
        focus: WorkoutFocus,
        memory: TrainingMemory,
        context: GeneratorContext
    ) -> GeneratedWorkout {
        var out = workout
        var totalSec = 0
        // Built the way generateLift builds it. A refresh has no date, so no
        // recovery status.
        let athlete = AthleteState.from(
            memory,
            variant: memory.primaryVariant,
            weekNumber: memory.weeksInCurrentPhase ?? 1,
            readiness: context.hasReadinessData ? context.readinessScore : nil)
        out.exercises = workout.exercises.enumerated().map { idx, row in
            guard let ex = CoachDatabase.shared.exercise(id: row.exerciseId) else {
                totalSec += row.sets * (45 + row.restSeconds) + 30
                return row   // dangling id — keep the stored row untouched
            }
            switch mode {
            case .weightsOnly:
                var updated = row
                let hint = progressiveOverloadHint(
                    for: ex, context: context, memory: memory,
                    prescribedReps: row.reps)
                updated.notes = mergedNotes(user: row.notes, hint: hint)
                totalSec += row.sets * (45 + row.restSeconds) + 30
                return updated
            case .fullRefresh:
                var updated = SportSeasonGenerator.prescribeRefresh(
                    ex, slotIdx: idx, focus: focus, athlete: athlete, strategy: .auto)
                let sore = isMuscleSoreForExercise(ex, memory: memory)
                if sore { updated.rpe = updated.rpe.map { capRPE($0, to: 7.0) } ?? "7" }
                if idx == 0, ex.isCompound, !sore { updated.warmUpSets = WarmUpSet.standardRamp }
                let hint = progressiveOverloadHint(
                    for: ex, context: context, memory: memory, prescribedReps: updated.reps)
                // Identity is the user's: id, name, superset grouping, and
                // their own note merged ahead of the generated notes.
                updated.id = row.id
                updated.name = row.name
                updated.supersetGroup = row.supersetGroup
                updated.notes = mergedNotes(user: row.notes, hint: mergedNotes(user: updated.notes, hint: hint))
                totalSec += updated.sets * (45 + updated.restSeconds) + 30
                return updated
            }
        }
        // Only a full refresh can move the time estimate (sets/rest changed).
        if mode == .fullRefresh {
            let estMin = max(15, totalSec / 60)
            let movements = out.exercises.count == 1
                ? "1 movement" : "\(out.exercises.count) movements"
            out.estimatedMinutes = estMin
            out.summary = "\(movements) · ~\(estMin) min"
        }
        return out
    }

    /// User note first, generated "target: X" hint after. Compose-produced
    /// notes are pure user text, so no hint-stripping is needed — each regen
    /// starts from the freshly composed row, never from a previous merge.
    private static func mergedNotes(user: String?, hint: String?) -> String? {
        let u = (user?.isEmpty == false) ? user : nil
        let h = (hint?.isEmpty == false) ? hint : nil
        switch (u, h) {
        case let (u?, h?): return "\(u) · \(h)"
        case let (u?, nil): return u
        case let (nil, h?): return h
        default: return nil
        }
    }
}
