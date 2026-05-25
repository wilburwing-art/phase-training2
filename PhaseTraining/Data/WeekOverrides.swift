// WeekOverrides.swift — per-week user inputs that shape the planner.
//
// Phase 11 moved availability + sport-day intent off TrainingMemory (which
// is long-term truth) and onto a per-week struct. The user sets these from
// the Week tab; a new week starts with a fresh empty WeekOverrides.
//
// Three pieces:
//   - unavailableDays: weekdays the user is OUT this week → forced rest
//   - events: WeekEvent[] anchored to specific dates → sport sessions, races,
//     anything that should pre-empt the planner's default kind for that day
//   - dayOverrides: per-date forced kind (rest / mobility / lift / sport).
//     Survives regeneration. Used by the Move-workout-to-another-day swap
//     and any future force-kind edits.
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

// MARK: - DayKindOverride
//
// User-forced kind for a specific date. Survives plan regeneration. The
// "Move workout to another day" swap writes two of these in one shot.
//
// .lift carries an optional routineId so a moved lift keeps its picked
// routine (otherwise the planner would re-pick deterministically and might
// land on a different one).

enum DayKindOverride: Codable, Hashable {
    case rest
    case lift(routineId: Int? = nil)
    case sport(sportSlug: String? = nil)

    var asKind: DayKind {
        switch self {
        case .rest:  return .rest
        case .lift:  return .lift
        case .sport: return .sport
        }
    }

    var routineId: Int? {
        switch self {
        case .lift(let id): return id
        case .rest, .sport: return nil
        }
    }

    var sportSlug: String? {
        if case .sport(let slug) = self { return slug }
        return nil
    }

    /// Map a currently-rendered DayPlan back into the override that would
    /// reproduce it. Used by the Move / drag-and-drop swap so a moved lift
    /// keeps its picked routine id, a moved sport keeps its sport, etc.
    /// Event days fall back to rest because events are date-anchored and
    /// shouldn't be swapped.
    static func from(plan: DayPlan) -> DayKindOverride {
        switch plan.kind {
        case .rest:  return .rest
        case .lift:  return .lift(routineId: plan.routineId)
        case .sport: return .sport(sportSlug: plan.sport?.slug)
        case .event: return .rest
        }
    }
}

// MARK: - WeekOverrides

struct WeekOverrides: Codable {
    /// Start-of-day Monday of the week this overrides applies to. PlanStore
    /// treats a stale weekStart as "no overrides" — Monday morning starts fresh.
    var weekStart: Date
    var unavailableDays: Set<Weekday> = []
    var events: [WeekEvent] = []
    var dayOverrides: [Date: DayKindOverride] = [:]
    /// Build 105: per-date CustomRoutine override. Date (startOfDay) →
    /// CustomRoutine.id. PlanStore applies these after Planner.generate()
    /// so the user's "use my saved leg workout for Thursday" pick survives
    /// regens + propagates to Today on the day-of.
    var customRoutineByDate: [Date: String] = [:]

    init(weekStart: Date) {
        self.weekStart = weekStart
    }
}

// MARK: - Convenience

extension WeekOverrides {
    /// True if the unavailableDays / events / dayOverrides / customRoutineByDate
    /// reference anything for `date`.
    func hasAnythingFor(date: Date, calendar: Calendar = .current) -> Bool {
        if unavailableDays.contains(Weekday.from(date: date, calendar: calendar)) {
            return true
        }
        if events.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return true
        }
        if dayOverrides.keys.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            return true
        }
        return customRoutineByDate.keys.contains(where: { calendar.isDate($0, inSameDayAs: date) })
    }

    /// CustomRoutine.id selected for `date`, if any.
    func customRoutineId(for date: Date, calendar: Calendar = .current) -> String? {
        for (k, v) in customRoutineByDate where calendar.isDate(k, inSameDayAs: date) {
            return v
        }
        return nil
    }

    /// All events landing on `date`. Usually 0 or 1; planner defends against >1
    /// by taking the first.
    func events(on date: Date, calendar: Calendar = .current) -> [WeekEvent] {
        events.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Day-kind override that lands on `date`, if any.
    func override(on date: Date, calendar: Calendar = .current) -> DayKindOverride? {
        for (k, v) in dayOverrides where calendar.isDate(k, inSameDayAs: date) {
            return v
        }
        return nil
    }

    /// Mutate to clear every per-date trace for `date` (events + override).
    /// unavailableDays is keyed by weekday so we don't touch it here — the
    /// caller decides whether to also clear that.
    mutating func clearDate(_ date: Date, calendar: Calendar = .current) {
        events.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
        let stale = dayOverrides.keys.filter { calendar.isDate($0, inSameDayAs: date) }
        for k in stale { dayOverrides.removeValue(forKey: k) }
        let staleCustom = customRoutineByDate.keys.filter { calendar.isDate($0, inSameDayAs: date) }
        for k in staleCustom { customRoutineByDate.removeValue(forKey: k) }
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
