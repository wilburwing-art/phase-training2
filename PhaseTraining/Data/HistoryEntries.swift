// HistoryEntries.swift: the History list as sessions plus imported workouts.
//
// Imported workouts (Health, CSV cardio) carry no sets, so they stay out of
// `SessionStore.displaySessions`, which also feeds Progress and PR
// detection. History merges them in here as read-only rows.

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
    /// Newest first. Sessions keep their order on a tied start time.
    static func merge(sessions: [SavedSession], workouts: [ImportedWorkout]) -> [HistoryEntry] {
        let entries = sessions.map(HistoryEntry.session) + workouts.map(HistoryEntry.workout)
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
