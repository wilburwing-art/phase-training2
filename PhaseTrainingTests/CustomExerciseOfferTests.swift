import XCTest
@testable import PhaseTraining

final class CustomExerciseOfferTests: XCTestCase {
    private func exercise(_ name: String, id: Int = 1) -> Exercise {
        UserExercise(id: Int64(id), name: name, muscleBucket: nil, notes: nil,
                     createdAt: Date(timeIntervalSince1970: 0)).exercise
    }

    func test_emptyResults_offersTrimmedQuery() {
        XCTAssertEqual(CustomExerciseOffer.trailingRowQuery(query: "  Zercher hold ", results: []), "Zercher hold")
    }

    func test_resultsWithoutExactMatch_offersQuery() {
        let results = [exercise("Zercher Squat")]
        XCTAssertEqual(CustomExerciseOffer.trailingRowQuery(query: "zercher", results: results), "zercher")
    }

    func test_exactMatchInOtherCase_hidesOffer() {
        let results = [exercise("Zercher Squat"), exercise("Sissy Squat", id: 2)]
        XCTAssertNil(CustomExerciseOffer.trailingRowQuery(query: "zercher SQUAT ", results: results))
    }

    func test_emptyQuery_hidesOffer() {
        XCTAssertNil(CustomExerciseOffer.trailingRowQuery(query: "   ", results: [exercise("A")]))
    }
}
