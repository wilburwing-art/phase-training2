// ActivityDetection.swift — on-open detection of sport activity the user
// did without telling the app.
//
// The use case: the user skis Saturday, climbs Tuesday after work, hikes a
// peak on a rest day — all recorded by their watch into Apple Health, none
// of it logged here. On the next app open we notice, confirm with the user
// ("Looks like you went skiing yesterday — want me to factor that in?"),
// and on confirm write a SportLogEntry plus (when the day is in the current
// plan week) a WeekEvent so the planner rebalances the remaining days
// around the real load.
//
// Read-only, same posture as the rest of the HK surface: this layer reuses
// HealthKitImporter's workout query and NEVER triggers the system auth
// dialog. If read access was never granted (or was denied), the query
// errors or returns nothing and the whole feature stays silent — auth
// continues to live behind Settings → Health & Imports, per the Phase 2
// lazy-auth rule documented in HealthKitImporter.swift.
//
// Detection is PURE (this enum): HKWorkoutLike[] + SportLogEntry[] +
// seen-ids in, DetectedActivity[] out. The store (ActivityDetectionStore)
// owns the async fetch + seen-id persistence; the Today banner owns the
// confirm/dismiss UX.

import Foundation
import HealthKit

/// One confirmable "you did a thing" candidate. A day's multiple HK
/// workouts of the same activity (ski runs recorded as separate workouts,
/// a climbing session split across gym visits) collapse into ONE candidate
/// with summed duration — the user confirms an outing, not a sample.
struct DetectedActivity: Identifiable, Equatable {
    /// The newest contributing HK workout UUID. Stable enough for
    /// Identifiable/banner identity; dedupe uses `workoutIds`.
    let id: String
    /// Every HK workout UUID that contributed to this candidate. All are
    /// marked seen on confirm OR dismiss so the same outing never
    /// re-prompts.
    let workoutIds: [String]
    /// App-catalog sport this maps to (alpine-skiing, climbing, ...).
    let sport: Sport
    /// Display name for the banner copy ("Skiing", "Climbing").
    let activityLabel: String
    /// Earliest contributing workout's start.
    let startTime: Date
    /// Summed duration across contributing workouts.
    let durationMinutes: Int
    /// Duration-derived guess the confirm writes to the sport log and the
    /// WeekEvent. ≥3 h reads as a full day out (hard), ≥90 min a real
    /// session (moderate), under that light.
    let suggestedIntensity: EventIntensity

    var day: Date { Calendar.current.startOfDay(for: startTime) }
}

/// What confirming a detected activity should do to the plan. Decided by
/// `ActivityDetector.confirmMode` from the plan + session history; the
/// Today glue executes it.
enum DetectedActivityConfirmMode: Equatable {
    /// Convert the outing's day to a sport day (WeekEvent) + regenerate,
    /// so adjacent lifts lighten and the week rebalances.
    case adjustWeek
    /// Sport log only — outside the current week, day already a sport
    /// day, or the user trained that day too (keep the lift record).
    case logOnly
    /// The outing is TODAY and today still has an un-trained planned
    /// lift. Whether to keep the lift or swap it for the sport is the
    /// user's call — surface a choice instead of deciding for them.
    case userChoice
}

enum ActivityDetector {

    /// How far back the on-open scan looks. Past 7 days the week is
    /// already regenerated around fresher data and a confirm's only value
    /// (a retroactive sport log) decays fast.
    static let windowDays = 7

    /// One HKWorkoutActivityType we consider notable, mapped to app
    /// vocabulary. `minMinutes` filters noise per activity — a 20-minute
    /// "skiing" workout is a lift lap, a 30-minute run is a jog not a
    /// load event.
    struct Mapping: Equatable {
        let label: String
        let sportSlug: String
        let minMinutes: Int
    }

    /// Curated outdoor / sport set. Strength + gym-cardio types are
    /// deliberately absent: the gym session is what the user logs natively
    /// in this app, so prompting "looks like you lifted" would double-count
    /// their own workout. Endurance types carry a higher floor so daily
    /// commutes and jogs don't prompt.
    static func mapping(for type: HKWorkoutActivityType) -> Mapping? {
        switch type {
        case .downhillSkiing:
            return Mapping(label: "Skiing", sportSlug: "alpine-skiing", minMinutes: 30)
        case .crossCountrySkiing:
            return Mapping(label: "Cross-country skiing", sportSlug: "snow-sports", minMinutes: 30)
        case .snowboarding:
            return Mapping(label: "Snowboarding", sportSlug: "snowboarding", minMinutes: 30)
        case .snowSports:
            return Mapping(label: "Snow sports", sportSlug: "snow-sports", minMinutes: 30)
        case .climbing:
            return Mapping(label: "Climbing", sportSlug: "climbing", minMinutes: 30)
        case .hiking:
            return Mapping(label: "Hiking", sportSlug: "hiking-trekking", minMinutes: 45)
        case .surfingSports:
            return Mapping(label: "Surfing", sportSlug: "surfing", minMinutes: 30)
        case .paddleSports:
            return Mapping(label: "Paddling", sportSlug: "paddle-sports", minMinutes: 45)
        case .cycling:
            return Mapping(label: "Riding", sportSlug: "cycling", minMinutes: 60)
        case .running:
            return Mapping(label: "Running", sportSlug: "running", minMinutes: 60)
        case .swimming:
            return Mapping(label: "Swimming", sportSlug: "swimming", minMinutes: 45)
        case .rowing:
            return Mapping(label: "Rowing", sportSlug: "rowing", minMinutes: 60)
        default:
            return nil
        }
    }

    /// Duration → intensity guess. Mirrors the sport-log vocabulary so the
    /// confirm writes straight through to SportLogEntry + WeekEvent.
    static func suggestedIntensity(durationMinutes: Int) -> EventIntensity {
        if durationMinutes >= 180 { return .hard }
        if durationMinutes >= 90 { return .moderate }
        return .light
    }

    /// Pure detection pass.
    ///
    /// Filters, in order:
    ///   1. window — only workouts starting within `windowDays` of `now`
    ///   2. seen — any workout UUID already confirmed/dismissed is out
    ///   3. type + duration — must map via `mapping(for:)` and clear its
    ///      per-activity minimum
    ///   4. already logged — a day with ANY SportLogEntry is out (the user
    ///      already told us; re-prompting would double-log)
    /// then collapses per (day, sport) and returns newest-day first.
    static func detect(
        workouts: [HKWorkoutLike],
        sportLogs: [SportLogEntry],
        seenIds: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DetectedActivity] {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let loggedDays = Set(sportLogs.map { calendar.startOfDay(for: $0.date) })

        struct Candidate {
            let uuid: String
            let mapping: Mapping
            let startTime: Date
            let minutes: Int
        }

        let candidates: [Candidate] = workouts.compactMap { hk in
            guard hk.startDate >= cutoff, hk.startDate <= now else { return nil }
            guard !seenIds.contains(hk.uuid.uuidString) else { return nil }
            guard let map = mapping(for: hk.activityType) else { return nil }
            guard !loggedDays.contains(calendar.startOfDay(for: hk.startDate)) else { return nil }
            return Candidate(
                uuid: hk.uuid.uuidString,
                mapping: map,
                startTime: hk.startDate,
                minutes: Int(hk.duration / 60)
            )
        }

        // Collapse per (day, sport). The per-activity duration floor
        // applies to the SUMMED outing, not each fragment — four
        // 20-minute ski runs are an 80-minute ski day.
        var grouped: [String: [Candidate]] = [:]
        for c in candidates {
            let key = DayKeyFormatter.string(from: c.startTime) + "|" + c.mapping.sportSlug
            grouped[key, default: []].append(c)
        }

        var out: [DetectedActivity] = []
        for (_, group) in grouped {
            let total = group.reduce(0) { $0 + $1.minutes }
            guard let map = group.first?.mapping, total >= map.minMinutes else { continue }
            let sorted = group.sorted { $0.startTime < $1.startTime }
            out.append(DetectedActivity(
                id: sorted.last!.uuid,
                workoutIds: sorted.map(\.uuid),
                sport: Sport.resolve(slug: map.sportSlug),
                activityLabel: map.label,
                startTime: sorted.first!.startTime,
                durationMinutes: total,
                suggestedIntensity: suggestedIntensity(durationMinutes: total)
            ))
        }

        // Newest outing first — the banner surfaces one at a time and the
        // most recent one matters most to this week's remaining days.
        return out.sorted { $0.startTime > $1.startTime }
    }

    /// Decide what a confirm does to the plan. Pure so the branching is
    /// testable; `completedSessionDays` is start-of-day dates of native
    /// SavedSessions (did the user lift that day too?).
    ///
    /// Rules, in order:
    ///   - outside the current training week → logOnly (WeekOverrides is
    ///     week-scoped; the sport log still feeds the next generation)
    ///   - day already planned as sport → logOnly (nothing to rebalance)
    ///   - lift day the user ALSO trained on → logOnly (they did both;
    ///     keep the lift day + its session record)
    ///   - TODAY with a pending (un-trained) lift → userChoice: the user
    ///     may well still want to lift on a ski day
    ///   - otherwise → adjustWeek (a past lift day they skied instead of,
    ///     or a rest day that was actually an outing)
    static func confirmMode(
        for activity: DetectedActivity,
        plan: WeekPlan?,
        completedSessionDays: Set<Date>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DetectedActivityConfirmMode {
        let day = activity.day
        guard calendar.isDate(day.startOfTrainingWeek(calendar: calendar),
                              inSameDayAs: now.startOfTrainingWeek(calendar: calendar)) else {
            return .logOnly
        }
        guard let planDay = plan?.days.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) else {
            // In-week but no plan (or the day isn't on it): record the
            // event; the planner honors it whenever the week generates.
            return .adjustWeek
        }
        if planDay.kind == .sport { return .logOnly }
        if planDay.kind == .lift {
            if completedSessionDays.contains(calendar.startOfDay(for: day)) { return .logOnly }
            if calendar.isDate(day, inSameDayAs: now) { return .userChoice }
        }
        return .adjustWeek
    }
}
