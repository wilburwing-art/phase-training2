// MissedWorkoutEntry.swift — PR 8 of the weekly-coach roadmap.
//
// One log entry per detected missed workout. Captured the morning after
// a planned lift/sport day passed without a matching SavedSession, with
// the day flagged as either reshuffled-to-another-date, dropped (drop-
// rule fired), or user-dismissed (banner dismiss tap).
//
// Persisted on PlanStore under `pt_missed_workouts`. Rolling 90-day
// window — entries older than that drop off so the coach context doesn't
// keep referencing a missed workout from 8 months ago.
//
// Spec: PLAN-weekly-coach.md §2.4, §3, §11.1.

import Foundation

/// What happened with the miss — either we successfully shifted it
/// somewhere, or we couldn't / chose not to, or the user manually
/// closed the banner.
enum MissResolution: Codable, Hashable {
    /// Autopilot found a target date and proposed/applied a move.
    /// The `Date` is the new home of the workout.
    case reshuffledTo(Date)
    /// Drop-rule fired (≥4 lift days/week → don't crowd) OR no valid
    /// target slot existed (every remaining day was already busy or
    /// user-locked). The workout is gone for this week.
    case dropped
    /// User saw the banner and tapped dismiss. Same effective behavior
    /// as `dropped` for plan state, but logged separately so the coach
    /// can tell "user chose to skip" from "autopilot couldn't fit it".
    case userDismissed
}

extension MissResolution {
    /// Short label for the coach context / debug surfaces.
    var summary: String {
        switch self {
        case .reshuffledTo(let date):
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return "moved to \(f.string(from: date))"
        case .dropped:        return "dropped"
        case .userDismissed:  return "dismissed by user"
        }
    }
}

struct MissedWorkoutEntry: Codable, Identifiable, Hashable {
    var id: UUID
    /// Start-of-day of the missed planned day.
    var date: Date
    var plannedKind: DayKind
    /// Title the user would have seen (e.g. "Push day"). Nullable
    /// because some plans don't carry titles on every day.
    var plannedTitle: String?
    var resolution: MissResolution
    var loggedAt: Date

    init(date: Date, plannedKind: DayKind, plannedTitle: String?,
         resolution: MissResolution, loggedAt: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.plannedKind = plannedKind
        self.plannedTitle = plannedTitle
        self.resolution = resolution
        self.loggedAt = loggedAt
    }
}
