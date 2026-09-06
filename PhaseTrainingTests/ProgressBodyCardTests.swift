// ProgressBodyCardTests.swift — SCAFFOLD (item 3 of 7).
//
// Body-weight / body-composition card logic from
// ProgressScreen+BodyCards.swift: the per-metric latest-non-nil rule (a
// lean-only newest reading must not blank the BF stat), trendDelta's
// under-2-points nil, and the delta signs each stat block renders.

import XCTest
@testable import PhaseTraining

final class ProgressBodyCardTests: XCTestCase {

    func test_latestBF_ignoresNewerLeanOnlyEntry() { XCTFail("scaffold") }
    func test_latestLean_ignoresNewerBFOnlyEntry() { XCTFail("scaffold") }
    func test_trendDelta_nilUnderTwoPoints() { XCTFail("scaffold") }
    func test_trendDelta_signedFirstToLast() { XCTFail("scaffold") }
    func test_compositionSeries_skipNilReadingsPerMetric() { XCTFail("scaffold") }
    func test_bodyWeightDelta_signedAgainstFirstEntry() { XCTFail("scaffold") }
}
