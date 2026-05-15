// WeekOverrides.swift — per-week user inputs that shape the planner.
//
// Phase 11 moved availability + sport-day intent off TrainingMemory (which
// is long-term truth) and onto a per-week struct. The user sets these from
// the Week tab; a new week starts with a fresh empty WeekOverrides.
//
// Two pieces:
//   - unavailableDays: weekdays the user is OUT this week → forced rest
//   - events: WeekEvent[] anchored to specific dates → sport sessions, races,
//     anything that should pre-empt the planner's default kind for that day
//
// PlanStore persists the active WeekOverrides under `pt_week_overrides`. When
// `weekStart` no longer matches the current week's Monday-anchor, PlanStore
// returns a fresh empty WeekOverrides instead.

import Foundation

// MARK: - WeekEvent

enum WeekEventKind: String, Codable, CaseIterable {
    /// Recurring sport practice that you want planned this week (e.g.
    /// "climbing Monday & Wednesday"). Renders as a `.sport` DayPlan.
    case sportSession = "sport_session"
    /// A competition / race / performance day. Renders as a `.event` DayPlan.
    /// Hard-intensity races trigger pre-event taper.
    case race
}

enum EventIntensity: String, Codable, CaseIterable {
    case light, moderate, hard
    var label: String {
        switch self {
        case .light:    return "Light"
        case .moderate: return "Moderate"
        case .hard:     return "Hard"
        }
    }
}

struct WeekEvent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// Start-of-day for the event date (planner normalizes).
    var date: Date
    var title: String
    var kind: WeekEventKind
    var sport: Sport?
    var intensity: EventIntensity = .moderate
}

// MARK: - WeekOverrides

struct WeekOverrides: Codable {
    /// Start-of-day Monday of the week this overrides applies to. PlanStore
    /// treats a stale weekStart as "no overrides" — Monday morning starts fresh.
    var weekStart: Date
    var unavailableDays: Set<Weekday> = []
    var events: [WeekEvent] = []

    init(weekStart: Date) {
        self.weekStart = weekStart
    }
}

// MARK: - Convenience

extension WeekOverrides {
    /// True if the unavailableDays / events reference anything for `date`.
    func hasAnythingFor(date: Date, calendar: Calendar = .current) -> Bool {
        if unavailableDays.contains(Weekday.from(date: date, calendar: calendar)) {
            return true
        }
        return events.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// All events landing on `date`. Usually 0 or 1; planner defends against >1
    /// by taking the first.
    func events(on date: Date, calendar: Calendar = .current) -> [WeekEvent] {
        events.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

// MARK: - Week anchoring

extension Date {
    /// Monday of the ISO week containing this date, at start-of-day. Stable
    /// across timezones using the current Calendar's firstWeekday convention.
    func startOfTrainingWeek(calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2   // Monday — matches Weekday.monday convention
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? cal.startOfDay(for: self)
    }
}
