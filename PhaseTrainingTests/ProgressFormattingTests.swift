// ProgressFormattingTests.swift — presentation helpers behind the Progress
// cards, extracted to ProgressStats so they're reachable from a test.
//
// Small functions, but they render every number and date on the tab, and
// their edges are where the surprises are: formatBigNum's magnitude switch
// rounds 9,999 up to "10.0k", daysAgo counts elapsed days rather than
// calendar dates, and normalizedPoints centers a flat series instead of
// flooring it (the doc comment on the original said "flat series → all
// zeros" while the code returned 0.5 — the code was right, and this pins
// which one is the contract).

import XCTest
@testable import PhaseTraining

final class ProgressFormattingTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - formatBigNum

    func test_formatBigNum_zero() {
        XCTAssertEqual(ProgressStats.formatBigNum(0), "0")
    }

    func test_formatBigNum_subThousand_dropsTrailingZeroDecimal() {
        XCTAssertEqual(ProgressStats.formatBigNum(7), "7")
        XCTAssertEqual(ProgressStats.formatBigNum(250), "250")
        XCTAssertEqual(ProgressStats.formatBigNum(999), "999")
    }

    func test_formatBigNum_subThousand_keepsOneDecimalWhenFractional() {
        XCTAssertEqual(ProgressStats.formatBigNum(0.5), "0.5")
        XCTAssertEqual(ProgressStats.formatBigNum(112.5), "112.5")
        XCTAssertEqual(ProgressStats.formatBigNum(999.4), "999.4")
    }

    func test_formatBigNum_thousandsBoundary() {
        // 999 renders exactly; 1000 switches to the k form.
        XCTAssertEqual(ProgressStats.formatBigNum(999), "999")
        XCTAssertEqual(ProgressStats.formatBigNum(1000), "1.0k")
        XCTAssertEqual(ProgressStats.formatBigNum(1500), "1.5k")
        XCTAssertEqual(ProgressStats.formatBigNum(9500), "9.5k")
    }

    func test_formatBigNum_tenThousandBoundary() {
        // 9,999 is still in the one-decimal branch, where %.1f rounds it to
        // "10.0k" — deliberate, and the reason this boundary is pinned.
        XCTAssertEqual(ProgressStats.formatBigNum(9999), "10.0k")
        XCTAssertEqual(ProgressStats.formatBigNum(10_000), "10k")
        XCTAssertEqual(ProgressStats.formatBigNum(42_350), "42k")
    }

    func test_formatBigNum_truncatesRatherThanRoundsAboveTenK() {
        // Weekly volume runs to six figures; "42k" is the honest precision
        // at that magnitude, and the k value truncates, not rounds.
        XCTAssertEqual(ProgressStats.formatBigNum(42_999), "42k")
        XCTAssertEqual(ProgressStats.formatBigNum(999_999), "999k")
    }

    // MARK: - daysAgo

    func test_daysAgo_todayYesterdayAndN() {
        XCTAssertEqual(daysAgo(hoursBack: 0), "today")
        XCTAssertEqual(daysAgo(daysBack: 1), "yesterday")
        XCTAssertEqual(daysAgo(daysBack: 3), "3d ago")
        XCTAssertEqual(daysAgo(daysBack: 45), "45d ago")
    }

    func test_daysAgo_countsElapsedDaysNotCalendarDates() {
        // 23 hours ago is still "today" even if the calendar date changed.
        XCTAssertEqual(daysAgo(hoursBack: 23), "today")
        // 25 hours ago has crossed one whole day.
        XCTAssertEqual(daysAgo(hoursBack: 25), "yesterday")
    }

    func test_daysAgo_futureDateReadsAsToday() {
        // A future-dated import must not render "-3d ago".
        XCTAssertEqual(daysAgo(daysBack: -3), "today")
    }

    private func daysAgo(daysBack: Int = 0, hoursBack: Int = 0) -> String {
        let shifted = calendar.date(byAdding: .day, value: -daysBack, to: now)!
        let date = calendar.date(byAdding: .hour, value: -hoursBack, to: shifted)!
        return ProgressStats.daysAgo(date, now: now, calendar: calendar)
    }

    // MARK: - isWithinDays (per-exercise PR flag)

    func test_isWithinDays_boundaryIsInclusive() {
        XCTAssertTrue(within(14, daysBack: 14))
        XCTAssertFalse(within(14, daysBack: 15))
        XCTAssertTrue(within(14, daysBack: 0))
    }

    func test_isWithinDays_nilDateIsNotRecent() {
        XCTAssertFalse(
            ProgressStats.isWithinDays(14, of: nil, now: now, calendar: calendar)
        )
    }

    func test_isWithinDays_futureDateCountsAsRecent() {
        // Elapsed days go negative, which is <= 14. A future-dated PR flags
        // as recent rather than silently dropping off the tile.
        XCTAssertTrue(within(14, daysBack: -2))
    }

    private func within(_ days: Int, daysBack: Int) -> Bool {
        let date = calendar.date(byAdding: .day, value: -daysBack, to: now)!
        return ProgressStats.isWithinDays(days, of: date, now: now, calendar: calendar)
    }

    // MARK: - normalizedPoints

    func test_normalizedPoints_spreadSeriesMapsToUnitInterval() {
        let out = ProgressStats.normalizedPoints(points([100, 150, 200]))
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(out[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(out[2], 1.0, accuracy: 0.0001)
    }

    func test_normalizedPoints_minAndMaxAlwaysHitTheEnds() {
        // Order-independent: the low point is 0 and the high point is 1
        // wherever they fall in the series.
        let out = ProgressStats.normalizedPoints(points([185, 135, 225, 205]))
        XCTAssertEqual(out.min()!, 0.0, accuracy: 0.0001)
        XCTAssertEqual(out.max()!, 1.0, accuracy: 0.0001)
        XCTAssertEqual(out[1], 0.0, accuracy: 0.0001)  // 135, the lightest
        XCTAssertEqual(out[2], 1.0, accuracy: 0.0001)  // 225, the heaviest
    }

    func test_normalizedPoints_flatSeriesCenters() {
        // A plateau has no shape. Centering draws a flat line through the
        // middle of the tile; flooring to 0 would pin it to the bottom edge
        // and read as a collapse in strength.
        let out = ProgressStats.normalizedPoints(points([150, 150, 150]))
        XCTAssertEqual(out, [0.5, 0.5, 0.5])
    }

    func test_normalizedPoints_emptyAndSinglePoint() {
        XCTAssertTrue(ProgressStats.normalizedPoints([]).isEmpty)
        XCTAssertEqual(ProgressStats.normalizedPoints(points([185])), [0.5])
    }

    func test_normalizedPoints_preservesCount() {
        for weights in [[100.0], [100, 100], [100, 200, 300, 400]] {
            XCTAssertEqual(
                ProgressStats.normalizedPoints(points(weights)).count,
                weights.count
            )
        }
    }

    private func points(_ weights: [Double]) -> [ProgressAggregates.SparkPoint] {
        weights.enumerated().map { i, w in
            ProgressAggregates.SparkPoint(
                date: calendar.date(byAdding: .day, value: i, to: now)!,
                weight: w
            )
        }
    }
}
