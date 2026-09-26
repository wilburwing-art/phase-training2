// CalendarTravelDetectorTests.swift — B3 slice: travel days from the calendar.
//
// Each rule at its boundary, the non-travel shapes that must not count, the
// week clip, dedupe against the draft, and the generic "Travel" title that
// keeps calendar content out of the plan the coach can see.

import XCTest
@testable import PhaseTraining

final class CalendarTravelDetectorTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    /// Monday 2026-10-05, local midnight.
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func at(_ dayOffset: Int, _ hour: Int = 0) -> Date {
        cal.date(byAdding: .hour, value: dayOffset * 24 + hour, to: monday)!
    }
    private func ev(_ title: String, location: String? = nil, from: Date, to: Date, allDay: Bool = false) -> CalendarEventSnapshot {
        CalendarEventSnapshot(title: title, location: location, start: from, end: to, isAllDay: allDay)
    }
    private func days(_ events: [CalendarEventSnapshot]) -> [Int] {
        CalendarTravelDetector.travelDays(in: events, weekStart: monday, calendar: cal)
            .map { cal.dateComponents([.day], from: monday, to: $0.date).day! }
    }

    // MARK: - Stays

    func test_hotelStay_coversEachDayItTouches() {
        // Tue 15:00 to Thu 11:00: Tue, Wed, Thu.
        XCTAssertEqual(days([ev("Hilton Denver", from: at(1, 15), to: at(3, 11))]), [1, 2, 3],
                       "a 44-hour timed event is a trip even without a lodging word")
        XCTAssertEqual(days([ev("Hotel check-in", location: "Hilton Denver", from: at(1, 15), to: at(3, 11))]), [1, 2, 3])
        XCTAssertEqual(days([ev("Stay at Airbnb", from: at(1, 15), to: at(3, 11))]), [1, 2, 3])
    }

    func test_lodgingWordInLocation_counts() {
        XCTAssertEqual(days([ev("Trip", location: "Motel 6, Moab", from: at(4, 16), to: at(5, 10))]), [4, 5])
    }

    func test_sameDayMeetingNamedHotel_isNotAStay() {
        XCTAssertEqual(days([ev("Hotel sales review", from: at(2, 10), to: at(2, 11))]), [])
    }

    // MARK: - Multi-day all-day away

    func test_allDayWithLocation_countsFromTwoDays() {
        XCTAssertEqual(days([ev("Wedding", location: "Boise", from: at(2), to: at(3), allDay: true)]), [],
                       "a single all-day event with an address is not a trip")
        XCTAssertEqual(days([ev("Wedding weekend", location: "Boise", from: at(4), to: at(6), allDay: true)]), [4, 5])
    }

    func test_overnightShift_isNotATrip() {
        XCTAssertEqual(days([ev("Night shift", from: at(2, 19), to: at(3, 7))]), [])
    }

    func test_allDayWithoutLocation_neverCounts() {
        XCTAssertEqual(days([ev("Vacation", from: at(0), to: at(5), allDay: true)]), [])
    }

    // MARK: - Flights

    func test_flight_marksDepartureDay() {
        XCTAssertEqual(days([ev("UA 1234 SLC-DEN", from: at(1, 7), to: at(1, 9))]), [1])
        XCTAssertEqual(days([ev("DL123", from: at(3, 18), to: at(3, 21))]), [3])
        XCTAssertEqual(days([ev("Flight home", from: at(6, 12), to: at(6, 14))]), [6])
    }

    func test_numbersThatAreNotFlights_doNotCount() {
        XCTAssertEqual(days([ev("Q3 2026 planning", from: at(1, 9), to: at(1, 10))]), [])
        XCTAssertEqual(days([ev("Room 1204 standup", from: at(1, 9), to: at(1, 10))]), [])
        XCTAssertEqual(days([ev("Check in with Bob", from: at(1, 9), to: at(1, 10))]), [])
    }

    // MARK: - Week clip and dedupe

    func test_eventsOutsideTheWeek_areIgnored_andStaysAreClipped() {
        XCTAssertEqual(days([ev("UA 99", from: at(-2, 8), to: at(-2, 10))]), [])
        XCTAssertEqual(days([ev("Hotel", from: at(5, 15), to: at(9, 11))]), [5, 6])
        XCTAssertEqual(days([ev("Hotel", from: at(-3, 15), to: at(1, 11))]), [0, 1])
    }

    func test_events_skipDaysAlreadyInTheDraft_andUseTheGenericTitle() {
        let found = CalendarTravelDetector.travelDays(
            in: [ev("Stay at the Ritz", location: "Secret Client Offsite", from: at(1, 15), to: at(3, 11))],
            weekStart: monday, calendar: cal)
        let existing = [WeekEvent(date: at(2), title: "Climbing", kind: .sportSession)]
        let added = CalendarTravelDetector.events(for: found, existing: existing, calendar: cal)
        XCTAssertEqual(added.map { cal.dateComponents([.day], from: monday, to: $0.date).day! }, [1, 3])
        XCTAssertTrue(added.allSatisfy { $0.title == "Travel" && $0.kind == .outOfTown })
        XCTAssertFalse(added.contains { $0.title.contains("Ritz") || $0.title.contains("Offsite") })
    }

    // MARK: - Summary line

    func test_summary_readsRangesAndLists() {
        let e = { (d: Int) in WeekEvent(date: self.at(d), title: "Travel", kind: .outOfTown) }
        XCTAssertTrue(CheckInEventsScreen.summary(added: [e(1), e(2), e(3)], found: 3).hasPrefix("Added Tue to Thu"))
        XCTAssertTrue(CheckInEventsScreen.summary(added: [e(1), e(4)], found: 2).hasPrefix("Added Tue, Fri"))
        XCTAssertEqual(CheckInEventsScreen.summary(added: [], found: 0), "No travel found next week.")
        XCTAssertEqual(CheckInEventsScreen.summary(added: [], found: 2), "Travel days next week already have events.")
    }
}
