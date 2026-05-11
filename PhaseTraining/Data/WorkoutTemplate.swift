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
