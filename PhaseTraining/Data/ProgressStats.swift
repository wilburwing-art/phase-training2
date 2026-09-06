// ProgressStats.swift — render-time stat-strip math for the Progress tab.
//
// These three helpers were private methods on the ProgressScreen extension
// in Screens/Progress/ProgressScreen+StatCards.swift. They stayed at render
// time (rather than moving into ProgressAggregates with the rest of the
// session walks) because they mix cached data with inputs that are NOT part
// of the aggregates cache key: the current date and the weekly lift target.
//
// That is exactly why they live here now. As private View methods calling
// `Date()` inline they were untestable — any assertion would have had to be
// written relative to the real clock and would flake whenever the suite ran
// across a Monday-midnight boundary. `now` is a parameter here, so
// ProgressStatStripTests can pin a week grid and assert the edges.
//
// Pure value math, no store access: same inputs in → same numbers out. The
// card call sites in +StatCards.swift are thin wrappers that supply
// `Date()`.

import Foundation

enum ProgressStats {

    /// Sessions logged in the current week.
    ///
    /// Sums the `byWeek` grouping over keys at or after this week's start
    /// rather than re-filtering `savedSessions` — `startOfWeek(d) >=
    /// thisWeekStart ⟺ d >= thisWeekStart`, so the two count exactly the
    /// same sessions. Weeks after the current one (a future-dated session)
    /// are included, matching the old `startTime >= weekStart` filter.
    static func sessionsThisWeekCount(byWeek: [Date: Int],
                                      now: Date,
                                      calendar: Calendar = .current) -> Int {
        let weekStart = ProgressAggregates.startOfWeek(for: now, calendar: calendar)
        return byWeek.reduce(0) { $0 + ($1.key >= weekStart ? $1.value : 0) }
    }

    /// Consecutive weeks (ending with the most recent week that has any
    /// session) where the session count met `target`. Returns 0 when the
    /// most recent qualifying week is older than this-week-or-last-week, or
    /// when target was never met.
    ///
    /// Two behaviors worth keeping in mind when reading the assertions:
    ///
    /// - **Grace week.** A week still in progress is usually short of
    ///   target, so an unmet current week does not end the streak: the
    ///   cursor drops to last week and counts from there. The current week
    ///   is only counted when it has already met target.
    /// - **Bounded cursor.** The walk stops at the oldest week present in
    ///   `byWeek`. The original loop advanced with `?? cursor`, so a nil
    ///   from date arithmetic pinned the cursor while the target check
    ///   stayed true — an infinite loop on the main thread, inside a body
    ///   evaluation. The bound is load-bearing, not defensive.
    static func currentWeeklyTargetStreak(target: Int,
                                          byWeek: [Date: Int],
                                          now: Date,
                                          calendar: Calendar = .current) -> Int {
        let thisWeekStart = ProgressAggregates.startOfWeek(for: now, calendar: calendar)

        var streak = 0
        var cursor = thisWeekStart
        if (byWeek[cursor] ?? 0) < target {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        let oldestWeek = byWeek.keys.min() ?? cursor
        while (byWeek[cursor] ?? 0) >= target, cursor >= oldestWeek {
            streak += 1
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// PR events landed within the last `days` days — the "PRs · 30d" cell.
    /// Inclusive at the cutoff instant.
    static func prsInLastDays(_ days: Int,
                              in records: [PersonalRecord],
                              now: Date,
                              calendar: Calendar = .current) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        return records.filter { $0.date >= cutoff }.count
    }
}

// MARK: - Strength-ratios disclosure

extension ProgressStats {

    /// The line under the strength-ratios card's tier labels.
    ///
    /// Tiers render as bare authoritative words ("ELITE") off thresholds
    /// StrengthStandards.swift itself calls "a directional signal, not a
    /// diagnosis", so the card says that where the user reads them. The
    /// `.nonbinary` / `.preferNotToSay` variant additionally names the curve
    /// those cases are routed to, because silently scoring someone against an
    /// unnamed curve while telling them gender is what unlocks the label is
    /// the failure this copy exists to prevent.
    ///
    /// Lives here, not in the View extension, so a test can assert the copy
    /// against `StrengthStandards.curve(for:)` — the routing it describes.
    static func strengthTierDisclosure(gender: Gender?) -> String {
        let base = "Tiers are a rough directional signal, not a diagnosis."
        switch gender {
        case .none:
            return base + " Add your gender on Profile to see them."
        case .male, .female:
            return base
        case .nonbinary, .preferNotToSay:
            return base + " Published standards only come in two curves, so these use the female thresholds."
        }
    }
}
