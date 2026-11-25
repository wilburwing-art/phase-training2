// HistoryEntries.swift: the History list as sessions plus imported workouts.
//
// Imported workouts (Health, CSV cardio) carry no sets, so they stay out of
// `SessionStore.displaySessions`, which also feeds Progress and PR
// detection. History merges them in here as read-only rows.
//
// A strength app that exports CSV (Fitbod, Strong) also writes the same
// workout to Health, so a Health strength workout that starts within
// `duplicateWindow` of a CSV set-import session is the same workout and
// is dropped (backlog 2026-11c 6.12).

import Foundation

enum HistoryEntry: Identifiable, Equatable {
    case session(SavedSession)
    case workout(ImportedWorkout)

    var id: String {
        switch self {
        case .session(let s): return "session-\(s.id)"
        case .workout(let w): return "workout-\(w.id)"
        }
    }

    var date: Date {
        switch self {
        case .session(let s): return s.startTime
        case .workout(let w): return w.startTime
        }
    }
}

enum HistoryEntries {
    /// A Health strength workout this close to a set-import session's start
    /// is the same workout.
    static let duplicateWindow: TimeInterval = 2 * 3_600

    /// Newest first. Sessions keep their order on a tied start time.
    static func merge(sessions: [SavedSession], workouts: [ImportedWorkout]) -> [HistoryEntry] {
        let setImportStarts = sessions
            .filter { $0.importSource.map { $0 != .healthKit } ?? false }
            .map(\.startTime)
        let kept = workouts.filter { w in
            guard w.source == .healthKit, w.kind == .strength else { return true }
            return !setImportStarts.contains { abs($0.timeIntervalSince(w.startTime)) <= duplicateWindow }
        }
        let entries = sessions.map(HistoryEntry.session) + kept.map(HistoryEntry.workout)
        return entries.enumerated()
            .sorted { a, b in
                a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Row title for an imported workout: "Apple Health workout".
    static func title(_ w: ImportedWorkout) -> String {
        "\(ImportedHistorySessions.sourceName(w.source)) workout"
    }
}
