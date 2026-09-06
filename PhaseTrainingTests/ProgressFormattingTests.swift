// ProgressFormattingTests.swift — SCAFFOLD (item 6 of 7).
//
// Presentation helpers the Progress cards use: formatBigNum (stat values, PR
// rows, volume read-out), daysAgo (PR feed / feedback / per-exercise
// suffixes), and normalizedPoints (per-exercise sparkline scaling — its
// flat-series branch is the one nobody has read against the code).

import XCTest
@testable import PhaseTraining

final class ProgressFormattingTests: XCTestCase {

    func test_formatBigNum_zero() { XCTFail("scaffold") }
    func test_formatBigNum_subThousand_dropsTrailingZeroDecimal() { XCTFail("scaffold") }
    func test_formatBigNum_thousandsBoundary() { XCTFail("scaffold") }
    func test_formatBigNum_tenThousandBoundary() { XCTFail("scaffold") }
    func test_daysAgo_todayYesterdayAndN() { XCTFail("scaffold") }
    func test_normalizedPoints_spreadSeriesMapsToUnitInterval() { XCTFail("scaffold") }
    func test_normalizedPoints_flatSeriesCenters() { XCTFail("scaffold") }
    func test_normalizedPoints_emptyAndSinglePoint() { XCTFail("scaffold") }
}
