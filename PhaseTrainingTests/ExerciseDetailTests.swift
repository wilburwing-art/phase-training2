// ExerciseDetailTests: the labelled catalog notes the exercise detail shows
// under "Variations and notes" (backlog 2026-11c 6.5).

import XCTest
@testable import PhaseTraining

final class ExerciseDetailTests: XCTestCase {

    private func notes(home: String? = nil, time: String? = nil, age: String? = nil,
                       desk: String? = nil) -> ExerciseCatalogNotes {
        ExerciseCatalogNotes(commonCompensations: [], injuryPreventionNotes: nil,
                             homeVariation: home, timeEfficientVariation: time,
                             ageConsiderations: age, deskWorkerNotes: desk)
    }

    func test_labeledRows_keepDisplayOrder() {
        let rows = notes(home: "h", time: "t", age: "a", desk: "d").labeledRows
        XCTAssertEqual(rows.map(\.text), ["h", "t", "a", "d"])
        XCTAssertEqual(rows.map(\.label), ["At home", "Short on time", "By age", "Desk workers"])
    }

    func test_labeledRows_dropMissingText() {
        let rows = notes(time: "t", desk: "d").labeledRows
        XCTAssertEqual(rows.map(\.label), ["Short on time", "Desk workers"])
    }

    func test_isEmpty_onlyWhenEveryFieldIsMissing() {
        XCTAssertTrue(notes().isEmpty)
        XCTAssertFalse(notes(age: "a").isEmpty)
        XCTAssertFalse(ExerciseCatalogNotes(commonCompensations: ["x"], injuryPreventionNotes: nil,
                                            homeVariation: nil, timeEfficientVariation: nil,
                                            ageConsiderations: nil, deskWorkerNotes: nil).isEmpty)
    }
}
