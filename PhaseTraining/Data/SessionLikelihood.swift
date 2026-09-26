// SessionLikelihood.swift — 3b of PLAN-next-gen.md: "will today happen?"
//
// The chance a planned lift or sport day actually gets trained, from what the
// app already logs: DayOutcome (planned days that happened), the missed log
// (planned days that did not), weekday skip streaks, calendar travel (already
// in the week as `.outOfTown` events), and, for today only, the time of day
// against the user's usual start.
//
// Kept simple enough to explain in one breath:
//   1. Pooled rate over the last 90 days, Beta(3, 1) prior, so no history reads
//      75% and a handful of days cannot swing it to 0 or 100.
//   2. This weekday's rate, shrunk toward the pooled rate by 4 pseudo-days.
//   3. Multiplied down for a skip streak on the weekday, a travel day, and
//      (today only) being well past the usual start time.
// Every step adds a plain-language reason.
//
// Pure and deterministic: every input, `now` and the calendar are passed in.
// Nothing reads this to move a session (standing rule: nothing auto-moves).
// It is context for the coach and an informational line in the check-in; it
// never lands on Today (`phase-training-tab-time-horizon-rule`).

import Foundation

struct SessionLikelihood: Equatable {
    /// Start of the day being estimated.
    var date: Date
    /// 0...1.
    var probability: Double
    /// The smoothed weekday rate before any adjustment.
    var weekdayRate: Double
    /// Planned days on this weekday, in the window, that happened / were missed.
    var weekdayHappened: Int
    var weekdayMissed: Int
    /// Planned days across every weekday in the window: the evidence the
    /// pooled prior rests on.
    var samples: Int
    /// Plain-language reasons, in the order they were applied.
    var reasons: [String]

    var percent: Int { Int((probability * 100).rounded()) }
}

enum SessionLikelihoodEngine {

    /// Matches the missed log's and DayOutcome's own 90-day retention.
    static let windowDays = 90
    /// Beta prior on the pooled rate: 3 happened, 1 missed, so 75% with no history.
    static let priorHappened = 3.0
    static let priorMissed = 1.0
    /// Pseudo-days pulling a weekday's rate toward the pooled rate.
    static let weekdayShrink = 4.0
    /// Multiplier on a weekday with a skip streak (SkipStreakDetector).
    static let streakFactor = 0.85
    /// Multiplier on a travel day (`.outOfTown` event).
    static let travelFactor = 0.7
    /// Session starts needed before "your usual start time" means anything.
    static let minStartsForUsualHour = 5
    /// Hours past the usual start before time of day starts to count, then the
    /// share lost per further hour, and the floor it cannot drop below.
    static let lateGraceHours = 1.0
    static let latePerHour = 0.12
    static let lateFloor = 0.25

    struct History {
        var outcomes: [DayOutcome]
        var missed: [MissedWorkoutEntry]
        /// `SavedSession.startTime` of logged sessions, any order.
        var sessionStarts: [Date]
    }

    /// Likelihood for one day. Nil unless the day plans a lift or sport session.
    static func estimate(date: Date,
                         dayKind: DayKind,
                         isTravel: Bool,
                         history: History,
                         now: Date,
                         calendar: Calendar = .current) -> SessionLikelihood? {
        guard dayKind == .lift || dayKind == .sport else { return nil }
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) ?? today
        let weekday = Weekday.from(date: day, calendar: calendar)

        // Already trained that day: nothing left to estimate.
        if history.sessionStarts.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            return SessionLikelihood(date: day, probability: 1, weekdayRate: 1,
                                     weekdayHappened: 0, weekdayMissed: 0, samples: 0,
                                     reasons: ["A session is already logged that day."])
        }

        // One sample per planned day in the window, before today. A day with
        // an outcome counts as happened even if the missed log also has it.
        var happened = Set<Date>()
        for o in history.outcomes where o.plannedDayKind == .lift || o.plannedDayKind == .sport {
            let d = calendar.startOfDay(for: o.date)
            if d >= windowStart && d < today { happened.insert(d) }
        }
        var missed = Set<Date>()
        for m in history.missed {
            let d = calendar.startOfDay(for: m.date)
            if d >= windowStart && d < today && !happened.contains(d) { missed.insert(d) }
        }

        let hAll = Double(happened.count), mAll = Double(missed.count)
        let pooled = (hAll + priorHappened) / (hAll + mAll + priorHappened + priorMissed)
        let h = happened.filter { Weekday.from(date: $0, calendar: calendar) == weekday }.count
        let m = missed.filter { Weekday.from(date: $0, calendar: calendar) == weekday }.count
        let weekdayRate = (Double(h) + weekdayShrink * pooled) / (Double(h + m) + weekdayShrink)

        var reasons: [String] = []
        if happened.isEmpty && missed.isEmpty {
            reasons.append("No planned days logged in the last \(windowDays) days yet, so this starts at \(pct(pooled)).")
        } else if h + m == 0 {
            reasons.append("No planned \(weekday.short) sessions in the last \(windowDays) days; using the overall \(happened.count) of \(happened.count + missed.count).")
        } else {
            reasons.append("\(h) of \(h + m) planned \(weekday.short) sessions happened in the last \(windowDays) days (\(happened.count) of \(happened.count + missed.count) overall).")
        }

        var p = weekdayRate
        let streaks = SkipStreakDetector.detect(missedWorkouts: history.missed, now: now, calendar: calendar)
        if let streak = streaks.first(where: { $0.weekday == weekday }) {
            p *= streakFactor
            reasons.append("\(weekday.short) has a skip streak: \(streak.missCount) missed in the last \(SkipStreakDetector.windowDays) days.")
        }
        if isTravel {
            p *= travelFactor
            reasons.append("Travel day: the plan has a bodyweight session.")
        }

        if day == today, let usual = usualStartHour(history.sessionStarts, now: now, calendar: calendar) {
            let parts = calendar.dateComponents([.hour, .minute], from: now)
            let nowHour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            let late = nowHour - usual
            if late > lateGraceHours {
                p *= max(lateFloor, 1 - latePerHour * (late - lateGraceHours))
                let hours = Int(late.rounded())
                reasons.append("Sessions usually start around \(clock(usual)); it is \(hours) hour\(hours == 1 ? "" : "s") past that.")
            } else if late < 0 {
                reasons.append("Still before the usual start time, around \(clock(usual)).")
            }
        }

        return SessionLikelihood(date: day, probability: min(1, max(0, p)), weekdayRate: weekdayRate,
                                 weekdayHappened: h, weekdayMissed: m,
                                 samples: happened.count + missed.count, reasons: reasons)
    }

    /// Likelihood for each lift or sport day of `plan`, in day order. Travel
    /// comes from `events` (the overrides the plan was built from, or the
    /// check-in draft's).
    static func week(plan: WeekPlan,
                     events: [WeekEvent],
                     history: History,
                     now: Date,
                     calendar: Calendar = .current) -> [SessionLikelihood] {
        plan.days.sorted { $0.date < $1.date }.compactMap { day -> SessionLikelihood? in
            let travel = events.contains { $0.kind == .outOfTown && calendar.isDate($0.date, inSameDayAs: day.date) }
            return estimate(date: day.date, dayKind: day.kind, isTravel: travel,
                            history: history, now: now, calendar: calendar)
        }
    }

    /// Median start hour (fractional, local) of sessions in the window, or nil
    /// with fewer than `minStartsForUsualHour` of them.
    static func usualStartHour(_ starts: [Date], now: Date, calendar: Calendar = .current) -> Double? {
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let hours = starts.filter { $0 >= windowStart && $0 <= now }.map { d -> Double in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }.sorted()
        guard hours.count >= minStartsForUsualHour else { return nil }
        let mid = hours.count / 2
        return hours.count % 2 == 1 ? hours[mid] : (hours[mid - 1] + hours[mid]) / 2
    }

    /// "7 AM", "12 PM", "6 PM": the hour nearest `hour`, no locale lookups so
    /// tests and the coach block read the same everywhere.
    static func clock(_ hour: Double) -> String {
        let h = Int(hour.rounded()) % 24
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(h < 12 ? "AM" : "PM")"
    }

    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

extension PlanStore {

    /// The engine's history from the stores PlanStore already holds.
    func sessionLikelihoodHistory() -> SessionLikelihoodEngine.History {
        SessionLikelihoodEngine.History(outcomes: dayOutcomes,
                                        missed: missedWorkouts,
                                        sessionStarts: sessionStore?.savedSessions.map(\.startTime) ?? [])
    }

    /// Today's likelihood on the current plan, or nil on a rest day or with no plan.
    func todaySessionLikelihood(now: Date = Date(), calendar: Calendar = .current) -> SessionLikelihood? {
        guard let day = plan?.today(now: now, calendar: calendar) else { return nil }
        let travel = overrides.events(on: day.date, calendar: calendar).contains { $0.kind == .outOfTown }
        return SessionLikelihoodEngine.estimate(date: day.date, dayKind: day.kind, isTravel: travel,
                                                history: sessionLikelihoodHistory(), now: now, calendar: calendar)
    }
}
