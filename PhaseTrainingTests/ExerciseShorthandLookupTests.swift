//
//  ExerciseShorthandLookupTests.swift
//  PhaseTrainingTests
//
//  The UI shows short exercise names and coach.db stores specific ones, so
//  every row's photo, muscle bucket and substitution list depends on the
//  shorthand resolving. When it does not, the row renders a muscle-chip
//  placeholder that looks designed rather than broken, so nothing reports it.
//

import XCTest
@testable import PhaseTraining

final class ExerciseShorthandLookupTests: XCTestCase {

    /// Every shorthand in db/aliases_shorthand.sql, with the canonical row it
    /// must land on. Targets are hand-picked: an alias pointing at the wrong
    /// variant shows a plausible photo and reads as correct.
    private let shorthand: [(String, String)] = [
        ("Bench Press",      "Barbell Bench Press"),
        ("Pull Up",          "Pull-Up"),
        ("Overhead Press",   "Barbell Overhead Press (Strict)"),
        ("Incline Row",      "Incline Row (Dumbbell)"),
        ("Skullcrusher",     "Skull Crusher (Lying Triceps Extension)"),
        ("Face Pull",        "Face Pull (Cable or Band)"),
        ("Incline DB Press", "Incline Dumbbell Bench Press"),
        ("Lateral Raise",    "Dumbbell Lateral Raise"),
    ]

    override func setUp() {
        super.setUp()
        ExerciseLookupCache.shared.reset()
    }

    func testShorthandResolvesToItsCanonicalExercise() {
        for (short, canonical) in shorthand {
            let id = ExerciseLookupCache.shared.exerciseID(forName: short)
            XCTAssertNotNil(id, "\(short) did not resolve; its row renders a placeholder")
            let name = id.flatMap { CoachDatabase.shared.exercise(id: $0)?.name }
            XCTAssertEqual(name, canonical, "\(short) resolved to the wrong variant")
        }
    }

    /// The built-in fallback template and the plan generator both feed this
    /// path, so every name either side writes has to resolve.
    func testBuiltInTemplateNamesAllResolve() {
        for ex in WorkoutTemplate.upper1.exercises {
            XCTAssertNotNil(ExerciseLookupCache.shared.exerciseID(forName: ex.name),
                            "upper1 exercise '\(ex.name)' does not resolve")
        }
    }

    /// Canonical names must keep working; the fallback is additive.
    func testCanonicalNamesStillResolve() {
        let id = ExerciseLookupCache.shared.exerciseID(forName: "Barbell Bench Press")
        XCTAssertEqual(id, 900)
    }

    /// A name that means nothing must stay nil rather than fuzzy-matching
    /// onto a plausible neighbour.
    func testUnknownNameDoesNotResolve() {
        XCTAssertNil(ExerciseLookupCache.shared.exerciseID(forName: "Zorble Press"))
    }
}
