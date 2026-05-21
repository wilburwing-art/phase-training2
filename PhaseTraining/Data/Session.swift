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
    /// Marks a warm-up set. Warmup sets are tracked + displayed in the log
    /// but EXCLUDED from PR detection, volume aggregation, and Epley 1RM
    /// math (see UserDatabase.bestWeightsByExerciseAndReps, MuscleVolume,
    /// StrengthStandards, GeneratorContext.buildStagnantExercises). Optional
    /// on decode so pre-build-100 sessions round-trip cleanly without a
    /// JSON migration; defaults to false.
    var isWarmup: Bool = false

    enum CodingKeys: String, CodingKey {
        case num, weight, reps, rpe, done, isWarmup
    }

    init(num: Int, weight: String, reps: String, rpe: String, done: Bool, isWarmup: Bool = false) {
        self.num = num
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.done = done
        self.isWarmup = isWarmup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.num = try c.decode(Int.self, forKey: .num)
        self.weight = try c.decode(String.self, forKey: .weight)
        self.reps = try c.decode(String.self, forKey: .reps)
        self.rpe = try c.decode(String.self, forKey: .rpe)
        self.done = try c.decode(Bool.self, forKey: .done)
        self.isWarmup = (try? c.decode(Bool.self, forKey: .isWarmup)) ?? false
    }
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
