// ExerciseSheetCoordination.swift — shared sheet-presentation plumbing for
// the exercise surfaces (TodayScreen, DayWorkoutPreviewSheet, LogScreen,
// CoachRequestScreen, CustomRoutineEditSheet).
//
// The screens drive their swap / edit / action sheets off an optional
// Int index into the exercise array, and the filtered-history sheet off an
// optional exercise-name String (CustomRoutineEditSheet wraps a stable row-id
// String instead). `.sheet(item:)` needs an Identifiable, so
// the wrappers + Binding helpers here lift the raw optionals without each
// screen hand-rolling its own Binding(get:set:). The shared "similar
// exercises" pre-filter for the swap picker lives here too, so all the
// swap surfaces filter the same way.

import SwiftUI

/// Identifiable wrapper so `.sheet(item:)` can bind to an optional exercise
/// index — drives the swap / edit / action-sheet presentations.
struct ExerciseSheetIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Identifiable wrapper so `.sheet(item:)` can bind to an optional exercise
/// name string — drives the filtered HistoryScreen presentation.
struct ExerciseSheetName: Identifiable {
    let name: String
    var id: String { name }
}

extension Binding where Value == Int? {
    /// Lift an optional exercise index into the Identifiable wrapper
    /// `.sheet(item:)` needs.
    var exerciseSheetItem: Binding<ExerciseSheetIndex?> {
        Binding<ExerciseSheetIndex?>(
            get: { wrappedValue.map(ExerciseSheetIndex.init) },
            set: { wrappedValue = $0?.index }
        )
    }
}

extension Binding where Value == String? {
    /// Lift an optional exercise name into the Identifiable wrapper
    /// `.sheet(item:)` needs.
    var exerciseSheetItem: Binding<ExerciseSheetName?> {
        Binding<ExerciseSheetName?>(
            get: { wrappedValue.map(ExerciseSheetName.init) },
            set: { wrappedValue = $0?.name }
        )
    }
}

// MARK: - Similar-exercise pre-filter

extension ExerciseFilters {
    /// Resolve "similar exercises" filters for the swap picker — same muscle
    /// bucket AND same movement category as the named source exercise, so the
    /// picker opens narrowed to true alternatives (same body area AND same
    /// movement pattern style), not just any exercise in the same bucket.
    /// Bucket prefers the primary muscle role, then secondary; category takes
    /// the first pattern slug that maps (patterns carry no role concept).
    /// Returns empty filters when the name can't be resolved in coach.db
    /// (custom routines without a backing exerciseId).
    static func similar(toExerciseNamed name: String) -> ExerciseFilters {
        var filters = ExerciseFilters()
        guard let dbEx = CoachDatabase.shared
                .listExercises(search: name)
                .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return filters }

        let muscles = CoachDatabase.shared.musclesForExercise(dbEx.id).sorted { lhs, rhs in
            let rank: (String) -> Int = { r in r == "primary" ? 0 : (r == "secondary" ? 1 : 2) }
            return rank(lhs.role) < rank(rhs.role)
        }
        for entry in muscles {
            if let bucket = MuscleBucket.bucket(forSlug: entry.slug) {
                filters.bucket = bucket
                break
            }
        }
        for slug in CoachDatabase.shared.patternsForExercise(dbEx.id) {
            if let cat = MovementCategory.category(forSlug: slug) {
                filters.category = cat
                break
            }
        }
        return filters
    }
}
