// CalendarTravelDetector.swift — B3 slice of PLAN-predictive-recommendations.md.
//
// Finds travel days in next week's calendar so the weekly check-in can
// pre-fill `.outOfTown` WeekEvents, which the Planner already turns into a
// protected bodyweight session. Pure: EventKit stays in CalendarTravelReader,
// and tests feed CalendarEventSnapshot values.
//
// Conservative on purpose of cost: a false positive replaces a gym day with a
// bodyweight flow, so only three shapes count.
//   - a stay: title or location names lodging, and the event spans a night;
//   - an all-day event of 2+ days that carries a location, or a timed event
//     of 20+ hours that crosses a night (a 12-hour night shift does not);
//   - a flight: the title names a flight or carries a flight number.
// A meeting titled "Hotel sales review" at 10:00 is not a stay; neither is a
// single all-day event with an address.
//
// Output events are titled "Travel", never the calendar title or location:
// the week plan reaches the AI Coach when the coach is on, and calendar
// content must not ride along.

import Foundation

struct CalendarEventSnapshot: Equatable {
    var title: String
    var location: String?
    var start: Date
    var end: Date
    var isAllDay: Bool
}

enum CalendarTravelRule: String, Equatable {
    case stay, multiDayAway, flight
}

struct CalendarTravelDay: Equatable {
    /// Start of day.
    var date: Date
    var rule: CalendarTravelRule
}

enum CalendarTravelDetector {

    static let eventTitle = "Travel"

    /// No "check in": "Check in with Bob" is a meeting. The night-spanning
    /// requirement does the rest.
    static let stayWords = ["hotel", "airbnb", "vrbo", "lodging", "motel", "stay at"]
    static let flightWords = ["flight", "✈"]
    /// A timed event at least this long that crosses a night reads as a trip.
    static let minAwayHours: Double = 20

    /// Travel days inside `week` (Monday start of day, seven days), one per
    /// date, first matching rule wins in the order stay, multiDayAway, flight.
    static func travelDays(in events: [CalendarEventSnapshot], weekStart: Date,
                           calendar: Calendar = .current) -> [CalendarTravelDay] {
        let start = calendar.startOfDay(for: weekStart)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        var byDay: [Date: CalendarTravelRule] = [:]

        func mark(_ from: Date, _ to: Date, _ rule: CalendarTravelRule) {
            // Every calendar day the interval touches, clipped to the week.
            var d = calendar.startOfDay(for: max(from, start))
            let last = min(to, end)
            while d < last {
                if byDay[d] == nil { byDay[d] = rule }
                guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }

        for e in events where e.end > start && e.start < end {
            let text = (e.title + " " + (e.location ?? "")).lowercased()
            let nights = spannedNights(e, calendar: calendar)

            if nights >= 1, stayWords.contains(where: { text.contains($0) }) {
                // A stay covers the nights slept away plus the departure day.
                mark(e.start, e.end, .stay)
            } else if e.isAllDay, allDayLength(e, calendar: calendar) >= 2,
                      !(e.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                mark(e.start, e.end, .multiDayAway)
            } else if !e.isAllDay, nights >= 1, e.end.timeIntervalSince(e.start) >= minAwayHours * 3600 {
                // "Hilton Denver" Tue 15:00 to Thu 11:00 names no lodging word,
                // but nobody books a 44-hour meeting.
                mark(e.start, e.end, .multiDayAway)
            } else if isFlight(e.title) {
                let day = calendar.startOfDay(for: e.start)
                if let next = calendar.date(byAdding: .day, value: 1, to: day) { mark(day, next, .flight) }
            }
        }
        return byDay.map { CalendarTravelDay(date: $0.key, rule: $0.value) }.sorted { $0.date < $1.date }
    }

    /// `.outOfTown` WeekEvents for the travel days not already covered by any
    /// event in `existing`.
    static func events(for days: [CalendarTravelDay], existing: [WeekEvent],
                       calendar: Calendar = .current) -> [WeekEvent] {
        let taken = Set(existing.map { calendar.startOfDay(for: $0.date) })
        return days.filter { !taken.contains($0.date) }.map {
            WeekEvent(date: $0.date, title: eventTitle, kind: .outOfTown)
        }
    }

    // MARK: - Helpers

    /// Midnights crossed between start and end.
    static func spannedNights(_ e: CalendarEventSnapshot, calendar: Calendar) -> Int {
        let a = calendar.startOfDay(for: e.start)
        let b = calendar.startOfDay(for: e.end.addingTimeInterval(-1))
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Days an all-day event covers (EventKit ends all-day events at the next
    /// midnight, so a one-day event is 1).
    static func allDayLength(_ e: CalendarEventSnapshot, calendar: Calendar) -> Int {
        spannedNights(e, calendar: calendar) + 1
    }

    /// "Flight to Denver", "✈ SLC → DEN", or a two-letter carrier code plus a
    /// 2-4 digit number such as "UA 1234" / "DL123". Letter-only carrier codes
    /// on purpose: allowing a digit ("B6") also matches "Q3 2026 planning".
    static func isFlight(_ title: String) -> Bool {
        let lower = title.lowercased()
        if flightWords.contains(where: { lower.contains($0) }) { return true }
        return title.range(of: #"\b[A-Z]{2}\s?\d{2,4}\b"#, options: .regularExpression) != nil
    }
}
