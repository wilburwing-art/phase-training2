import XCTest
@testable import PhaseTraining

/// The latest max-hang test sets added load on the two Lattice protocols:
/// 85% (max hangs) and 80% (7/3 repeaters) of tested total load, against
/// today's body weight, rounded to 2.5 lb.
final class HangboardLoadTests: XCTestCase {

    private let maxHang = "Hangboard Max Hang (20mm Edge)"
    private let repeaters = "Hangboard Repeaters (7/3 Protocol)"

    private func memory(body: Double, tests: [MaxHangTest]) -> TrainingMemory {
        var m = TrainingMemory()
        m.weightKg = body
        m.maxHangTests = tests
        return m
    }

    private func test(_ addedKg: Double, body: Double, daysAgo: Double = 7) -> MaxHangTest {
        MaxHangTest(date: Date().addingTimeInterval(-daysAgo * 86_400), addedKg: addedKg, bodyKg: body)
    }

    func test_maxHang_is85PercentOfTotalLoad() throws {
        // 70 kg + 20 kg = 90 kg total; 85% = 76.5 kg, so +6.5 kg = 14.3 lb -> 15.
        let p = try XCTUnwrap(HangboardLoad.prescription(
            forExerciseNamed: maxHang, memory: memory(body: 70, tests: [test(20, body: 70)])))
        XCTAssertEqual(p.addedLb, 15)
        XCTAssertEqual(p.intensity, 0.85)
        XCTAssertEqual(p.percentLabel, "85% of your test")
    }

    func test_repeaters_is80PercentOfTotalLoad() throws {
        // 80% of 90 kg = 72 kg, so +2 kg = 4.4 lb -> 5.
        let p = try XCTUnwrap(HangboardLoad.prescription(
            forExerciseNamed: repeaters, memory: memory(body: 70, tests: [test(20, body: 70)])))
        XCTAssertEqual(p.addedLb, 5)
        XCTAssertEqual(p.intensity, 0.80)
    }

    func test_bodyWeightHang_givesAssistance() throws {
        // A body-weight max (ratio 1.0): 85% of 72 kg is 10.8 kg off = 23.8 lb -> 25.
        let p = try XCTUnwrap(HangboardLoad.prescription(
            forExerciseNamed: maxHang, memory: memory(body: 72, tests: [test(0, body: 72)])))
        XCTAssertEqual(p.addedLb, -25)
    }

    func test_weighInSinceTheTest_movesTheLoadWithIt() throws {
        var m = memory(body: 70, tests: [test(20, body: 70)])
        m.bodyWeightLog = [BodyWeightEntry(date: Date(), weightKg: 80)]
        // Ratio 90/70 held at 80 kg: 85% total is 87.4 kg, +7.4 kg = 16.4 lb -> 17.5.
        let p = try XCTUnwrap(HangboardLoad.prescription(forExerciseNamed: maxHang, memory: m))
        XCTAssertEqual(p.addedLb, 17.5)
    }

    func test_latestTestWins() throws {
        let m = memory(body: 70, tests: [test(20, body: 70, daysAgo: 1), test(5, body: 70, daysAgo: 40)])
        XCTAssertEqual(HangboardLoad.prescription(forExerciseNamed: maxHang, memory: m)?.addedLb, 15)
    }

    func test_nilWithoutATest_aBodyWeight_orACoveredProtocol() {
        XCTAssertNil(HangboardLoad.prescription(forExerciseNamed: maxHang, memory: memory(body: 70, tests: [])))
        var noBody = TrainingMemory()
        noBody.maxHangTests = [test(20, body: 70)]
        XCTAssertNil(HangboardLoad.prescription(forExerciseNamed: maxHang, memory: noBody))
        XCTAssertNil(HangboardLoad.prescription(forExerciseNamed: "Hangboard Repeaters (Endurance Variant)",
                                                memory: memory(body: 70, tests: [test(20, body: 70)])),
                     "Lattice gives no figure for 10/5 repeaters")
    }
}
