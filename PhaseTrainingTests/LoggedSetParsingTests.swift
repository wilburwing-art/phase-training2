import XCTest
@testable import PhaseTraining

final class LoggedSetParsingTests: XCTestCase {

    private func set(_ weight: String, _ reps: String = "5") -> LoggedSet {
        LoggedSet(num: 1, weight: weight, reps: reps, rpe: "", done: true)
    }

    func test_weightValue_plainNumber() {
        XCTAssertEqual(set("135").weightValue, 135)
        XCTAssertEqual(set("12.5").weightValue, 12.5)
        XCTAssertEqual(set("0").weightValue, 0)
    }

    func test_weightValue_toleratesFormatsDoubleRejects() {
        // These all returned nil under Double(set.weight), silently dropping
        // the set from volume / PR / trend math.
        XCTAssertEqual(set(" 135").weightValue, 135)      // leading space
        XCTAssertEqual(set("135 ").weightValue, 135)      // trailing space
        XCTAssertEqual(set("+25").weightValue, 25)        // added-weight notation
        XCTAssertEqual(set("60kg").weightValue, 60)       // trailing unit
    }

    func test_weightValue_commaIsDecimalSeparator_notThousands() {
        // EU keypads emit a comma as the decimal separator. A lone comma must
        // mean decimal (60,5 = 60.5) — NOT thousands — or metric users get a
        // silent 10x. Both-separator strings keep "," as thousands grouping.
        XCTAssertEqual(set("60,5").weightValue, 60.5)
        XCTAssertEqual(set("2,5").weightValue, 2.5)
        XCTAssertEqual(set("1,250.5").weightValue, 1250.5)
    }

    func test_repsValue_outOfRange_returnsNilNotCrash() {
        // 23 digits parses to ~1e22; the old Int(Double) initializer trapped.
        XCTAssertNil(set("100", String(repeating: "1", count: 23)).repsValue)
    }

    func test_weightValue_nilForBodyweightAndBlank() {
        XCTAssertNil(set("").weightValue)
        XCTAssertNil(set("BW").weightValue)
        XCTAssertNil(set("bodyweight").weightValue)
    }

    func test_repsValue() {
        XCTAssertEqual(set("135", "8").repsValue, 8)
        XCTAssertEqual(set("135", " 8 ").repsValue, 8)
        XCTAssertEqual(set("135", "8-10").repsValue, 8)   // range → first number
        XCTAssertNil(set("135", "").repsValue)
        XCTAssertNil(set("135", "AMRAP").repsValue)
    }
}
