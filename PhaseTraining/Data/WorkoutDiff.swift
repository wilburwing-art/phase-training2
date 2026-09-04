// WorkoutDiff.swift — Phase 13d exercise/set-level edits to today's
// generated workout.
//
// Analogous to PlanDiff (which edits the WeekPlan at the day level) but
// scoped to a single DayPlan.generatedWorkout. Two ops:
//   - swap:    replace one GeneratedExercise with another (by name).
//   - adjust:  change sets / reps / rest of an existing GeneratedExercise.
//
// Address exercises by case-insensitive name match — the model doesn't know
// the stable id strings, and names are the natural reference.
//
// Apply seam: PlanStore.applyWorkoutDiff(_:for:date:) replaces the matching
// DayPlan's generatedWorkout. Refuses when an active session exists (logged
// sets would be lost).

import Foundation

// MARK: - Wire shape (model-friendly)

struct WorkoutChange: Codable, Hashable {
    var op: String                 // "swap" | "adjust"
    // swap
    var fromName: String?          // existing exercise (case-insensitive)
    var toName: String?            // new exercise (free text — no DB lookup in 13d)
    // adjust
    var exerciseName: String?      // existing exercise to adjust
    var sets: Int?
    var reps: String?
    var restSeconds: Int?
    // Optional reason per change — only used when reasoning needs per-row attribution.
    var reason: String?
}

struct WorkoutProposalToolInput: Codable {
    var changes: [WorkoutChange]
    var reasoning: String?
    /// Optional yyyy-MM-dd target day. nil means "today" — the decoder
    /// fills in the caller-provided fallback. Added in build 99 so chat
    /// can edit any day in the current week plan, not just today.
    var date: String?
}

// MARK: - Persisted proposal attached to a CoachMessage

struct CoachWorkoutProposal: Codable, Hashable {
    enum Status: String, Codable { case pending, applied, rejected }
    var id: UUID = UUID()
    /// yyyy-MM-dd of the day this proposal targets — almost always today.
    var dateString: String
    var changes: [WorkoutChange]
    var reasoning: String?
    var status: Status = .pending
}

// MARK: - In-memory diff

struct WorkoutDiff: Hashable {
    let before: GeneratedWorkout
    let after: GeneratedWorkout
    let changes: [WorkoutChange]
    let reasoning: String?

    var isNoop: Bool { before == after }
}

// MARK: - Build diff from proposal

enum WorkoutDiffBuilder {
    /// Apply changes to a snapshot of the workout, returning a WorkoutDiff.
    /// Unknown exercise names are silently skipped — the card shows what
    /// resolved; if the user wanted more, they re-ask.
    static func diff(
        for proposal: CoachWorkoutProposal,
        workout: GeneratedWorkout
    ) -> WorkoutDiff {
        var after = workout
        for change in proposal.changes {
            apply(change, to: &after)
        }
        return WorkoutDiff(
            before: workout,
            after: after,
            changes: proposal.changes,
            reasoning: proposal.reasoning
        )
    }

    private static func apply(_ change: WorkoutChange, to workout: inout GeneratedWorkout) {
        switch change.op {
        case "swap":
            guard let from = change.fromName, let to = change.toName,
                  let idx = workout.exercises.firstIndex(where: { $0.name.caseInsensitiveCompare(from) == .orderedSame }) else { return }
            let existing = workout.exercises[idx]
            // Resolve the model's free-text name against the catalog. Writing
            // `exerciseId: 0` unconditionally (the old behaviour) detached the
            // row from coach.db: no detail sheet, no photo, no muscle
            // attribution, and — load-bearing — no injury contraindication
            // could ever match it, because the exclusion set is a set of real
            // ids. The lookup walks canonical name, then shorthand, slug and
            // aliases, so "Goblet Squat" resolves the way the model writes it.
            let resolved = ExerciseLookupCache.shared.exercise(forName: to)
            workout.exercises[idx] = GeneratedExercise(
                id: existing.id,                      // keep slot id so SessionStore session id mapping holds
                exerciseId: resolved?.id ?? 0,        // 0 only when the catalog has no match
                name: resolved?.name ?? to,
                // Identity travels with the NEW movement, not the old one.
                // Same defect T0-9 fixed at TodayScreen+TemplateEditor and
                // LogScreen; this was the third site and was out of its scope.
                pattern: resolved == nil ? existing.pattern : nil,
                isCompound: resolved?.isCompound ?? existing.isCompound,
                // The DOSE is what the user asked to keep — they asked to swap
                // the movement, not to re-prescribe it.
                sets: existing.sets,
                reps: existing.reps,
                restSeconds: existing.restSeconds,
                // notes/rpe/tempo describe the exercise being replaced. notes
                // in particular can carry a progressive-overload target ("target:
                // 225 lb") computed from the OLD lift's history, which is the
                // safety-relevant half. Dropped rather than inherited.
                notes: nil,
                rpe: nil,
                tempo: nil,
                source: existing.source,
                supersetGroup: existing.supersetGroup
            )

        case "adjust":
            guard let name = change.exerciseName,
                  let idx = workout.exercises.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
            if let s = change.sets         { workout.exercises[idx].sets = max(1, min(20, s)) }
            if let r = change.reps         { workout.exercises[idx].reps = r }
            if let rest = change.restSeconds { workout.exercises[idx].restSeconds = max(15, min(600, rest)) }

        default:
            break
        }
    }
}
