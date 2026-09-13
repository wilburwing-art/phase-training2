// ExerciseSearch.swift — the query the exercise picker actually runs.
//
// ExercisePickerSheet opens pre-filtered on the swap surfaces: replacing an
// exercise narrows the catalog to "similar exercises" (same muscle bucket +
// same movement category as the source — see ExerciseFilters.similar). That
// pre-filter is a good default for browsing alternatives, but it is AND-ed
// with the search box, and the user never set it. Typing a name the filter
// excludes ("pull ups" while swapping a bench press) returned an empty list
// even though the exercise is in the library, which reads as "the app doesn't
// have it" rather than "your filters hide it".
//
// So a typed query that dead-ends under the current filters re-runs across the
// whole catalog, and the sheet says it did. Filters still rank first: the
// broadened query only ever runs when the filtered one returned nothing, so it
// can add results, never replace or reorder real ones.

import Foundation

enum ExerciseSearch {

    /// Outcome of one picker query. `broadenedPastFilters` is true when the
    /// filtered query came back empty and these rows came from the full
    /// catalog instead — the sheet surfaces that so the user knows why they
    /// are seeing exercises outside the filter they can see on screen.
    struct Result {
        var exercises: [Exercise]
        var broadenedPastFilters: Bool
    }

    /// Run `query` under `filters`, falling back to the unfiltered catalog when
    /// a non-empty query finds nothing under them.
    ///
    /// - Parameters:
    ///   - userSportSlugs: the user's sports, used only when
    ///     `filters.hideOtherSports` is on.
    static func run(query: String,
                    filters: ExerciseFilters,
                    userSportSlugs: [String] = []) -> Result {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let db = CoachDatabase.shared

        let filtered = db.listExercises(
            search: trimmed.isEmpty ? nil : trimmed,
            muscleSlugs: filters.bucket?.memberSlugs ?? [],
            patternSlugs: filters.category?.memberPatternSlugs ?? [],
            modality: filters.modality,
            difficulty: filters.difficulty,
            environment: filters.environment,
            compoundOnly: filters.compoundOnly,
            userSportSlugs: filters.hideOtherSports ? userSportSlugs : []
        )

        // Only a typed query earns the fallback. An empty result with an empty
        // search box means the filters themselves are too tight, which the
        // chips on screen already explain.
        guard filtered.isEmpty,
              !trimmed.isEmpty,
              narrows(filters, userSportSlugs: userSportSlugs)
        else {
            return Result(exercises: filtered, broadenedPastFilters: false)
        }

        // Note the explicit argument list: `listExercises(search:)` alone
        // resolves to the exact-name overload, which has no fuzzy fallback.
        let wide = db.listExercises(
            search: trimmed,
            muscleSlugs: [],
            patternSlugs: [],
            modality: nil,
            difficulty: nil,
            environment: nil,
            compoundOnly: nil,
            userSportSlugs: []
        )
        return Result(exercises: wide, broadenedPastFilters: !wide.isEmpty)
    }

    /// Does this filter set actually remove rows? `hideOtherSports` only does
    /// when the caller has sports to pass, so it doesn't count on its own.
    static func narrows(_ filters: ExerciseFilters, userSportSlugs: [String]) -> Bool {
        filters.bucket != nil
            || filters.category != nil
            || filters.modality != nil
            || filters.difficulty != nil
            || filters.environment != nil
            || filters.compoundOnly != nil
            || (filters.hideOtherSports && !userSportSlugs.isEmpty)
    }
}
