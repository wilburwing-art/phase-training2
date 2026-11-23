// PastWeeksSummary.swift — planned versus done for completed weeks.
//
// Feeds the Progress "PLANNED / DONE" card. `completedSessionCount`
// joins sessions by the week's date window, so a week snapshotted on
// Monday still counts the sessions logged later that week.

import Foundation

struct PastWeekRow: Hashable, Identifiable {
    let weekStart: Date
    /// plannedLiftDays + plannedSportDays.
    let planned: Int
    /// Distinct calendar days with a session in the week window.
    let done: Int

    var id: Date { weekStart }

    /// done / planned clamped to 0...1.5; 0 when nothing was planned.
    var ratio: Double {
        guard planned > 0 else { return 0 }
        return min(max(Double(done) / Double(planned), 0), 1.5)
    }
}

enum PastWeeksSummary {
    /// Completed weeks only (weekStart before today's training week), oldest
    /// first, at most `limit`, keeping the newest when there are more.
    static func rows(snapshots: [WeekPlanSnapshot],
                     sessions: [SavedSession],
                     today: Date = Date(),
                     calendar: Calendar = .current,
                     limit: Int = 8) -> [PastWeekRow] {
        let thisWeek = today.startOfTrainingWeek(calendar: calendar)
        let past = snapshots
            .filter { $0.weekStart < thisWeek }
            .sorted { $0.weekStart < $1.weekStart }
            .suffix(max(limit, 0))
        return past.map { snap in
            PastWeekRow(
                weekStart: snap.weekStart,
                planned: snap.plannedLiftDays + snap.plannedSportDays,
                done: snap.completedSessionCount(in: sessions, calendar: calendar)
            )
        }
    }

    /// One VoiceOver sentence naming every week.
    static func spoken(_ rows: [PastWeekRow]) -> String {
        guard !rows.isEmpty else { return "" }
        let head = rows.count == 1 ? "1 week." : "\(rows.count) weeks."
        let parts = rows.map { row -> String in
            let date = row.weekStart.formatted(.dateTime.month(.abbreviated).day())
            if row.planned == 0 { return "Week of \(date): rest week." }
            return "Week of \(date): \(row.done) of \(row.planned) done."
        }
        return ([head] + parts).joined(separator: " ")
    }
}
