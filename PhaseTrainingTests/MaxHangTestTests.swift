import XCTest
@testable import PhaseTraining

/// The max-hang ratio, assisted included, and the field joining memory
/// without breaking an older payload.
final class MaxHangTestTests: XCTestCase {

    func test_ratioIsTotalLoadOverBodyWeight() {
        XCTAssertEqual(MaxHangTest(date: Date(), addedKg: 20, bodyKg: 70).ratio, 90.0 / 70.0, accuracy: 1e-9)
        XCTAssertEqual(MaxHangTest(date: Date(), addedKg: 20, bodyKg: 70).percentLabel, "129% of body weight")
        XCTAssertEqual(MaxHangTest(date: Date(), addedKg: -10, bodyKg: 70).percentLabel, "86% of body weight",
                       "assisted hangs read under 100%")
        XCTAssertEqual(MaxHangTest(date: Date(), addedKg: 0, bodyKg: 0).ratio, 0, "no body weight, no ratio")
    }

    func test_memoryRoundTripsTests_andOldPayloadsDecode() throws {
        var m = TrainingMemory()
        m.maxHangTests = [MaxHangTest(date: Date(timeIntervalSince1970: 1_750_000_000), addedKg: 15, bodyKg: 72)]
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(TrainingMemory.self, from: data).maxHangTests.first?.addedKg, 15)

        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "maxHangTests")
        let old = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(try JSONDecoder().decode(TrainingMemory.self, from: old).maxHangTests, [])
    }

    func test_bodyWeightPrefersTheLatestLogEntry_andClimbingIsDetected() throws {
        var m = TrainingMemory()
        m.weightKg = 70
        XCTAssertEqual(m.currentBodyKg, 70)
        m.bodyWeightLog = [BodyWeightEntry(date: Date(timeIntervalSince1970: 1), weightKg: 68),
                           BodyWeightEntry(date: Date(timeIntervalSince1970: 2), weightKg: 71)]
        XCTAssertEqual(m.currentBodyKg, 71)
        XCTAssertFalse(m.climbs)
        m.sports = [try XCTUnwrap(Sport.catalog.first { $0.slug == "climbing" })]
        XCTAssertTrue(m.climbs)
    }
}
