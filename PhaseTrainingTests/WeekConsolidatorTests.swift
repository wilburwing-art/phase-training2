import XCTest
@testable import PhaseTraining

final class WeekConsolidatorTests: XCTestCase {

    private func coverage(_ days: [WeekConsolidator.ConsolidatedDay]) -> Set<WorkoutFocus> {
        var s = Set<WorkoutFocus>()
        for d in days {
            s.insert(d.primary)
            if let sec = d.secondary { s.insert(sec) }
        }
        return s
    }

    private func isUpper(_ f: WorkoutFocus) -> Bool {
        switch f { case .legs, .lower: return false; default: return true }
    }

    func test_noReductionWhenTargetMeetsCount() {
        let r = WeekConsolidator.consolidate([.push, .pull, .legs], to: 3)
        XCTAssertEqual(r, [
            .init(primary: .push, secondary: nil),
            .init(primary: .pull, secondary: nil),
            .init(primary: .legs, secondary: nil),
        ])
    }

    func test_ppl_to2_preservesCoverage() {
        let r = WeekConsolidator.consolidate([.push, .pull, .legs], to: 2)
        XCTAssertEqual(r.count, 2)
        XCTAssertTrue(coverage(r).isSuperset(of: [.push, .pull, .legs]),
                      "every PPL focus must survive as a primary or grafted secondary")
    }

    func test_ppl_to2_mergedDayBalancesRegions() {
        let r = WeekConsolidator.consolidate([.push, .pull, .legs], to: 2)
        guard let merged = r.first(where: { $0.secondary != nil }) else {
            return XCTFail("a merge should have occurred")
        }
        let parts = [merged.primary, merged.secondary].compactMap { $0 }
        XCTAssertTrue(parts.contains(where: isUpper) && parts.contains(where: { !isUpper($0) }),
                      "the merged day should pair an upper and a lower focus, got \(parts)")
    }

    func test_fourDayUpperLower_to2_dropsRepeatsNoGraft() {
        let r = WeekConsolidator.consolidate([.upper, .lower, .upper, .lower], to: 2)
        XCTAssertEqual(r, [
            .init(primary: .upper, secondary: nil),
            .init(primary: .lower, secondary: nil),
        ], "duplicate U/L days collapse without grafting")
    }

    func test_upperLowerFull_to2_preservesCoverage() {
        let r = WeekConsolidator.consolidate([.upper, .lower, .fullBodyA], to: 2)
        XCTAssertEqual(r.count, 2)
        XCTAssertTrue(coverage(r).isSuperset(of: [.upper, .lower, .fullBodyA]))
    }

    func test_belowFeasibleFloor_clampsToCeilHalf_keepsCoverage() {
        // 3 distinct focuses can't fit in 1 day (≤2 focuses/day) — clamp to 2.
        let r = WeekConsolidator.consolidate([.push, .pull, .legs], to: 1)
        XCTAssertEqual(r.count, 2, "clamped to ceil(3/2) = 2 so no coverage is dropped")
        XCTAssertTrue(coverage(r).isSuperset(of: [.push, .pull, .legs]))
    }

    func test_empty_returnsEmpty() {
        XCTAssertTrue(WeekConsolidator.consolidate([], to: 2).isEmpty)
    }
}
