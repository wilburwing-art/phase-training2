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
// whole catalog, and the sheet says it did. A dead end is either no rows at
// all, or only a `.partial` "closest we have" match that a literal hit outside
// the filter beats. Filters still win every other time, so broadening can add
// results, never replace or reorder real ones.

import Foundation

enum ExerciseSearch {

    /// Outcome of one picker query. `broadenedPastFilters` is true when the
    /// filtered query came back empty and these rows came from the full
    /// catalog instead — the sheet surfaces that so the user knows why they
    /// are seeing exercises outside the filter they can see on screen.
    struct Result {
        var exercises: [Exercise]
        var broadenedPastFilters: Bool
        /// Which search tier answered, recorded by A3's explore log so a
        /// partial-only result reads as a dead end. Defaulted for callers
        /// that build a Result by hand.
        var tier: CoachDatabase.SearchTier? = nil
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

        let filtered = db.searchExercises(
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
        //
        // A `.partial` result counts as a dead end too, even though it has
        // rows: that tier answers with "closest we have", and the exercise the
        // user typed may well be sitting in the catalog just outside the
        // filter. Swapping a squat and searching "dumbbell shoulder press"
        // partial-matches every dumbbell leg movement; the real answer is
        // Dumbbell Overhead Press, one filter away.
        guard !trimmed.isEmpty,
              narrows(filters, userSportSlugs: userSportSlugs),
              filtered.exercises.isEmpty || filtered.tier == .partial
        else {
            return Result(exercises: filtered.exercises, broadenedPastFilters: false, tier: filtered.tier)
        }

        let wide = db.searchExercises(
            search: trimmed,
            muscleSlugs: [],
            patternSlugs: [],
            modality: nil,
            difficulty: nil,
            environment: nil,
            compoundOnly: nil,
            userSportSlugs: []
        )
        guard !wide.exercises.isEmpty else {
            return Result(exercises: filtered.exercises, broadenedPastFilters: false, tier: filtered.tier)
        }
        // Dropping the filters has to buy something. When the filtered rows are
        // already as good a match as the wide ones, keep the narrower set.
        guard filtered.exercises.isEmpty || wide.tier < filtered.tier else {
            return Result(exercises: filtered.exercises, broadenedPastFilters: false, tier: filtered.tier)
        }
        return Result(exercises: wide.exercises, broadenedPastFilters: true, tier: wide.tier)
    }

    /// Browse order for an EMPTY search box: exercises the user has chosen
    /// before (positive affinity, mostly from swaps) float to the top, highest
    /// first. Stable, so ties keep catalog order. A typed query never goes
    /// through this: relevance beats preference once the user names something.
    static func preferenceOrdered(_ exercises: [Exercise],
                                  affinities: [String: Int]) -> [Exercise] {
        let scores = AthleteState.lowercasedAffinities(affinities)
        guard scores.values.contains(where: { $0 > 0 }) else { return exercises }
        return exercises.enumerated().sorted { l, r in
            let ls = max(0, scores[l.element.name.lowercased()] ?? 0)
            let rs = max(0, scores[r.element.name.lowercased()] ?? 0)
            if ls != rs { return ls > rs }
            return l.offset < r.offset
        }.map(\.element)
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
