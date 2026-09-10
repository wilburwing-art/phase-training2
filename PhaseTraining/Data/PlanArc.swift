// PlanArc.swift — PR 10A of the weekly-coach roadmap: auto-arc periodization.
//
// The planner used to be week-by-week static: every regen was computed from
// the same inputs, so a user who trained hard for a month got four identical
// hard weeks. This module closes that loop. It reads the plan-history
// snapshots (PR 4) joined against saved sessions, classifies each past week
// as a build week or not, and when enough build weeks stack up, tells the
// planner to generate a deload week.
//
// Spec: PLAN-weekly-coach.md §6.1 — invisible to the user, no "Week 3 of 4"
// indicator. The deload expresses itself only through lighter prescriptions
// (fewer sets) and one demoted recovery day.
//
// Pure logic — no persistence, no PlanStore dependency. The caller
// (PlanStore+Generation) supplies snapshots + sessions and persists the
// last-deload marker so the cooldown survives restarts.

import Foundation

/// What the arc tracker tells the planner for the week being generated.
enum PlanArcSignal: Equatable {
    /// Train normally.
    case none
    /// Accumulated load crossed the threshold — generate a deload week.
    case deload
}

enum PlanArc {

    /// A week counts as a BUILD week when the user both showed up and did
    /// meaningful work. The bar is deliberately modest — the goal is to
    /// detect sustained load, not to punish an imperfect week:
    ///   - completion ratio ≥ 0.6 against planned lift+sport days
    ///   - at least 2 distinct completed training days
    /// (mirrors WeekPlanSnapshot.completionRatio's clamped 0...1.5 scale)
    static let buildWeekMinCompletion: Double = 0.6
    static let buildWeekMinSessions = 2

    /// 3 consecutive build weeks → deload. Spec §6.1.
    static let buildWeeksBeforeDeload = 3

    /// After a deload week, at least this many weeks must pass before
    /// another can fire. Prevents the arc from re-triggering on the
    /// first post-deload build week (a deloaded athlete rebounds fast,
    /// but 2 weeks of training between deloads is too little to matter).
    static let deloadCooldownWeeks = 4

    // MARK: - Week classification

    /// True when the week covered by `snapshot` was a build week.
    /// `sessions` is the full saved-session list; the snapshot joins it
    /// by its own recorded ids.
    static func isBuildWeek(_ snapshot: WeekPlanSnapshot,
                            sessions: [SavedSession],
                            calendar: Calendar = .current) -> Bool {
        let done = snapshot.completedSessionCount(in: sessions, calendar: calendar)
        guard done >= buildWeekMinSessions else { return false }
        return snapshot.completionRatio(in: sessions, calendar: calendar) >= buildWeekMinCompletion
    }

    /// Count consecutive build weeks ending at the most recent PAST week.
    ///
    /// Walks snapshots newest-first (any order input is normalized). The
    /// CURRENT week is excluded — an in-progress week shouldn't count
    /// toward the streak (a Monday regen on a fresh week would otherwise
    /// look like zero completion and break a real streak, or worse, count
    /// last Monday's partial data twice). The streak counts the weeks
    /// BEFORE the one being planned: 3 prior hard weeks means THIS week
    /// is the deload.
    ///
    /// A gap in snapshots (a week with no plan at all, e.g. the user
    /// didn't open the app) breaks the streak — absence of evidence is
    /// evidence of interruption.
    static func consecutiveBuildWeeks(snapshots: [WeekPlanSnapshot],
                                      sessions: [SavedSession],
                                      currentWeekStart: Date,
                                      calendar: Calendar = .current) -> Int {
        let mondayCal = calendar.mondayFirst
        let byWeek = Self.bestByWeek(snapshots)
        // Most recent snapshot strictly before the current week.
        var cursor = previousWeekStart(currentWeekStart, calendar: mondayCal)
        var streak = 0
        while let snap = byWeek[cursor] {
            guard isBuildWeek(snap, sessions: sessions, calendar: mondayCal) else { break }
            streak += 1
            cursor = previousWeekStart(cursor, calendar: mondayCal)
        }
        return streak
    }

    // MARK: - Decision

    /// The full decision: should the week starting `currentWeekStart`
    /// be a deload?
    ///
    /// Conditions, all of which must hold:
    ///   1. ≥ `buildWeeksBeforeDeload` consecutive build weeks precede it.
    ///   2. No deload within the last `deloadCooldownWeeks` weeks
    ///      (lastDeloadWeekStart persisted by the caller).
    ///   3. There IS enough history to judge — fewer than 2 past weeks of
    ///      snapshots means we don't know enough; never deload a new user.
    static func signal(snapshots: [WeekPlanSnapshot],
                       sessions: [SavedSession],
                       currentWeekStart: Date,
                       lastDeloadWeekStart: Date? = nil,
                       calendar: Calendar = .current) -> PlanArcSignal {
        let mondayCal = calendar.mondayFirst
        // Condition 3 — need at least the deload candidate + its 3 build
        // weeks... realistically: fewer than 3 snapshots can't produce a
        // 3-streak anyway, but state the guard so the intent is explicit.
        guard Self.bestByWeek(snapshots).count >= buildWeeksBeforeDeload else {
            return .none
        }
        // Condition 2 — cooldown.
        if let last = lastDeloadWeekStart {
            let weeksSince = mondayCal.dateComponents([.weekOfYear],
                from: mondayCal.startOfDay(for: last),
                to: mondayCal.startOfDay(for: currentWeekStart)).weekOfYear ?? 0
            guard weeksSince >= deloadCooldownWeeks else { return .none }
        }
        // Condition 1 — the streak.
        let streak = consecutiveBuildWeeks(snapshots: snapshots,
                                           sessions: sessions,
                                           currentWeekStart: currentWeekStart,
                                           calendar: mondayCal)
        return streak >= buildWeeksBeforeDeload ? .deload : .none
    }

    // MARK: - Helpers

    /// Dedupe snapshots by weekStart (latest capturedAt wins), keyed by
    /// weekStart normalized to start-of-day.
    static func bestByWeek(_ snapshots: [WeekPlanSnapshot]) -> [Date: WeekPlanSnapshot] {
        var out: [Date: WeekPlanSnapshot] = [:]
        for snap in snapshots {
            let key = Calendar.current.startOfDay(for: snap.weekStart)
            if let existing = out[key], existing.capturedAt >= snap.capturedAt { continue }
            out[key] = snap
        }
        return out
    }

    static func previousWeekStart(_ of: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: of))
            ?? calendar.startOfDay(for: of).addingTimeInterval(-7 * 86_400)
    }
}

extension Calendar {
    /// A Monday-first copy — the training-week convention used across
    /// PlanHistory / Planner. Callers pass `.current` freely.
    var mondayFirst: Calendar {
        var c = self
        c.firstWeekday = 2
        return c
    }
}
