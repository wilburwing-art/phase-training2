// PlateTarget.swift — what the Log screen hands the plate calculator.

import Foundation

struct PlateTarget: Identifiable {
    let id = UUID()
    /// The next undone set's weight, else the last set's; empty when none.
    let weight: String

    init(exercise ex: LoggedExercise) {
        let next = ex.sets.first { !$0.done && $0.weightValue != nil } ?? ex.sets.last { $0.weightValue != nil }
        weight = next?.weightValue.map { String(format: "%g", $0) } ?? ""
    }

    static let barSlugs: Set<String> = ["barbell", "trap-bar", "ez-bar"]

    /// True when the catalog says the exercise needs a loadable bar. Cached
    /// by name: the context menu asks on every render of every block.
    @MainActor static func isBarbell(_ name: String) -> Bool {
        if let hit = barbellCache[name] { return hit }
        var answer = false
        if let id = ExerciseLookupCache.shared.exercise(forName: name)?.id {
            let slugs = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: [id])[id] ?? []
            answer = !slugs.isDisjoint(with: barSlugs)
        }
        barbellCache[name] = answer
        return answer
    }

    @MainActor private static var barbellCache: [String: Bool] = [:]
}
