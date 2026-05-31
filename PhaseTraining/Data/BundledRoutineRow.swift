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
    /// routine_exercises.superset_group (nullable). Same int across two-plus
    /// exercises = "do these in a round-robin." Propagated all the way down
    /// to LoggedExercise so LogScreen can render the band + reorder rest nav.
    let supersetGroup: Int?

    init(id: Int, exerciseId: Int, name: String, position: Int,
         sets: Int? = nil, reps: String? = nil, rest: String? = nil,
         notes: String? = nil, supersetGroup: Int? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.position = position
        self.sets = sets
        self.reps = reps
        self.rest = rest
        self.notes = notes
        self.supersetGroup = supersetGroup
    }
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
        // Reps-only movements log as bodyweight (no weight input on the log row).
        let categories = CoachDatabase.shared.equipmentCategory(
            forExerciseIds: Set(exercises.map(\.exerciseId)))
        return WorkoutTemplate(
            id: slug,
            name: name,
            category: [goal, phase].compactMap { $0 }.joined(separator: " · "),
            exercises: exercises.map { rex in
                ExerciseTemplate(
                    id: "rex-\(rex.id)",
                    name: rex.name,
                    type: nil,
                    unit: LoggedExercise.unit(for: categories[rex.exerciseId]),
                    targetSets: rex.sets ?? 3,
                    targetReps: parseRepsLeading(rex.reps) ?? 8,
                    rest: parseRestSeconds(rex.rest) ?? 90,
                    supersetGroup: rex.supersetGroup
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
