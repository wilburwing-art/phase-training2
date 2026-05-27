// PlanHistory.swift — historical plan snapshots.
//
// PR 4 of the weekly-coach roadmap (`PLAN-weekly-coach-roadmap.md`).
// This is the foundation layer every later PR reads from: painted-strip
// "actual vs planned" rendering, rules-engine pattern detection ("you've
// skipped Tuesday's lift 3 weeks in a row"), missed-workout autopilot,
// progress-tab visualizations, and the coach's long-horizon context
// summary all source from `WeekPlanSnapshot`.
//
// The snapshot itself is intentionally thin — `weekStart` is the dedup key,
// `plan` is the full WeekPlan as the user saw it that week, and
// `actualSessions` is a list of `SavedSession.id` values (timeIntervals)
// to be joined at query time against SessionStore. We don't denormalize
// session details into the snapshot because sessions outlive plans (a
// session logged 8 weeks ago should still be queryable; the plan for that
// week eventually rolls off the 12-week cap).
//
// Spec reference: PLAN-weekly-coach.md §11.1.

import Foundation

/// One week's plan as captured at the time it became active. Joined against
/// `SessionStore` at query time to compute "actual shape" — what the user
/// actually completed vs. what was planned.
struct WeekPlanSnapshot: Codable, Hashable, Identifiable {
    /// Monday of the week this snapshot covers (start-of-day).
    /// Doubles as the dedup key — `PlanStore` keeps at most one snapshot
    /// per `weekStart`, replacing on subsequent captures so the most
    /// recent edit of the week is what the history shows.
    let weekStart: Date

    /// The full WeekPlan as the user saw it. We keep the whole plan rather
    /// than just metadata so the painted-strip surface can render the
    /// exact day-by-day shape from history without re-running the planner.
    let plan: WeekPlan

    /// `SavedSession.id` values logged during this week's window. Joined
    /// at read time — `SessionStore.savedSessions` is the source of truth
    /// for the session details themselves. Storing IDs (not copies) keeps
    /// the snapshot small + avoids divergence when the user edits a saved
    /// session post-hoc.
    let actualSessionIDs: [TimeInterval]

    /// When we snapshotted. Used to disambiguate multiple captures of the
    /// same week if we ever surface them (mid-week edit history) and to
    /// drive the rolling 12-week cap (sort by `weekStart` desc, take 12).
    let capturedAt: Date

    /// Stable id for SwiftUI iteration — weekStart already uniquely
    /// identifies a snapshot under the dedup invariant.
    var id: Date { weekStart }
}

extension WeekPlanSnapshot {
    /// Number of lift days the plan called for that week.
    var plannedLiftDays: Int {
        plan.days.filter { $0.kind == .lift }.count
    }

    /// Number of sport days the plan called for.
    var plannedSportDays: Int {
        plan.days.filter { $0.kind == .sport }.count
    }

    /// Number of distinct calendar days within this week that have an
    /// associated session id. Doesn't validate session details — a
    /// 5-minute "warmup" session counts toward "did something". The
    /// coarseness is intentional; finer rules (volume, RPE) live in PR 7.
    func completedSessionCount(in sessions: [SavedSession],
                               calendar: Calendar = .current) -> Int {
        let idSet = Set(actualSessionIDs)
        // Use start-of-day on the session date so two sessions on the
        // same calendar day collapse to one "completed day" — protects
        // against double-counting if the user splits a workout.
        var doneDays = Set<Date>()
        for s in sessions where idSet.contains(s.id) {
            doneDays.insert(calendar.startOfDay(for: s.startTime))
        }
        return doneDays.count
    }

    /// Completion ratio against the week's planned workout days
    /// (lift + sport). 0.0 if no workouts were planned (rest week);
    /// clamped to [0, 1.5] so an over-shoot week reads as ">100%" rather
    /// than capping at 1.0 and hiding the signal.
    func completionRatio(in sessions: [SavedSession],
                         calendar: Calendar = .current) -> Double {
        let planned = plannedLiftDays + plannedSportDays
        guard planned > 0 else { return 0 }
        let done = completedSessionCount(in: sessions, calendar: calendar)
        let ratio = Double(done) / Double(planned)
        return min(max(ratio, 0), 1.5)
    }

    /// Sessions logged in this week's calendar window, ordered by date.
    /// Used by `shape(forWeek:)` consumers that need full session details
    /// rather than just counts.
    func sessions(from store: [SavedSession]) -> [SavedSession] {
        let idSet = Set(actualSessionIDs)
        return store
            .filter { idSet.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }
    }
}

extension WeekPlanSnapshot {
    /// Trim a snapshot list to the most recent `limit` weeks. Sorted
    /// newest-first so callers can iterate naturally and the rolling cap
    /// drops the oldest entries. Removes dupes by `weekStart` (latest
    /// `capturedAt` wins) before capping.
    static func trim(_ snapshots: [WeekPlanSnapshot], limit: Int = 12) -> [WeekPlanSnapshot] {
        var bestByWeek: [Date: WeekPlanSnapshot] = [:]
        for snap in snapshots {
            if let existing = bestByWeek[snap.weekStart],
               existing.capturedAt >= snap.capturedAt {
                continue
            }
            bestByWeek[snap.weekStart] = snap
        }
        return bestByWeek.values
            .sorted { $0.weekStart > $1.weekStart }
            .prefix(limit)
            .map { $0 }
    }

    /// Capture a snapshot of the given plan + the sessions whose dates
    /// fall in the plan's week window. Pure — caller persists.
    static func capture(_ plan: WeekPlan,
                        sessions: [SavedSession],
                        now: Date = Date(),
                        calendar: Calendar = .current) -> WeekPlanSnapshot {
        let weekStart = (plan.days.first?.date ?? now).startOfTrainingWeek(calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let inWindow = sessions.filter { s in
            s.startTime >= weekStart && s.startTime < weekEnd
        }
        return WeekPlanSnapshot(
            weekStart: weekStart,
            plan: plan,
            actualSessionIDs: inWindow.map(\.id),
            capturedAt: now
        )
    }
}

/// "Actual shape" of a historical week — what the user can read off the
/// painted strip / Progress tab. Combines a snapshot (planned) with the
/// resolved sessions (actual). Computed lazily by `PlanStore.shape(forWeek:)`
/// rather than persisted, because session details change as the user edits
/// saved sessions; the source of truth stays the snapshot + session store.
struct WeekShape: Hashable {
    let weekStart: Date
    let plannedLiftDays: Int
    let plannedSportDays: Int
    let completedLiftDays: Int
    let completedSportDays: Int
    let completionRatio: Double
    /// Days the plan called for a workout but no session was logged.
    let missedDates: [Date]

    init(snapshot: WeekPlanSnapshot,
         sessions: [SavedSession],
         calendar: Calendar = .current) {
        self.weekStart = snapshot.weekStart
        self.plannedLiftDays = snapshot.plannedLiftDays
        self.plannedSportDays = snapshot.plannedSportDays
        self.completionRatio = snapshot.completionRatio(in: sessions, calendar: calendar)

        // Per-kind completion: for each planned workout day, did the user
        // log a session that calendar day? Lift vs sport is bucketed by
        // looking at the plan's day kind, not the session's category —
        // a user who did sport on a planned lift day still counts as
        // "completed a workout that day" but bucketed under the planned kind.
        let resolved = snapshot.sessions(from: sessions)
        let doneDays: Set<Date> = Set(resolved.map { calendar.startOfDay(for: $0.startTime) })

        var liftDone = 0
        var sportDone = 0
        var missed: [Date] = []
        for day in snapshot.plan.days where day.kind.isWorkout || day.kind == .sport {
            let d = calendar.startOfDay(for: day.date)
            if doneDays.contains(d) {
                switch day.kind {
                case .lift:  liftDone += 1
                case .sport: sportDone += 1
                default:     break
                }
            } else if d <= calendar.startOfDay(for: Date()) {
                missed.append(d)
            }
        }
        self.completedLiftDays = liftDone
        self.completedSportDays = sportDone
        self.missedDates = missed
    }
}
