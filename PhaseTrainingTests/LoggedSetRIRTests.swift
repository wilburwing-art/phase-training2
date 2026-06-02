import XCTest
@testable import PhaseTraining

/// Build 103 — LoggedSet.rir is the new reps-in-reserve field. Tolerant decode
/// must keep pre-build-103 sessions round-tripping cleanly (no migration), and
/// the new field has to survive a JSON round trip when set.
final class LoggedSetRIRTests: XCTestCase {

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    func test_rir_defaultsEmptyForNewSets() {
        let s = LoggedSet(num: 1, weight: "135", reps: "5", rpe: "8", done: true)
        XCTAssertEqual(s.rir, "")
    }

    func test_rir_roundTripsThroughJSON() throws {
        let original = LoggedSet(num: 2, weight: "185", reps: "5", rpe: "9", done: true, isWarmup: false, rir: "2")
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(LoggedSet.self, from: data)
        XCTAssertEqual(decoded.rir, "2")
        XCTAssertEqual(decoded.rpe, "9")
    }

    func test_decodingPreBuild103JSON_omitsRIRField_defaultsToEmpty() throws {
        // Older JSON has no "rir" key — the tolerant decode must fall back
        // to "" so the session loads without errors.
        let legacyJSON = """
        {"num":1,"weight":"135","reps":"5","rpe":"8","done":true,"isWarmup":false}
        """.data(using: .utf8)!
        let decoded = try decoder().decode(LoggedSet.self, from: legacyJSON)
        XCTAssertEqual(decoded.rir, "")
        XCTAssertEqual(decoded.weight, "135")
    }
}
