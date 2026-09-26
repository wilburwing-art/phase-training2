// CalendarTravelReader.swift — the only EventKit code in the app (B3 slice).
//
// Asks for calendar access on the user's tap and nowhere else, reads one week
// of events, and hands plain snapshots to CalendarTravelDetector. Nothing
// read here is stored or sent: the caller keeps only the resulting dates.
// iOS 17+ needs FULL access to read events; write-only cannot.

import EventKit
import Foundation

enum CalendarTravelResult: Equatable {
    case found([CalendarTravelDay])
    case denied
    case failed(String)
}

enum CalendarTravelReader {

    static func findTravel(weekStart: Date, calendar: Calendar = .current,
                           store: EKEventStore = EKEventStore()) async -> CalendarTravelResult {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            break
        case .notDetermined:
            do {
                guard try await store.requestFullAccessToEvents() else { return .denied }
            } catch {
                return .failed(error.localizedDescription)
            }
        default:
            // Denied, restricted, or write-only: none of them can read.
            return .denied
        }
        let start = calendar.startOfDay(for: weekStart)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return .found([]) }
        // Widen the window by two days each side so a stay that began before
        // the week, or a flight home that ends after it, is still seen.
        let from = calendar.date(byAdding: .day, value: -2, to: start) ?? start
        let to = calendar.date(byAdding: .day, value: 2, to: end) ?? end
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        let snapshots = store.events(matching: predicate).map {
            CalendarEventSnapshot(title: $0.title ?? "", location: $0.location,
                                  start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
        return .found(CalendarTravelDetector.travelDays(in: snapshots, weekStart: start, calendar: calendar))
    }
}
