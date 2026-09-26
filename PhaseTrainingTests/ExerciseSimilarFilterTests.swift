// ExerciseSimilarFilterTests.swift — the swap picker's "similar exercises"
// pre-filter must resolve alias names. Plan rows can carry an alias
// ("Bench Press" is an alias of Barbell Bench Press); an exact-name-only match
// returned empty filters and the picker opened on the whole catalog.

import XCTest
@testable import PhaseTraining

final class ExerciseSimilarFilterTests: XCTestCase {

    func test_aliasName_resolvesToTheSameFiltersAsTheCanonicalName() throws {
        let canonical = ExerciseFilters.similar(toExerciseNamed: "Barbell Bench Press")
        XCTAssertNotNil(canonical.bucket, "fixture: the canonical name must resolve to a muscle bucket")
        // No category assertion: Barbell Bench Press's pattern slug maps to no
        // MovementCategory in the bundled catalog, so category is nil for both.
        XCTAssertEqual(ExerciseFilters.similar(toExerciseNamed: "Bench Press"), canonical)
        XCTAssertEqual(ExerciseFilters.similar(toExerciseNamed: "bench press"), canonical, "case-insensitive")
    }

    func test_unknownName_leavesTheFiltersEmpty() {
        XCTAssertEqual(ExerciseFilters.similar(toExerciseNamed: "Not A Real Lift 123"), ExerciseFilters())
    }

    func test_swapPickerFromAnAlias_doesNotOpenOnTheWholeCatalog() {
        let filters = ExerciseFilters.similar(toExerciseNamed: "Bench Press")
        let narrowed = ExerciseSearch.run(query: "", filters: filters).exercises.count
        let whole = ExerciseSearch.run(query: "", filters: ExerciseFilters()).exercises.count
        XCTAssertGreaterThan(narrowed, 0)
        XCTAssertLessThan(narrowed, whole)
    }
}
