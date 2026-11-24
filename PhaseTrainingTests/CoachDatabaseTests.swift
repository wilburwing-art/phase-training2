// CoachDatabaseTests: reads over the bundled coach.db that feed screens
// directly, starting with the prehab and rehab list on the injury card
// (backlog 2026-11c 6.4).

import XCTest
@testable import PhaseTraining

final class CoachDatabaseTests: XCTestCase {

    private var allSlugs: Set<String> {
        Set(CoachDatabase.shared.listInjuries().map(\.slug))
    }

    func test_supportiveExercises_emptySlugSetReturnsEmpty() {
        XCTAssertTrue(CoachDatabase.shared.supportiveExercises(bySlug: []).isEmpty)
    }

    func test_supportiveExercises_knownInjuryReturnsItsRehabRows() {
        let rows = CoachDatabase.shared.supportiveExercises(bySlug: ["achilles-tendinopathy"])["achilles-tendinopathy"] ?? []
        XCTAssertTrue(rows.contains { $0.role == .rehabEarly && $0.name == "Single-Leg Heel Drop (Eccentric)" },
                      "achilles-tendinopathy lost its eccentric heel drop: \(rows.map(\.name))")
    }

    func test_supportiveExercises_everyRoleIsRepresented() {
        let rows = CoachDatabase.shared.supportiveExercises(bySlug: allSlugs).values.flatMap { $0 }
        for role in InjurySupportExercise.Role.allCases {
            XCTAssertTrue(rows.contains { $0.role == role }, "no \(role.rawValue) rows across the catalog")
        }
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty }, "a supportive row has no exercise name")
    }

    func test_supportiveExercises_slugsWithoutRowsAreAbsent() {
        let bySlug = CoachDatabase.shared.supportiveExercises(bySlug: allSlugs)
        XCTAssertTrue(bySlug.values.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(Set(bySlug.keys).isSubset(of: allSlugs))
        XCTAssertLessThan(bySlug.count, allSlugs.count,
                          "every injury has prehab or rehab rows; the card's empty case is now unreachable")
    }

    func test_supportiveExercises_sortedByRoleThenName() {
        for (slug, rows) in CoachDatabase.shared.supportiveExercises(bySlug: allSlugs) {
            let keys = rows.map { ($0.role.order, $0.name) }
            XCTAssertTrue(zip(keys, keys.dropFirst()).allSatisfy { $0 <= $1 }, "\(slug) rows out of order: \(rows)")
        }
    }

    // Backlog 2026-11c 3.8: routine_exercises.rpe holds the program's own
    // stated effort and is NULL wherever the program states none.
    func test_routineExercises_rpeReadsTheProgramsStatedEffort() {
        let climbing = CoachDatabase.shared.exercises(forRoutineId: 1)
        XCTAssertFalse(climbing.isEmpty)
        XCTAssertTrue(climbing.allSatisfy { $0.rpe == "6-7" }, "\(climbing.map(\.rpe))")

        let splitboard = CoachDatabase.shared.exercises(forRoutineId: 297)
        XCTAssertEqual(splitboard.first { $0.position == 1 }?.rpe, "6-7")
        XCTAssertTrue(splitboard.filter { $0.position != 1 }.allSatisfy { $0.rpe == nil },
                      "only the goblet squat row states RPE: \(splitboard.map(\.rpe))")
    }

    func test_routineExercises_rpeIsNilWhereTheProgramStatesNone() {
        let mtb = CoachDatabase.shared.exercises(forRoutineId: 299)
        XCTAssertFalse(mtb.isEmpty)
        XCTAssertTrue(mtb.allSatisfy { $0.rpe == nil }, "\(mtb.map(\.rpe))")
    }

    // Backlog 2026-11c 6.5: catalog coaching text for the exercise detail.
    private func catalogId(_ slug: String) -> Int? {
        CoachDatabase.shared.listExercises().first { $0.slug == slug }?.id
    }

    func test_catalogNotes_readsEveryFieldForAFullyAnnotatedExercise() throws {
        let id = try XCTUnwrap(catalogId("weighted-pull-up"))
        let notes = try XCTUnwrap(CoachDatabase.shared.catalogNotes(forExerciseId: id))
        XCTAssertEqual(notes.commonCompensations,
                       ["kipping hip drive", "shrugging into ears", "elbows flaring wide"])
        XCTAssertEqual(notes.injuryPreventionNotes?.hasPrefix("Protect finger flexors"), true)
        XCTAssertEqual(notes.homeVariation, "Band-assisted pull-up with backpack load.")
        XCTAssertNotNil(notes.timeEfficientVariation)
        XCTAssertNotNil(notes.ageConsiderations)
        XCTAssertNotNil(notes.deskWorkerNotes)
    }

    func test_catalogNotes_nilWhenTheRowHoldsNone() throws {
        let id = try XCTUnwrap(catalogId("barbell-bench-press"))
        XCTAssertNil(CoachDatabase.shared.catalogNotes(forExerciseId: id))
        XCTAssertNil(CoachDatabase.shared.catalogNotes(forExerciseId: -1))
    }

    func test_catalogNotes_coverageMatchesTheCatalog() {
        let all = CoachDatabase.shared.listExercises().compactMap {
            CoachDatabase.shared.catalogNotes(forExerciseId: $0.id)
        }
        XCTAssertGreaterThan(all.filter { !$0.commonCompensations.isEmpty }.count, 150)
        XCTAssertGreaterThan(all.filter { $0.homeVariation != nil }.count, 400)
        XCTAssertTrue(all.allSatisfy { !$0.isEmpty })
    }
}
