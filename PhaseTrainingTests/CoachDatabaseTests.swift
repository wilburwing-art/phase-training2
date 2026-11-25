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

    // Backlog 2026-11c 6.7
    func test_sportRecovery_and_prevalence_emptySlugSetReturnsEmpty() {
        XCTAssertTrue(CoachDatabase.shared.sportRecoveryProfiles(forSportSlugs: []).isEmpty)
        XCTAssertTrue(CoachDatabase.shared.injuryPrevalence(forSportSlugs: []).isEmpty)
    }

    func test_sportRecovery_runningReadsHoursAndTokens() throws {
        let all = CoachDatabase.shared.sportRecoveryProfiles(forSportSlugs: ["running"])
        let p = try XCTUnwrap(all["running"])
        XCTAssertEqual(p.typicalRecoveryHours, 24)
        XCTAssertEqual(p.avoidBeforeSession, ["heavy_squat", "heavy_deadlift", "high_volume_plyo"])
        XCTAssertEqual(p.avoidLabels.first, "Heavy squat")
    }

    func test_sportRecovery_tokenLabels() {
        XCTAssertEqual(SportRecoveryProfile.label(forToken: "high_cns"), "High CNS")
        XCTAssertEqual(SportRecoveryProfile.label(forToken: "cns"), "CNS")
    }

    func test_sportRecovery_missingSlugsAreAbsent() {
        let all = CoachDatabase.shared.sportRecoveryProfiles(
            forSportSlugs: ["general-fitness", "not-a-sport", "running"])
        XCTAssertNil(all["general-fitness"])
        XCTAssertNil(all["not-a-sport"])
        XCTAssertNotNil(all["running"])
    }

    func test_injuryPrevalence_runningAndClimbing() throws {
        let all = CoachDatabase.shared.injuryPrevalence(forSportSlugs: ["running", "climbing"])
        XCTAssertTrue(try XCTUnwrap(all["patellar-tendinopathy"])
            .contains(InjuryPrevalence(sportSlug: "running", level: .common)))
        XCTAssertTrue(try XCTUnwrap(all["finger-pulley"])
            .contains(InjuryPrevalence(sportSlug: "climbing", level: .common)))
        XCTAssertTrue(try XCTUnwrap(all["slap-tear"])
            .contains(InjuryPrevalence(sportSlug: "climbing", level: .occasional)))
        for rows in all.values {
            let sorted = rows.sorted { ($0.level.order, $0.sportSlug) < ($1.level.order, $1.sportSlug) }
            XCTAssertEqual(rows, sorted)
        }
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        XCTAssertTrue(Set(all.keys).isSubset(of: known))
    }

    // MARK: - Equipment unlock counts (6.8)

    func test_exerciseCount_everySlugAllowedCountsTheWholeCatalog() {
        let db = CoachDatabase.shared
        let none = db.exerciseCount(fittingEquipmentSlugs: [])
        let floor = db.exerciseCount(fittingEquipmentSlugs: Equipment.bodyweightAlwaysAvailable)
        let gym = db.exerciseCount(fittingEquipmentSlugs: Equipment.bodyweightAlwaysAvailable
            .union(Equipment.allCases.flatMap(\.specificCoachDbSlugs)))
        XCTAssertGreaterThan(none, 0, "exercises with no required equipment row disappeared")
        XCTAssertGreaterThanOrEqual(floor, none)
        XCTAssertGreaterThan(gym, floor)
    }

    func test_unlocks_everyItemAddsExercisesOverTheFloor() {
        let u = Equipment.unlocks()
        XCTAssertGreaterThan(u.floor, 0)
        XCTAssertNil(u.added[.bodyweight])
        XCTAssertNil(u.added[.fullGym])
        let items = Equipment.allCases.filter { $0 != .bodyweight && $0 != .fullGym }
        XCTAssertEqual(Set(u.added.keys), Set(items))
        for eq in items {
            XCTAssertGreaterThan(u.added[eq] ?? 0, 0, "\(eq.label) unlocks nothing on its own")
        }
    }

    func test_unlocks_dumbbellsAddMoreThanAWeightVest() {
        let u = Equipment.unlocks()
        XCTAssertGreaterThan(u.added[.dumbbells] ?? 0, u.added[.weightVest] ?? 0)
    }
}
