import Foundation

struct BundledRoutineRow: Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let description: String?
    let goal: String?
    let difficulty: String?
    let phase: String?
    let durationMinutes: Int?
    let environment: String?

    let exerciseCount: Int
    let setCount: Int
}

struct RoutineExercise: Identifiable, Hashable {
    let id: Int
    let exerciseId: Int
    let name: String
    let position: Int
    let sets: Int?
    let reps: String?
    let rest: String?
    let notes: String?
}

extension BundledRoutineRow {
    var splitTag: String {
        switch goal {
        case "strength", "direct_strength": return "UPPER"
        case "power":                       return "PUSH"
        case "endurance":                   return "COND"
        case "mobility":                    return "MOB"
        case "recovery":                    return "MOB"
        case "warm_up":                     return "MOB"
        case "prehab", "pt_rehab":          return "PULL"
        case "antagonist", "accessory":     return "LOWER"
        case "balance", "conditioning":     return "COND"
        default:                            return "MOB"
        }
    }
}

extension BundledRoutineRow {
    func toWorkoutTemplate(with exercises: [RoutineExercise]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: slug,
            name: name,
            category: [goal, phase].compactMap { $0 }.joined(separator: " · "),
            exercises: exercises.map { rex in
                ExerciseTemplate(
                    id: "rex-\(rex.id)",
                    name: rex.name,
                    type: nil,
                    unit: "lbs",
                    targetSets: rex.sets ?? 3,
                    targetReps: parseRepsLeading(rex.reps) ?? 8,
                    rest: parseRestSeconds(rex.rest) ?? 90
                )
            }
        )
    }

    private func parseRepsLeading(_ s: String?) -> Int? {
        guard let s, let digits = s.prefix(while: { $0.isNumber }).description as String?, let n = Int(digits) else { return nil }
        return n
    }

    private func parseRestSeconds(_ s: String?) -> Int? {
        guard let s = s?.lowercased() else { return nil }
        let digits = s.prefix(while: { $0.isNumber || $0 == "." })
        guard let n = Double(digits) else { return nil }
        if s.contains("min") { return Int(n * 60) }
        return Int(n)
    }
}
