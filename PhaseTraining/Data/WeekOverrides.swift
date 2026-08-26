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
    /// PR 5 (weekly-coach roadmap) — travel / away-from-gym days. Planner
    /// renders a bodyweight-only `.lift` DayPlan so the user still has a
    /// workout to follow without needing equipment.
    case outOfTown = "out_of_town"

    var label: String {
        switch self {
        case .sportSession: return "Sport session"
        case .race:         return "Race / event"
        case .outOfTown:    return "Travel"
        }
    }
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

// MARK: - LiftFocus
//
// PR 5 (weekly-coach roadmap) — user-facing focus vocabulary for a lift day.
// The painted strip in PR 6 lets the user tap "Push" / "Pull" / "Legs" /
// "Upper" / "Lower" / "Full body" for any planned lift day; that selection
// becomes a `LiftFocus` on the corresponding `DayKindOverride.lift`.
//
// We expose a separate enum from `WorkoutFocus` (the generator's internal
// shape vocabulary) so the user's intent stays user-facing — `WorkoutFocus`
// has `fullBodyA` / `fullBodyB` split for variety rotation, which is an
// internal concern. `LiftFocus.fullBody` maps to one of those at generation
// time.

enum LiftFocus: String, Codable, Hashable, CaseIterable {
    case push, pull, legs, upper, lower, fullBody = "full_body"

    /// Display label for the painted strip chip.
    var label: String {
        switch self {
        case .push:     return "Push"
        case .pull:     return "Pull"
        case .legs:     return "Legs"
        case .upper:    return "Upper"
        case .lower:    return "Lower"
        case .fullBody: return "Full body"
        }
    }

    /// Map to the generator's internal `WorkoutFocus`. `.fullBody` resolves
    /// to `.fullBodyA` by default — variety-rotation across multiple
    /// full-body days within a week is a planner concern, not a UI one.
    var asWorkoutFocus: WorkoutFocus {
        switch self {
        case .push:     return .push
        case .pull:     return .pull
        case .legs:     return .legs
        case .upper:    return .upper
        case .lower:    return .lower
        case .fullBody: return .fullBodyA
        }
    }
}

// MARK: - WeekTone
//
// PR 5 — the week-level intent dial. User picks once per week from the
// painted strip: "typical" (default, no adjustment), "recovery" (-15%
// volume, deload bias), "build" (+10% volume, push bias), "busy" (trim
// sessions aggressively to respect the time budget).

enum WeekTone: String, Codable, Hashable, CaseIterable {
    case typical, recovery, build, busy

    /// Display label for the painted strip context chip.
    var label: String {
        switch self {
        case .typical:  return "Typical"
        case .recovery: return "Recovery"
        case .build:    return "Build"
        case .busy:     return "Busy"
        }
    }

    /// Map to the generator's intensity dial. `.typical` is identity
    /// (`.normal`); `.recovery` deloads; `.build` pushes; `.busy` stays
    /// at `.normal` (the time-budget effect is handled by trimming
    /// `durationMinutes`, not by changing per-set intensity).
    var asIntensityBias: GeneratorStrategy.IntensityBias {
        switch self {
        case .typical, .busy: return .normal
        case .recovery:       return .deload
        case .build:          return .push
        }
    }

    /// Multiplier applied to the session's minute budget. `.busy` is the
    /// only tone that compresses time; other tones keep the user's declared
    /// session length intact and let `intensityBias` do the work.
    var durationMultiplier: Double {
        switch self {
        case .busy: return 0.7
        default:    return 1.0
        }
    }
}

// MARK: - DayKindOverride
//
// User-forced kind for a specific date. Survives plan regeneration. The
// "Move workout to another day" swap writes two of these in one shot.
//
// .lift carries an optional routineId so a moved lift keeps its picked
// routine (otherwise the planner would re-pick deterministically and might
// land on a different one).
//
// PR 5 added the optional `focus` associated value. Existing persisted
// payloads decode cleanly: Swift's synthesized enum codec uses
// `decodeIfPresent` for Optional associated values, so old JSON without
// the `focus` key resolves to `focus = nil`.

enum DayKindOverride: Codable, Hashable {
    case rest
    case lift(routineId: Int? = nil, focus: LiftFocus? = nil)
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
        case .lift(let id, _): return id
        case .rest, .sport:    return nil
        }
    }

    var sportSlug: String? {
        if case .sport(let slug) = self { return slug }
        return nil
    }

    /// PR 5 — user-selected focus for a lift day, if any. nil = let the
    /// planner pick from auto-rotation.
    var liftFocus: LiftFocus? {
        if case .lift(_, let focus) = self { return focus }
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
        case .lift:  return .lift(routineId: plan.routineId, focus: nil)
        case .sport: return .sport(sportSlug: plan.sport?.slug)
        case .event: return .rest
        }
    }
}

// MARK: - Prescription refresh

/// Per-date "refresh prescriptions" pick for a custom-routine override day.
/// Stored as INTENT — applyCustomRoutineOverrides re-derives the refreshed
/// workout deterministically on every generate(), so the refresh survives
/// plan regeneration the same way customRoutineByDate itself does.
/// Raw-string cases per repo Codable hygiene: never remove a case without
/// migration (a decode throw resets the whole week's overrides).
enum PrescriptionRefreshMode: String, Codable, Hashable {
    case fullRefresh = "full"          // new sets, reps & weights
    case weightsOnly = "weights_only"  // recompute target notes only
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
    /// PR 5 (weekly-coach roadmap) — week-level intent dial. nil = typical
    /// (no adjustment). Optional + decoded with decodeIfPresent so existing
    /// persisted payloads decode unchanged.
    var weekTone: WeekTone?
    /// Per-date prescription refresh on a custom-routine override day.
    /// Date (startOfDay) → mode. MUST stay Optional (weekTone pattern):
    /// synthesized Codable throws keyNotFound for a non-optional field
    /// missing from an old payload, nuking the whole week's overrides via
    /// the try? decode in PlanStore.
    var prescriptionRefreshByDate: [Date: PrescriptionRefreshMode]?

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

    /// Prescription-refresh mode selected for `date`, if any.
    func prescriptionRefreshMode(for date: Date, calendar: Calendar = .current) -> PrescriptionRefreshMode? {
        for (k, v) in prescriptionRefreshByDate ?? [:] where calendar.isDate(k, inSameDayAs: date) {
            return v
        }
        return nil
    }

    /// Set (or clear, with nil) the prescription-refresh mode for `date`.
    /// Same-day keys are removed first so time-of-day never duplicates.
    mutating func setPrescriptionRefresh(_ mode: PrescriptionRefreshMode?,
                                         for date: Date,
                                         calendar: Calendar = .current) {
        var map = prescriptionRefreshByDate ?? [:]
        for k in map.keys where calendar.isDate(k, inSameDayAs: date) {
            map.removeValue(forKey: k)
        }
        if let mode {
            map[calendar.startOfDay(for: date)] = mode
        }
        prescriptionRefreshByDate = map.isEmpty ? nil : map
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
        // A prescription refresh is meaningless without its custom override —
        // it clears with the day.
        setPrescriptionRefresh(nil, for: date, calendar: calendar)
    }
}

// MARK: - Week anchoring

/// The app's single `yyyy-MM-dd` day-key formatter.
///
/// Six separate copies existed (WeekScreen, CheckInEventsScreen, CoachTools,
/// CoachDrawer, CoachConversationStore, MiniWorkoutDiffCard) and NONE of them
/// pinned a locale. `yyyy` is the *calendar-relative* year, so on a device set
/// to a Japanese, Buddhist or ROC calendar `df.date(from: "2026-08-25")`
/// resolves to a different era-year: the coach's plan-edit matching found no
/// day and every proposal degraded to "Couldn't match the proposed ops to your
/// current plan", and the conversation store's day bucket keyed wrong so the
/// midnight rollover misfired.
///
/// `en_US_POSIX` + an explicit Gregorian calendar makes the format mean what
/// the string says regardless of device settings. Machine-readable day keys
/// must never use a user-locale formatter.
enum DayKeyFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func string(from date: Date) -> String { iso.string(from: date) }
    static func date(from key: String) -> Date? { iso.date(from: key) }
}

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
