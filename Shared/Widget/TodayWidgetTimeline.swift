// TodayWidgetTimeline.swift: which day the Today widget shows, what it says,
// and when its timeline turns over.
//
// The widget provider and views only forward to these, so the day pick
// ("Done", "No plan yet", midnight turnover) is testable from the app's test
// target. Foundation only, like TodayWidgetSnapshot.

import Foundation

enum TodayWidgetTimeline {
    /// The day shown at `date`. Nil renders "No plan yet": no snapshot, or the
    /// snapshot has no day on that calendar date.
    static func day(at date: Date, in snapshot: TodayWidgetSnapshot?,
                    calendar: Calendar = .current) -> TodayWidgetDay? {
        snapshot?.day(on: date, calendar: calendar)
    }

    /// Entry dates, ascending and unique: `now`, each later midnight the
    /// snapshot covers, and the midnight after its last day (the empty state).
    static func entryDates(now: Date, snapshot: TodayWidgetSnapshot?,
                           calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        if let snapshot {
            let starts = snapshot.days.map { calendar.startOfDay(for: $0.date) }
            dates += starts.filter { $0 > now }
            if let last = starts.max(),
               let after = calendar.date(byAdding: .day, value: 1, to: last), after > now {
                dates.append(after)
            }
        }
        return Set(dates).sorted()
    }
}

/// The two lines the widget renders for one entry.
struct TodayWidgetText: Equatable {
    static let emptyTitle = "No plan yet"
    static let emptyDetail = "Open Phase Training"
    static let doneDetail = "Done"

    var title: String
    var detail: String?
    /// The small family draws a checkmark beside `detail` when true.
    var done: Bool

    init(day: TodayWidgetDay?) {
        guard let day else {
            self.init(title: Self.emptyTitle, detail: Self.emptyDetail, done: false)
            return
        }
        self.init(title: day.title, detail: day.done ? Self.doneDetail : day.detail, done: day.done)
    }

    init(title: String, detail: String?, done: Bool) {
        self.title = title
        self.detail = detail
        self.done = done
    }
}
