// WorkoutTemplate.swift — Workout template models + the hardcoded upper-1 template.
// Ports `handoff/proto/data.jsx:3-17` to Swift.

import Foundation

struct ExerciseTemplate: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let type: String?
    let unit: String
    let targetSets: Int
    let targetReps: Int
    let rest: Int
    /// Coaching hints (build 70). Both nil for upper-1 + other hardcoded
    /// templates; populated when the workout comes from the generator's
    /// prescription path. Surface to the user above the set rows.
    var rpe: String?
    var tempo: String?
    /// Superset grouping (build 99). Propagated from
    /// routine_exercises.superset_group; null = not in a superset. Same
    /// integer across two-plus exercises means "rotate between these
    /// sets, then rest." Survives the trip through SessionStore into
    /// LoggedExercise so LogScreen can use it for visual + nav grouping.
    var supersetGroup: Int?

    /// Convenience init so the upper-1 template + everywhere else that
    /// constructs an ExerciseTemplate without coaching hints stays unchanged.
    init(id: String, name: String, type: String?, unit: String,
         targetSets: Int, targetReps: Int, rest: Int,
         rpe: String? = nil, tempo: String? = nil,
         supersetGroup: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.unit = unit
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.rest = rest
        self.rpe = rpe
        self.tempo = tempo
        self.supersetGroup = supersetGroup
    }
}

struct WorkoutTemplate: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let category: String
    let exercises: [ExerciseTemplate]
}

extension WorkoutTemplate {
    static let upper1 = WorkoutTemplate(
        id: "upper-1",
        name: "Upper Body Day 1",
        category: "Push / Pull / Accessories",
        exercises: [
            ExerciseTemplate(id: "bench",    name: "Bench Press",    type: "Barbell",  unit: "lbs",  targetSets: 5, targetReps: 5,  rest: 120),
            ExerciseTemplate(id: "pullup",   name: "Pull Up",        type: nil,        unit: "+lbs", targetSets: 4, targetReps: 5,  rest: 120),
            ExerciseTemplate(id: "ohp",      name: "Overhead Press", type: "Barbell",  unit: "lbs",  targetSets: 4, targetReps: 8,  rest: 120),
            ExerciseTemplate(id: "row",      name: "Incline Row",    type: "Dumbbell", unit: "lbs",  targetSets: 4, targetReps: 10, rest: 90),
            ExerciseTemplate(id: "skull",    name: "Skullcrusher",   type: "Barbell",  unit: "lbs",  targetSets: 3, targetReps: 10, rest: 90),
            ExerciseTemplate(id: "facepull", name: "Face Pull",      type: "Cable",    unit: "lbs",  targetSets: 3, targetReps: 15, rest: 60),
        ]
    )

    static func byId(_ id: String) -> WorkoutTemplate? {
        switch id {
        case "upper-1": return upper1
        default:        return nil
        }
    }
}
