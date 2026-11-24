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
}
