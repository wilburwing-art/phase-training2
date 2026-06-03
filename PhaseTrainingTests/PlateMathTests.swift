import XCTest
@testable import PhaseTraining

/// Build 103 — PlateMath powers PlateCalculatorSheet. The greedy allocator
/// has to handle clean stacks (135 = 45-bar + 1×45 per side) AND ones that
/// don't divide evenly (137.5 → falls 2.5 short with the standard set if
/// the user doesn't have 1.25s).
final class PlateMathTests: XCTestCase {

    private let imperial = PlateMath.standardPlates(imperial: true)
    private let metric   = PlateMath.standardPlates(imperial: false)

    func test_target135LbBarOnly() {
        // Empty bar = 45. 135 wants exactly 1×45 per side.
        let r = PlateMath.calculate(target: 135, bar: 45, plates: imperial)!
        XCTAssertEqual(r.perSide, [PlateMath.Row(plate: 45, count: 1)])
        XCTAssertEqual(r.achieved, 135, accuracy: 0.001)
        XCTAssertEqual(r.remainder, 0, accuracy: 0.001)
    }

    func test_target225LbStacksTwoFortyFives() {
        // 225 = 45 + 2×45 per side.
        let r = PlateMath.calculate(target: 225, bar: 45, plates: imperial)!
        XCTAssertEqual(r.perSide, [PlateMath.Row(plate: 45, count: 2)])
        XCTAssertEqual(r.achieved, 225, accuracy: 0.001)
        XCTAssertEqual(r.remainder, 0, accuracy: 0.001)
    }

    func test_target315LbGreedyStack() {
        // 315 = 45 + (3×45 = 135) per side.
        let r = PlateMath.calculate(target: 315, bar: 45, plates: imperial)!
        XCTAssertEqual(r.perSide, [PlateMath.Row(plate: 45, count: 3)])
        XCTAssertEqual(r.achieved, 315, accuracy: 0.001)
    }

    func test_target185LbMixedStack() {
        // 185 → 70 per side → 1×45 + 1×25.
        let r = PlateMath.calculate(target: 185, bar: 45, plates: imperial)!
        XCTAssertEqual(r.perSide, [
            PlateMath.Row(plate: 45, count: 1),
            PlateMath.Row(plate: 25, count: 1),
        ])
        XCTAssertEqual(r.achieved, 185, accuracy: 0.001)
    }

    func test_targetBelowBar_returnsNil() {
        XCTAssertNil(PlateMath.calculate(target: 40, bar: 45, plates: imperial))
    }

    func test_targetEqualToBar_returnsEmptyStack() {
        let r = PlateMath.calculate(target: 45, bar: 45, plates: imperial)!
        XCTAssertTrue(r.perSide.isEmpty)
        XCTAssertEqual(r.achieved, 45, accuracy: 0.001)
        XCTAssertEqual(r.remainder, 0, accuracy: 0.001)
    }

    func test_remainderWhenStandardSetCantHit() {
        // 100 lb bar + per-side target 27.5 → 1×25 + 1×2.5 = 27.5. Exact.
        let r = PlateMath.calculate(target: 100, bar: 45, plates: imperial)!
        XCTAssertEqual(r.remainder, 0, accuracy: 0.001)
        // Now make it odd: 100.5 lb target. 27.75/side: greedy gets 25 + 2.5
        // = 27.5 per side, total achieved 100, remainder 1.
        let odd = PlateMath.calculate(target: 100.5, bar: 45, plates: imperial)!
        XCTAssertEqual(odd.achieved, 100, accuracy: 0.001)
        XCTAssertEqual(odd.remainder, 0.5, accuracy: 0.05)
    }

    func test_metricSet_60kgWith20kgBar() {
        // 60 kg = 20-bar + 1×20 per side.
        let r = PlateMath.calculate(target: 60, bar: 20, plates: metric)!
        XCTAssertEqual(r.perSide, [PlateMath.Row(plate: 20, count: 1)])
        XCTAssertEqual(r.achieved, 60, accuracy: 0.001)
    }

    func test_metricSet_100kgGreedyMix() {
        // 100 kg = 20-bar + 40/side. Greedy: 1×25 + 1×15 = 40. Exact.
        let r = PlateMath.calculate(target: 100, bar: 20, plates: metric)!
        XCTAssertEqual(r.perSide, [
            PlateMath.Row(plate: 25, count: 1),
            PlateMath.Row(plate: 15, count: 1),
        ])
        XCTAssertEqual(r.achieved, 100, accuracy: 0.001)
    }

    func test_floatingPointWobble_doesntLoseAFullPlate() {
        // The smallest plate (2.5) must be PLACED as a trailing denomination,
        // not dropped. 140 = 45-bar + (45 + 2.5) per side. calculate()'s
        // `+ 1e-9` count tolerance guards the integer boundary so a raw count
        // that lands a hair under a whole number never floors down and loses
        // the lifter a plate they need. (137.5 is NOT used here: with the
        // standard set's smallest plate being 2.5 — no 1.25s — it falls 2.5
        // short, which test_remainderWhenStandardSetCantHit already covers.)
        let r = PlateMath.calculate(target: 140, bar: 45, plates: imperial)!
        XCTAssertTrue(r.perSide.contains(PlateMath.Row(plate: 45, count: 1)))
        XCTAssertTrue(r.perSide.contains(PlateMath.Row(plate: 2.5, count: 1)))
        XCTAssertEqual(r.achieved, 140, accuracy: 0.001)
        XCTAssertEqual(r.remainder, 0, accuracy: 0.001)
    }

    func test_hugeTarget_doesNotCrash() {
        // A pasted/fat-fingered huge target must not trap on Int(Double) —
        // raw = perSideTarget/plate can exceed Int.max for small plates.
        // The per-denomination count is clamped to 50, so the call returns
        // a (capped, mostly-remainder) result instead of crashing.
        let r = PlateMath.calculate(target: 9e20, bar: 45, plates: imperial)
        XCTAssertNotNil(r)
        for row in r!.perSide {
            XCTAssertLessThanOrEqual(row.count, 50)
        }
    }
}
