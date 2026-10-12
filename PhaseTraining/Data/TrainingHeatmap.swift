// TrainingHeatmap.swift — month grid for the Progress tab's training heatmap.
//
// One cell per calendar day of a month, padded to whole weeks, each carrying
// the logged sessions that started that day and a 0-4 shade level from the
// day's total minutes. Minutes rather than session count (almost always 0 or
// 1 a day) or volume (zero for bodyweight work).
//
// Pure value math with `calendar` injected, so TrainingHeatmapTests can pin a
// month and a first weekday without reading the real clock.

import Foundation

enum TrainingHeatmap {

    struct Day: Equatable {
        let date: Date
        let sessions: [SavedSession]

        var minutes: Int { sessions.reduce(0) { $0 + max(0, $1.duration) / 60 } }
        var level: Int { TrainingHeatmap.level(minutes: minutes, sessionCount: sessions.count) }
    }

    /// Lower bound, in minutes, of shade levels 2, 3 and 4. Any session at
    /// all is level 1, so a day with a zero-duration session still shows.
    static let levelThresholds = [30, 60, 90]

    static func level(minutes: Int, sessionCount: Int) -> Int {
        guard sessionCount > 0 else { return 0 }
        return 1 + levelThresholds.filter { minutes >= $0 }.count
    }

    /// First instant of the month `offset` months from the one containing `now`.
    static func monthStart(offset: Int, now: Date, calendar: Calendar = .current) -> Date {
        let thisMonth = calendar.dateInterval(of: .month, for: now)!.start
        return calendar.date(byAdding: .month, value: offset, to: thisMonth)!
    }

    /// Rows of seven, starting on `calendar.firstWeekday`. Cells outside the
    /// month are nil. Sessions inside each day keep their input order.
    static func weeks(month: Date, sessions: [SavedSession],
                      calendar: Calendar = .current) -> [[Day?]] {
        let interval = calendar.dateInterval(of: .month, for: month)!
        let dayCount = calendar.range(of: .day, in: .month, for: interval.start)!.count

        var byDay: [Date: [SavedSession]] = [:]
        for s in sessions where interval.contains(s.startTime) {
            byDay[calendar.startOfDay(for: s.startTime), default: []].append(s)
        }

        let leading = (calendar.component(.weekday, from: interval.start)
                       - calendar.firstWeekday + 7) % 7
        var cells: [Day?] = Array(repeating: nil, count: leading)
        for i in 0..<dayCount {
            let date = calendar.date(byAdding: .day, value: i, to: interval.start)!
            cells.append(Day(date: date, sessions: byDay[date] ?? []))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Weekday initials in grid column order.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
