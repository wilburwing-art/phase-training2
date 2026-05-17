// CustomRoutine.swift — user-created workouts.
//
// Stored as JSON in UserDefaults (key: `pt_custom_routines`). Kept structurally
// distinct from the bundled `Routine` type so coach.db stays read-only and we
// don't have to invent fake int ids for custom rows.
//
// Each CustomRoutine owns its own exercise list. Each CustomRoutineExercise
// references a real coach.db exercise by id (so substitutions still work) but
// carries its own sets / reps / rest / notes that the user picked when
// building the workout.
//
// Bridges to the existing workflow via `toWorkoutTemplate()` (for starting
// the session) and `toRoutineExercises()` (for sharing the RoutineDetailScreen
// editing UI).

import Foundation

struct CustomRoutine: Codable, Identifiable, Hashable {
    var id: String           // UUID().uuidString
    var name: String
    var exercises: [CustomRoutineExercise]
    var createdAt: Date
}

struct CustomRoutineExercise: Codable, Identifiable, Hashable {
    var id: String           // UUID().uuidString
    var exerciseId: Int      // coach.db exercises.id
    var name: String
    var position: Int
    var sets: Int?
    var reps: String?
    var rest: String?
    var notes: String?
}

// MARK: - Bridging to the workout runtime

extension CustomRoutine {
    /// Empty starter for the "+ Create custom workout" entry point.
    static func makeBlank() -> CustomRoutine {
        CustomRoutine(
            id: UUID().uuidString,
            name: "",
            exercises: [],
            createdAt: Date()
        )
    }

    /// Convert to a WorkoutTemplate so SessionStore.createSession can consume
    /// it the same way it consumes bundled routines.
    func toWorkoutTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            id: "custom-\(id)",
            name: name.isEmpty ? "Custom workout" : name,
            category: "Custom",
            exercises: exercises.map { cex in
                ExerciseTemplate(
                    id: "cex-\(cex.id)",
                    name: cex.name,
                    type: nil,
                    unit: "lbs",
                    targetSets: cex.sets ?? 3,
                    targetReps: Self.parseRepsLeading(cex.reps) ?? 8,
                    rest: Self.parseRestSeconds(cex.rest) ?? 90
                )
            }
        )
    }

    /// Render as a list of bundled-style RoutineExercises so the existing
    /// RoutineDetailScreen UI can edit a custom routine. RoutineExercise.id
    /// is Int — we use the cex's index to fabricate a stable negative id
    /// that won't collide with the bundled coach.db rows.
    func toRoutineExercises() -> [RoutineExercise] {
        exercises.enumerated().map { idx, cex in
            RoutineExercise(
                id: -(idx + 1),
                exerciseId: cex.exerciseId,
                name: cex.name,
                position: cex.position,
                sets: cex.sets,
                reps: cex.reps,
                rest: cex.rest,
                notes: cex.notes
            )
        }
    }

    /// Reverse: take edited RoutineExercises (from the shared detail UI) and
    /// rebuild the CustomRoutine's exercise list, regenerating stable cex ids
    /// for new rows + preserving existing ones by position.
    func updatingExercises(from edited: [RoutineExercise]) -> CustomRoutine {
        let newExercises = edited.enumerated().map { idx, rex -> CustomRoutineExercise in
            // Preserve existing cex id when the edited row is at a slot the
            // existing custom routine had — keeps Codable stable across edits.
            let preservedId: String = exercises.indices.contains(idx)
                ? exercises[idx].id
                : UUID().uuidString
            return CustomRoutineExercise(
                id: preservedId,
                exerciseId: rex.exerciseId,
                name: rex.name,
                position: idx + 1,
                sets: rex.sets,
                reps: rex.reps,
                rest: rex.rest,
                notes: rex.notes
            )
        }
        var copy = self
        copy.exercises = newExercises
        return copy
    }

    private static func parseRepsLeading(_ s: String?) -> Int? {
        guard let s, let digits = s.prefix(while: { $0.isNumber }).description as String?, let n = Int(digits) else { return nil }
        return n
    }

    private static func parseRestSeconds(_ s: String?) -> Int? {
        guard let s = s?.lowercased() else { return nil }
        let digits = s.prefix(while: { $0.isNumber || $0 == "." })
        guard let n = Double(digits) else { return nil }
        if s.contains("min") { return Int(n * 60) }
        return Int(n)
    }
}
