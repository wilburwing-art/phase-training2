// SkipStreakDetector.swift — PR 10D of the weekly-coach roadmap:
// skip-streak detection + chat surface.
//
// A user who has missed Tuesday's lift 3 weeks running isn't lazy —
// Tuesday doesn't work for them. The planner used to keep prescribing
// Tuesday lifts forever; the coach never mentioned the pattern because
// nothing computed it.
//
// This detector reads the missed-workout log (PR 8) and reports weekdays
// whose misses have stacked up. The caller (Planner.generate) softens
// the rotation on those days; the coach context surfaces the pattern so
// the chat can ask "want me to drop Thursday from rotation?".
//
// Pure logic — no persistence. The PlanStore-owned missedWorkouts log
// (rolling 90-day window) is the input.
//
// Spec: PLAN-weekly-coach.md §6.4.

import Foundation

enum SkipStreakDetector {

    /// Misses on the same weekday needed to call it a streak.
    static let streakThreshold = 3

    /// Rolling window the detector examines. Matches the missed-workout
    /// log's own retention (90 days) — misses older than the log simply
    /// aren't there.
    static let windowDays = 90

    /// One detected streak: the weekday, how many recent misses landed
    /// on it, and what kind of workout they were.
    struct Streak: Equatable {
        let weekday: Weekday
        let missCount: Int
        /// Titles of the missed workouts, newest-first (for the chat
        /// surface to name the pattern concretely).
        let missedTitles: [String]
    }

    /// Detect skip streaks from the missed-workout log.
    ///
    /// `missed` is the full MissedWorkoutEntry log (any order; sorted
    /// internally). Only misses within the window count. A weekday
    /// becomes a streak when ≥ `streakThreshold` misses landed on it.
    /// Entries the user later RESOLVED as completed-after-the-fact (see
    /// MissedWorkoutEntry.resolution) still count — the skip happened
    /// on the planned day either way; the reshuffle moved the work.
    static func detect(missedWorkouts: [MissedWorkoutEntry],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> [Streak] {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var perWeekday: [Weekday: [(date: Date, title: String?)]] = [:]
        for entry in missedWorkouts where entry.date >= cutoff {
            let weekday = Weekday.from(date: entry.date, calendar: calendar)
            perWeekday[weekday, default: []].append((entry.date, entry.plannedTitle))
        }
        return perWeekday
            .compactMap { weekday, misses -> Streak? in
                guard misses.count >= streakThreshold else { return nil }
                let sorted = misses.sorted { $0.date > $1.date }
                return Streak(
                    weekday: weekday,
                    missCount: misses.count,
                    missedTitles: sorted.compactMap(\.title)
                )
            }
            .sorted { $0.missCount > $1.missCount }
    }

    /// The weekday with the worst streak, for the planner's de-emphasis
    /// bias. nil when no streak exists.
    static func worstStreakWeekday(missedWorkouts: [MissedWorkoutEntry],
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> Weekday? {
        detect(missedWorkouts: missedWorkouts, now: now, calendar: calendar).first?.weekday
    }
}
