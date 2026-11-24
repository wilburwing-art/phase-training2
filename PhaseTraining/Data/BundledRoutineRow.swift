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
    /// routine_exercises.reps_by_week: the program's own reps per plan week,
    /// week 1 first. Nil serves `reps` every week.
    let repsByWeek: [String]?
    /// routine_exercises.sets_by_week: the program's own set count per plan
    /// week, week 1 first. Nil serves `sets` every week.
    let setsByWeek: [Int]?
    /// routine_exercises.rpe: target effort as the program writes it ("6-7").
    /// Nil where the program states none.
    let rpe: String?

    init(id: Int, exerciseId: Int, name: String, position: Int,
         sets: Int? = nil, reps: String? = nil, rest: String? = nil,
         notes: String? = nil, supersetGroup: Int? = nil,
         repsByWeek: [String]? = nil, setsByWeek: [Int]? = nil,
         rpe: String? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.position = position
        self.sets = sets
        self.reps = reps
        self.rest = rest
        self.notes = notes
        self.supersetGroup = supersetGroup
        self.repsByWeek = repsByWeek
        self.setsByWeek = setsByWeek
        self.rpe = rpe
    }

    /// The reps text for a 1-indexed plan week. Weeks past the written ones
    /// hold the last entry; no week (or no per-week list) gives `reps`.
    func reps(forWeek week: Int?) -> String? {
        guard let week, let list = repsByWeek, !list.isEmpty else { return reps }
        return list[min(max(week, 1), list.count) - 1]
    }

    /// The set count for a 1-indexed plan week, read the way `reps(forWeek:)`
    /// reads reps.
    func sets(forWeek week: Int?) -> Int? {
        guard let week, let list = setsByWeek, !list.isEmpty else { return sets }
        return list[min(max(week, 1), list.count) - 1]
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
    /// `planWeek` picks each row's `reps(forWeek:)` and `sets(forWeek:)`;
    /// nil serves `reps` and `sets`.
    func toWorkoutTemplate(with exercises: [RoutineExercise], planWeek: Int? = nil) -> WorkoutTemplate {
        // Reps-only movements log as bodyweight (no weight input on the log row).
        let categories = CoachDatabase.shared.equipmentCategory(
            forExerciseIds: Set(exercises.map(\.exerciseId)))
        return WorkoutTemplate(
            id: slug,
            name: name,
            category: [goal, phase].compactMap { $0 }.joined(separator: " · "),
            exercises: exercises.map { rex in
                let reps = rex.reps(forWeek: planWeek)
                return ExerciseTemplate(
                    id: "rex-\(rex.id)",
                    name: rex.name,
                    type: nil,
                    unit: LoggedExercise.unit(for: categories[rex.exerciseId]),
                    targetSets: rex.sets(forWeek: planWeek) ?? 3,
                    targetReps: parseRepsLeading(reps) ?? 8,
                    rest: AuthoredRoutine.parseRest(rex.rest) ?? 90,
                    supersetGroup: rex.supersetGroup,
                    repsLabel: reps
                )
            }
        )
    }

    private func parseRepsLeading(_ s: String?) -> Int? {
        guard let s, let digits = s.prefix(while: { $0.isNumber }).description as String?, let n = Int(digits) else { return nil }
        return n
    }
}
