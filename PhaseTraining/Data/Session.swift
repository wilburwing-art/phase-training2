// Session.swift — Session-shaped models for active + saved workouts.
// Ports `handoff/proto/data.jsx` session-object shape to Swift Codable structs.
//
// Numeric fields on LoggedSet are intentionally `String` to match the prototype's
// TextField binding semantics (raw text in, blank-allowed).

import Foundation

struct LoggedSet: Codable, Equatable {
    var num: Int
    var weight: String
    var reps: String
    var rpe: String
    var done: Bool
}

struct LoggedExercise: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var type: String?
    var unit: String
    var targetSets: Int
    var targetReps: Int
    var rest: Int
    var sets: [LoggedSet]
    var prevSets: [LoggedSet]
    /// Coaching hints — propagated from ExerciseTemplate. Both optional so
    /// pre-build-70 saved sessions decode cleanly without a migration.
    var rpe: String?
    var tempo: String?
    /// Superset grouping — propagated from routine_exercises.superset_group
    /// (or CustomRoutineExercise.supersetGroup). Exercises sharing a value
    /// render adjacently with a colored band + "A1"/"A2" labels in the
    /// LogScreen + DayWorkoutPreviewSheet, and round-robin during rest
    /// navigation. Optional so pre-superset saved sessions decode cleanly.
    var supersetGroup: Int?
}

struct ActiveSession: Codable, Equatable {
    var templateId: String
    var name: String
    var category: String
    var startTime: Date
    var exercises: [LoggedExercise]
    var feel: String?
    var note: String?
}

struct SavedSession: Codable, Identifiable, Equatable {
    var templateId: String
    var name: String
    var category: String
    var startTime: Date
    var exercises: [LoggedExercise]
    var feel: String?
    var note: String?
    var endTime: Date
    var duration: Int // seconds

    var id: TimeInterval { startTime.timeIntervalSince1970 }
}

struct SessionStats: Equatable {
    var totalSets: Int
    var doneSets: Int
    var avgRpe: String // matches prototype's "—" sentinel when no RPEs logged
}

/// A personal-record event: highest weight ever lifted at a given rep count
/// for a given exercise (matched by name). Emitted by `SessionStore.prs(in:)`
/// after each saved session for CompleteScreen to celebrate.
struct PersonalRecord: Equatable, Hashable {
    let exerciseName: String
    let reps: Int
    let weight: Double
    let previousBest: Double?
    let date: Date
}
