import XCTest
@testable import PhaseTraining

final class CheckInHistoryTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d))!
    }

    func testRowsNewestWeekFirst() {
        let a = WeeklyCheckIn(weekStart: date(11, 9), intent: "a", lastWeekRating: nil, notes: nil)
        let b = WeeklyCheckIn(weekStart: date(11, 23), intent: "b", lastWeekRating: nil, notes: nil)
        let c = WeeklyCheckIn(weekStart: date(11, 16), intent: "c", lastWeekRating: nil, notes: nil)
        let rows = CheckInHistory.rows([a, b, c])
        XCTAssertEqual(rows.map(\.id), [b.id, c.id, a.id])
    }

    func testBlankFieldsBecomeNil() {
        let c = WeeklyCheckIn(weekStart: date(11, 9), intent: "  ", lastWeekRating: "", notes: "")
        let row = CheckInHistory.rows([c])[0]
        XCTAssertNil(row.intent)
        XCTAssertNil(row.rating)
        XCTAssertNil(row.notes)
    }

    func testSpokenRatingMapsKnownValues() {
        XCTAssertEqual(CheckInHistory.spokenRating("too_easy"), "too easy")
        XCTAssertEqual(CheckInHistory.spokenRating("right"), "about right")
        XCTAssertEqual(CheckInHistory.spokenRating("too_hard"), "too hard")
        XCTAssertNil(CheckInHistory.spokenRating("x"))
        XCTAssertNil(CheckInHistory.spokenRating(nil))
    }

    func testSpokenSkipsMissingParts() {
        let row = CheckInHistoryRow(id: UUID(), weekStart: date(11, 16), intent: nil, rating: "too_hard", notes: nil)
        let s = CheckInHistory.spoken(row) { _ in "Nov 16" }
        XCTAssertEqual(s, "Week of Nov 16. Last week too hard.")
        XCTAssertFalse(s.contains("Intent:"))
        XCTAssertFalse(s.contains("Notes:"))
    }

    func testSpokenIncludesIntentAndNotesVerbatim() {
        let row = CheckInHistoryRow(id: UUID(), weekStart: date(11, 16), intent: "Deload", rating: nil,
                                    notes: "worked: hills · didn't: sleep")
        let s = CheckInHistory.spoken(row) { _ in "Nov 16" }
        XCTAssertTrue(s.contains("worked: hills · didn't: sleep"))
        XCTAssertTrue(s.contains("Intent: Deload."))
    }
}
