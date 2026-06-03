import XCTest
@testable import PhaseTraining

/// Build 103 — BodyCompositionEntry is the body-fat % + lean mass series
/// distinct from the daily-weight series. Schema needs to round-trip
/// cleanly and survive partial reads (DEXA users log both, scale users
/// log just BF%).
final class BodyCompositionTests: XCTestCase {

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

    func test_codableRoundTripFullEntry() throws {
        let original = BodyCompositionEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            bodyFatPercent: 18.5,
            leanMassKg: 64.2,
            method: "DEXA",
            note: "Pre-cut baseline"
        )
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(BodyCompositionEntry.self, from: data)
        XCTAssertEqual(decoded.bodyFatPercent, 18.5)
        XCTAssertEqual(decoded.leanMassKg, 64.2)
        XCTAssertEqual(decoded.method, "DEXA")
        XCTAssertEqual(decoded.note, "Pre-cut baseline")
    }

    func test_codableRoundTripBFOnlyEntry() throws {
        // Scale-only users won't have a lean number — make sure the nil
        // path round-trips.
        let original = BodyCompositionEntry(
            date: Date(),
            bodyFatPercent: 22.0
        )
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(BodyCompositionEntry.self, from: data)
        XCTAssertEqual(decoded.bodyFatPercent, 22.0)
        XCTAssertNil(decoded.leanMassKg)
        XCTAssertNil(decoded.method)
    }

    func test_trainingMemoryEmbedsBodyCompositionLog() throws {
        var mem = TrainingMemory()
        mem.bodyCompositionLog = [
            BodyCompositionEntry(date: Date(), bodyFatPercent: 19.0, leanMassKg: 65.0),
            BodyCompositionEntry(date: Date(), bodyFatPercent: 18.5),
        ]
        let data = try encoder().encode(mem)
        let decoded = try decoder().decode(TrainingMemory.self, from: data)
        XCTAssertEqual(decoded.bodyCompositionLog.count, 2)
        XCTAssertEqual(decoded.bodyCompositionLog[0].leanMassKg, 65.0)
        XCTAssertNil(decoded.bodyCompositionLog[1].leanMassKg)
    }

    func test_preBuild103Memory_decodesWithEmptyCompositionLog() throws {
        // Older saves don't have the bodyCompositionLog key. Tolerant decode
        // must default it to [] so legacy saves load cleanly.
        let legacyJSON = """
        {"schemaVersion":6,"sports":[],"focuses":["general_strength"],
         "seasonsBySport":{},"defaultSeason":"maintenance","sessionMinutes":45,
         "liftDaysPerWeek":3,"equipment":["none"],"experience":"beginner",
         "startingState":"fresh_start","usesImperial":true,
         "dislikes":[],"constraints":[],"exerciseAffinities":{},
         "userInjuries":[],"feedback":[],"soreness":[],"weeklyCheckIns":[],
         "coachInsights":[]}
        """.data(using: .utf8)!
        let decoded = try decoder().decode(TrainingMemory.self, from: legacyJSON)
        XCTAssertTrue(decoded.bodyCompositionLog.isEmpty)
        XCTAssertTrue(decoded.bodyWeightLog.isEmpty)
    }
}
