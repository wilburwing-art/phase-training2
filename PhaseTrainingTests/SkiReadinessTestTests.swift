import XCTest
@testable import PhaseTraining

/// The pre-season ski test: labels, the change since the last test, and the
/// field joining memory without breaking an older payload.
final class SkiReadinessTestTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    func test_deltaOnlyWhenBothTestsCarryTheMetric() {
        let before = SkiReadinessTest(date: day, wallSitSeconds: 84, lateralHops30s: 40)
        let after = SkiReadinessTest(date: day.addingTimeInterval(21 * 86_400),
                                     wallSitSeconds: 90, balanceLeftSeconds: 22, lateralHops30s: 38)
        XCTAssertEqual(after.deltaLabel(.wallSit, from: before, imperial: true), "+6s")
        XCTAssertEqual(after.deltaLabel(.lateralHops, from: before, imperial: true), "-2")
        XCTAssertNil(after.deltaLabel(.balanceLeft, from: before, imperial: true),
                     "the earlier test skipped balance, so there is nothing to compare")
        XCTAssertNil(after.deltaLabel(.broadJump, from: before, imperial: true))
    }

    func test_labels() {
        let t = SkiReadinessTest(date: day, wallSitSeconds: 90, lateralHops30s: 41, broadJumpCm: 218.44)
        XCTAssertEqual(t.label(.wallSit, imperial: true), "90s")
        XCTAssertEqual(t.label(.lateralHops, imperial: true), "41 in 30s")
        XCTAssertEqual(t.label(.broadJump, imperial: true), "7 ft 2 in")
        XCTAssertEqual(t.label(.broadJump, imperial: false), "218 cm")
        XCTAssertNil(t.label(.balanceRight, imperial: true))
        let longer = SkiReadinessTest(date: day, broadJumpCm: 226.06)
        XCTAssertEqual(longer.deltaLabel(.broadJump, from: t, imperial: true), "+3 in")
        XCTAssertEqual(longer.deltaLabel(.broadJump, from: t, imperial: false), "+8 cm")
    }

    func test_emptyTestIsEmpty() {
        XCTAssertTrue(SkiReadinessTest(date: day).isEmpty)
        XCTAssertFalse(SkiReadinessTest(date: day, balanceRightSeconds: 12).isEmpty)
    }

    func test_memoryRoundTrips_andOldPayloadsDecode() throws {
        var m = TrainingMemory()
        m.skiReadinessTests = [SkiReadinessTest(date: day, wallSitSeconds: 75)]
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(TrainingMemory.self, from: data).skiReadinessTests.first?.wallSitSeconds, 75)

        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "skiReadinessTests")
        let old = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(try JSONDecoder().decode(TrainingMemory.self, from: old).skiReadinessTests, [])
    }

    func test_skisCoversSkiAndSnowboard_notClimbing() throws {
        var m = TrainingMemory()
        XCTAssertFalse(m.skis)
        m.sports = [try XCTUnwrap(Sport.catalog.first { $0.slug == "climbing" })]
        XCTAssertFalse(m.skis)
        m.sports = [try XCTUnwrap(Sport.catalog.first { $0.slug == "alpine-skiing" })]
        XCTAssertTrue(m.skis)
        m.sports = [try XCTUnwrap(Sport.catalog.first { $0.slug == "snowboarding" })]
        XCTAssertTrue(m.skis)
    }
}
