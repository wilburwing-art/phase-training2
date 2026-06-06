// CoachInsightPruneTests.swift — characterization tests for CoachInsight.prune.
//
// Pins the rolling 30-day retention window documented in CoachInsight.swift:
// prune(_:now:) keeps every insight dated at-or-after (now - 30 days) and
// drops everything older. It is a window filter, not a keep-newest-N cap.
// All tests inject a fixed `now`; the cutoff is recomputed with the same
// Calendar API the implementation uses so boundary assertions stay exact
// across time zones and DST transitions.

import XCTest
@testable import PhaseTraining

final class CoachInsightPruneTests: XCTestCase {

    // MARK: - Helpers

    /// Fixed reference instant: noon local time on Monday, May 11, 2026.
    /// Noon keeps the -30-day calendar math clear of DST midnight edges.
    private func fixedNow() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    /// The exact retention cutoff prune uses for the given `now`.
    private func cutoff(now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -30, to: now)!
    }

    private func insight(date: Date, body: String = "reflection") -> CoachInsight {
        CoachInsight(date: date, body: body)
    }

    // MARK: - Retention window

    func test_prune_keepsAllInsightsWithinWindow() {
        let now = fixedNow()
        let input = [
            insight(date: now, body: "today"),
            insight(date: now.addingTimeInterval(-7 * 86_400), body: "last week"),
            insight(date: now.addingTimeInterval(-20 * 86_400), body: "three weeks ago"),
        ]

        let survivors = CoachInsight.prune(input, now: now)

        XCTAssertEqual(survivors, input)
    }

    func test_prune_dropsInsightsOlderThanWindow() {
        let now = fixedNow()
        let edge = cutoff(now: now)
        let fresh = insight(date: now.addingTimeInterval(-86_400), body: "yesterday")
        let stale = insight(date: edge.addingTimeInterval(-10 * 86_400), body: "forty days ago")
        let ancient = insight(date: .distantPast, body: "distant past")

        let survivors = CoachInsight.prune([stale, fresh, ancient], now: now)

        XCTAssertEqual(survivors, [fresh])
    }

    func test_prune_keepsFutureDatedInsight() {
        // The window has no upper bound: only the 30-day lower cutoff applies.
        let now = fixedNow()
        let future = insight(date: now.addingTimeInterval(86_400), body: "tomorrow")

        let survivors = CoachInsight.prune([future], now: now)

        XCTAssertEqual(survivors, [future])
    }

    // MARK: - Boundary

    func test_prune_keepsInsightExactlyAtCutoff() {
        // Comparison is `>= cutoff`, so an insight dated exactly 30 calendar
        // days before `now` survives.
        let now = fixedNow()
        let atBoundary = insight(date: cutoff(now: now), body: "boundary")

        let survivors = CoachInsight.prune([atBoundary], now: now)

        XCTAssertEqual(survivors, [atBoundary])
    }

    func test_prune_dropsInsightJustBeforeCutoff() {
        let now = fixedNow()
        let justOutside = insight(
            date: cutoff(now: now).addingTimeInterval(-1),
            body: "one second too old"
        )

        let survivors = CoachInsight.prune([justOutside], now: now)

        XCTAssertTrue(survivors.isEmpty)
    }

    // MARK: - Empty / all-dropped

    func test_prune_emptyList_returnsEmpty() {
        XCTAssertTrue(CoachInsight.prune([], now: fixedNow()).isEmpty)
    }

    func test_prune_allOlderThanWindow_returnsEmpty() {
        let now = fixedNow()
        let edge = cutoff(now: now)
        let input = [
            insight(date: edge.addingTimeInterval(-86_400)),
            insight(date: edge.addingTimeInterval(-365 * 86_400)),
        ]

        XCTAssertTrue(CoachInsight.prune(input, now: now).isEmpty)
    }

    // MARK: - Order preservation

    func test_prune_preservesInputOrderOfSurvivors() {
        // Survivors keep their relative input order even when the input is
        // not date-sorted; prune filters, it does not sort.
        let now = fixedNow()
        let stale = insight(date: cutoff(now: now).addingTimeInterval(-86_400), body: "stale")
        let newest = insight(date: now, body: "newest")
        let middle = insight(date: now.addingTimeInterval(-10 * 86_400), body: "middle")
        let oldest = insight(date: now.addingTimeInterval(-25 * 86_400), body: "oldest")

        let survivors = CoachInsight.prune([middle, stale, newest, oldest], now: now)

        XCTAssertEqual(survivors, [middle, newest, oldest])
    }

    func test_prune_returnsSurvivorsUnmodified() {
        // Filtering must pass elements through intact — same id, body, date,
        // and surface as the input.
        let now = fixedNow()
        var original = insight(date: now, body: "untouched")
        original.surface = "today"

        let survivors = CoachInsight.prune([original], now: now)

        XCTAssertEqual(survivors.count, 1)
        XCTAssertEqual(survivors[0].id, original.id)
        XCTAssertEqual(survivors[0].body, "untouched")
        XCTAssertEqual(survivors[0].date, now)
        XCTAssertEqual(survivors[0].surface, "today")
    }
}
