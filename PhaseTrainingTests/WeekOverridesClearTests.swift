// WeekOverridesClearTests.swift — characterization tests for the
// WeekOverrides convenience surface: clearDate(_:), hasAnythingFor(date:),
// and customRoutineId(for:).
//
// All dates are anchored to a fixed Monday (May 11, 2026) so the tests are
// deterministic across CI clocks. Matching is same-day (Calendar
// isDate(_:inSameDayAs:)), so keys stored at any time of day must behave
// like their startOfDay equivalents.

import XCTest
@testable import PhaseTraining

final class WeekOverridesClearTests: XCTestCase {

    private let cal = Calendar.current

    // MARK: - Fixtures

    /// Fixed-Monday anchor so dates are deterministic across CI clocks.
    private func mondayAnchor() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11   // Monday, May 11, 2026
        return cal.date(from: c)!
    }

    /// Day `offset` from the Monday anchor, optionally at a specific time.
    private func day(_ offset: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let base = cal.date(byAdding: .day, value: offset, to: mondayAnchor())!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    private func event(on date: Date, title: String = "Climb gym") -> WeekEvent {
        WeekEvent(date: date, title: title, kind: .sportSession, sport: nil)
    }

    private func freshOverrides() -> WeekOverrides {
        WeekOverrides(weekStart: mondayAnchor())
    }

    // MARK: - clearDate

    func test_clearDate_removesEventsForDate() {
        let tuesday = day(1)
        var o = freshOverrides()
        o.events = [event(on: tuesday)]

        o.clearDate(tuesday)

        XCTAssertTrue(o.events.isEmpty)
    }

    func test_clearDate_removesAllEventsOnSameDate() {
        let tuesday = day(1)
        var o = freshOverrides()
        o.events = [event(on: tuesday, title: "Morning climb"),
                    event(on: day(1, hour: 18), title: "Evening climb")]

        o.clearDate(tuesday)

        XCTAssertTrue(o.events.isEmpty, "both same-day events should be cleared")
    }

    func test_clearDate_removesDayOverrideForDate() {
        let wednesday = day(2)
        var o = freshOverrides()
        o.dayOverrides = [wednesday: .rest]

        o.clearDate(wednesday)

        XCTAssertTrue(o.dayOverrides.isEmpty)
    }

    func test_clearDate_removesCustomRoutineForDate() {
        let thursday = day(3)
        var o = freshOverrides()
        o.customRoutineByDate = [thursday: "leg-day-uuid"]

        o.clearDate(thursday)

        XCTAssertTrue(o.customRoutineByDate.isEmpty)
    }

    func test_clearDate_leavesOtherDatesUntouched() {
        let tuesday = day(1)
        let friday = day(4)
        var o = freshOverrides()
        o.events = [event(on: tuesday), event(on: friday, title: "Race")]
        o.dayOverrides = [tuesday: .rest, friday: .lift(routineId: 7, focus: .legs)]
        o.customRoutineByDate = [tuesday: "tue-routine", friday: "fri-routine"]
        o.weekTone = .recovery

        o.clearDate(tuesday)

        XCTAssertEqual(o.events.map(\.title), ["Race"])
        XCTAssertEqual(o.dayOverrides, [friday: .lift(routineId: 7, focus: .legs)])
        XCTAssertEqual(o.customRoutineByDate, [friday: "fri-routine"])
        XCTAssertEqual(o.weekTone, .recovery, "clearDate is per-date; week-level tone survives")
    }

    func test_clearDate_doesNotTouchUnavailableDays() {
        // Per the doc comment: unavailableDays is keyed by weekday, so
        // clearDate leaves it alone — the caller decides whether to clear it.
        let tuesday = day(1)
        var o = freshOverrides()
        o.unavailableDays = [.tuesday]
        o.dayOverrides = [tuesday: .rest]

        o.clearDate(tuesday)

        XCTAssertEqual(o.unavailableDays, [.tuesday])
        XCTAssertTrue(o.dayOverrides.isEmpty)
    }

    func test_clearDate_matchesKeysStoredAtAnyTimeOfDay() {
        // Keys stored mid-afternoon must be cleared by a startOfDay query
        // (and vice versa) because matching is same-day, not exact-instant.
        let wednesdayAfternoon = day(2, hour: 15, minute: 30)
        let wednesdayMidnight = day(2)
        var o = freshOverrides()
        o.dayOverrides = [wednesdayAfternoon: .sport(sportSlug: "climbing")]
        o.customRoutineByDate = [wednesdayMidnight: "wed-routine"]
        o.events = [event(on: wednesdayAfternoon)]

        o.clearDate(day(2, hour: 9, minute: 5))

        XCTAssertTrue(o.dayOverrides.isEmpty)
        XCTAssertTrue(o.customRoutineByDate.isEmpty)
        XCTAssertTrue(o.events.isEmpty)
    }

    func test_clearDate_noopWhenNothingStored() {
        var o = freshOverrides()
        o.clearDate(day(0))

        XCTAssertTrue(o.events.isEmpty)
        XCTAssertTrue(o.dayOverrides.isEmpty)
        XCTAssertTrue(o.customRoutineByDate.isEmpty)
        XCTAssertEqual(o.weekStart, mondayAnchor())
    }

    func test_clearDate_doesNotAffectAdjacentDays() {
        let tuesday = day(1)
        let monday = day(0)
        let wednesday = day(2)
        var o = freshOverrides()
        o.dayOverrides = [monday: .rest, tuesday: .rest, wednesday: .rest]

        o.clearDate(tuesday)

        XCTAssertEqual(Set(o.dayOverrides.keys), [monday, wednesday])
    }

    // MARK: - hasAnythingFor

    func test_hasAnythingFor_falseWhenClean() {
        let o = freshOverrides()
        for offset in 0..<7 {
            XCTAssertFalse(o.hasAnythingFor(date: day(offset)))
        }
    }

    func test_hasAnythingFor_trueForUnavailableWeekday() {
        var o = freshOverrides()
        o.unavailableDays = [.tuesday]

        XCTAssertTrue(o.hasAnythingFor(date: day(1)), "Tue is marked unavailable")
        XCTAssertFalse(o.hasAnythingFor(date: day(0)), "Mon is untouched")
    }

    func test_hasAnythingFor_trueForEvent() {
        var o = freshOverrides()
        o.events = [event(on: day(4))]

        XCTAssertTrue(o.hasAnythingFor(date: day(4)))
        XCTAssertFalse(o.hasAnythingFor(date: day(3)))
    }

    func test_hasAnythingFor_trueForDayOverride() {
        var o = freshOverrides()
        o.dayOverrides = [day(5): .lift(routineId: nil, focus: .push)]

        XCTAssertTrue(o.hasAnythingFor(date: day(5)))
        XCTAssertFalse(o.hasAnythingFor(date: day(6)))
    }

    func test_hasAnythingFor_trueForCustomRoutine() {
        var o = freshOverrides()
        o.customRoutineByDate = [day(3): "custom-id"]

        XCTAssertTrue(o.hasAnythingFor(date: day(3)))
        XCTAssertFalse(o.hasAnythingFor(date: day(2)))
    }

    func test_hasAnythingFor_normalizesTimeOfDay() {
        // Entry stored at 15:30; queries at startOfDay and 23:59 of the same
        // calendar day must both match.
        var o = freshOverrides()
        o.dayOverrides = [day(2, hour: 15, minute: 30): .rest]

        XCTAssertTrue(o.hasAnythingFor(date: day(2)))
        XCTAssertTrue(o.hasAnythingFor(date: day(2, hour: 23, minute: 59)))
        XCTAssertFalse(o.hasAnythingFor(date: day(1, hour: 23, minute: 59)),
                       "late Tuesday is still a different day than Wednesday")
    }

    func test_hasAnythingFor_falseAfterClearDate_whenNoWeekdayBlock() {
        let saturday = day(5)
        var o = freshOverrides()
        o.events = [event(on: saturday)]
        o.dayOverrides = [saturday: .rest]
        o.customRoutineByDate = [saturday: "sat-routine"]

        o.clearDate(saturday)

        XCTAssertFalse(o.hasAnythingFor(date: saturday))
    }

    // MARK: - customRoutineId(for:)

    func test_customRoutineId_returnsIdForMatchingDate() {
        var o = freshOverrides()
        o.customRoutineByDate = [day(3): "thu-legs"]

        XCTAssertEqual(o.customRoutineId(for: day(3)), "thu-legs")
    }

    func test_customRoutineId_nilWhenUnset() {
        let o = freshOverrides()
        XCTAssertNil(o.customRoutineId(for: day(0)))
    }

    func test_customRoutineId_nilForDifferentDay() {
        var o = freshOverrides()
        o.customRoutineByDate = [day(3): "thu-legs"]

        XCTAssertNil(o.customRoutineId(for: day(4)))
    }

    func test_customRoutineId_matchesAcrossTimeOfDay() {
        var o = freshOverrides()
        o.customRoutineByDate = [day(1, hour: 6): "tue-routine"]

        XCTAssertEqual(o.customRoutineId(for: day(1, hour: 21, minute: 45)), "tue-routine")
    }
}
