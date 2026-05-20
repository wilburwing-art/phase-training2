// ExerciseStaplesTests.swift — guards the staple preference layer (build 95).
//
// Two risk areas:
//   1. The keyword map matches actual coach.db exercise names. A typo or
//      misaligned keyword would silently produce empty staple pools and
//      regress to the old uniform-pick behavior.
//   2. The deterministic generator narrows to staples when the candidate
//      pool contains any. New-user, no-recently-picked → must surface a
//      recognized staple for each major pattern.

import XCTest
@testable import PhaseTraining

final class ExerciseStaplesTests: XCTestCase {

    func test_isStaple_matchesKnownLifts() {
        XCTAssertTrue(ExerciseStaples.isStaple(name: "Dumbbell Bench Press", forPattern: "horizontal-push"))
        XCTAssertTrue(ExerciseStaples.isStaple(name: "Push-Up", forPattern: "horizontal-push"))
        XCTAssertTrue(ExerciseStaples.isStaple(name: "Barbell Back Squat", forPattern: "squat"))
        XCTAssertTrue(ExerciseStaples.isStaple(name: "Conventional Deadlift", forPattern: "hip-hinge"))
        XCTAssertTrue(ExerciseStaples.isStaple(name: "Weighted Pull-Up", forPattern: "vertical-pull"))
        XCTAssertTrue(ExerciseStaples.isStaple(name: "Farmer's Carry", forPattern: "loaded-carry"))
    }

    func test_isStaple_skipsObscureVariants() {
        XCTAssertFalse(ExerciseStaples.isStaple(name: "Single-arm Landmine Press", forPattern: "horizontal-push"))
        XCTAssertFalse(ExerciseStaples.isStaple(name: "Pole-Fitness Climb Pull-Up", forPattern: "horizontal-push"))
        XCTAssertFalse(ExerciseStaples.isStaple(name: "Surfboard Pop-Up", forPattern: "squat"))
    }

    func test_isStaple_unknownPattern_returnsFalse() {
        XCTAssertFalse(ExerciseStaples.isStaple(name: "Bench Press", forPattern: "not-a-real-pattern"))
    }

    /// End-to-end: each major pattern should have at least one staple in
    /// the live coach.db pool. If this fails, the keyword list and the DB
    /// names have drifted apart — either fix the keywords or backfill the
    /// DB with a missing canonical lift.
    func test_eachMajorPattern_hasAtLeastOneStapleInDb() {
        let patterns = [
            "horizontal-push", "vertical-push",
            "horizontal-pull", "vertical-pull",
            "squat", "hip-hinge",
            "single-leg-squat",
            "loaded-carry", "anti-extension",
            "elbow-flexion", "elbow-extension",
        ]
        for pattern in patterns {
            let pool = CoachDatabase.shared.exercises(matchingPattern: pattern)
            let staples = pool.filter { ExerciseStaples.isStaple(name: $0.name, forPattern: pattern) }
            XCTAssertFalse(
                staples.isEmpty,
                "No staples found in coach.db pool for pattern '\(pattern)'. Pool size: \(pool.count). " +
                "Check ExerciseStaples.keywordsByPattern against actual exercise names."
            )
        }
    }
}
