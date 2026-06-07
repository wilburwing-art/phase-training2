// ProgressAggregates.swift — memoized session aggregates for the Progress tab.
//
// Architecture item 8: every Progress card used to re-walk
// store.savedSessions per body evaluation — weeklyBuckets ran once per chart
// card, topExerciseSeries sorted + double-iterated, and
// StrengthStandards.rows (O(sessions × exercises × sets)) ran on every
// render. This layer computes all session-derived card inputs ONCE and
// reuses them until an input changes.
//
// ProgressAggregates is a pure value: same inputs in → same aggregates out.
// ProgressAggregatesCache is the memo — ProgressScreen owns one in @State
// and every card reads through it. The key is checked at READ time
// (sessions content + bodyweight + gender + calendar day), so a changed
// input can never serve stale data: finishing a workout reassigns
// savedSessions, the next render misses the key and recomputes. The
// calendar-day component covers the date-derived windows (weekly buckets,
// the muscle-volume 4-week cutoff) across midnight rollovers; week
// boundaries always fall on day boundaries, so the bucket math never goes
// stale mid-cache. StrengthStandards.rows and MuscleVolume.rows stay pure —
// only their OUTPUTS are memoized, here at the screen boundary (the item 8
// hazard note: no caching inside the Data/ math types themselves).

import Foundation

struct ProgressAggregates {

    // MARK: - Per-exercise series types
    //
    // Moved from ProgressScreen+ExerciseCards.swift: SparkPoint was
    // `ProgressScreen.SparkPoint` (internal — ProgressCharts.swift's
    // ExerciseSparkline renders it); ExerciseSeries was private to that file
    // and is internal here because the card now reads it cross-file.

    struct SparkPoint: Identifiable {
        let id = UUID()
        let date: Date
        let weight: Double
    }

    struct ExerciseSeries {
        let name: String
        let unit: String
        let points: [SparkPoint]
        let latest: Double
        let lastPRDate: Date?
    }

    // MARK: - Aggregates

    /// `store.savedSessions.count` — TOTAL cell on the stat strip.
    let totalSessions: Int
    /// Sessions per week, oldest at index 0 (`weeks` buckets) — sessions/wk
    /// bar chart.
    let sessionsPerWeek: [Int]
    /// Σ(weight × reps) of completed working sets per week — volume card.
    /// Warmup sets excluded — VOLUME / WEEK reflects working sets only.
    let weeklyVolume: [Double]
    /// Completed working-set count per week — the volume card's fallback
    /// series when no weights are logged.
    let weeklySetCounts: [Double]
    /// Session count grouped by Monday-based week start, ALL history (not
    /// just the chart window) — feeds the stat strip's this-week count and
    /// weekly-target streak, which stay render-time (they also depend on the
    /// current target, which is not part of the cache key).
    let sessionCountByWeekStart: [Date: Int]
    /// `SessionStore.allPersonalRecords()` output, newest first — PR feed,
    /// PRs·30d stat, per-exercise last-PR dates.
    let personalRecords: [PersonalRecord]
    /// `StrengthStandards.rows` output — strength-ratios card. Depends on
    /// bodyweightKg + gender, which are therefore part of the cache key.
    let strengthRows: [StrengthStandards.LiftRow]
    /// `MuscleVolume.rows` output — muscle-balance card.
    let muscleRows: [MuscleVolume.Row]
    /// Top exercises by completed-set count, each with its per-session
    /// best-weight series — per-exercise card.
    let topExercises: [ExerciseSeries]
    /// Newest `recentSessionsCount` sessions by end time — recent-sessions
    /// card.
    let recentSessions: [SavedSession]

    // MARK: - Computation

    init(sessions: [SavedSession],
         personalRecords: [PersonalRecord],
         bodyweightKg: Double?,
         gender: Gender?,
         weeks: Int,
         topExerciseCount: Int,
         recentSessionsCount: Int,
         now: Date = Date()) {
        let cal = Calendar.current
        let thisWeekStart = Self.startOfWeek(for: now, calendar: cal)

        // One fused pass replaces the per-card weeklyBuckets walks. Per
        // session: bucket index relative to this week, plus the byWeek
        // grouping the streak math reads. Contribution closures are verbatim
        // from the old sessionsCard / volumeCard call sites.
        var sessionsPerWeek = Array(repeating: 0, count: weeks)
        var weeklyVolume = Array(repeating: 0.0, count: weeks)
        var weeklySetCounts = Array(repeating: 0.0, count: weeks)
        var byWeek: [Date: Int] = [:]

        for session in sessions {
            let weekStart = Self.startOfWeek(for: session.startTime, calendar: cal)
            byWeek[weekStart, default: 0] += 1
            guard let weeksAgo = cal.dateComponents([.weekOfYear], from: weekStart, to: thisWeekStart).weekOfYear else { continue }
            let idx = weeks - 1 - weeksAgo
            guard idx >= 0, idx < weeks else { continue }
            sessionsPerWeek[idx] += 1
            // Warmup sets excluded — VOLUME / WEEK reflects working sets only.
            weeklyVolume[idx] += session.exercises.reduce(0.0) { acc, ex in
                acc + ex.sets.reduce(0.0) { a, set in
                    guard set.done, !set.isWarmup,
                          let w = set.weightValue,
                          let r = set.repsValue else { return a }
                    return a + (w * Double(r))
                }
            }
            weeklySetCounts[idx] += Double(session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && !$0.isWarmup }.count })
        }

        self.totalSessions = sessions.count
        self.sessionsPerWeek = sessionsPerWeek
        self.weeklyVolume = weeklyVolume
        self.weeklySetCounts = weeklySetCounts
        self.sessionCountByWeekStart = byWeek
        self.personalRecords = personalRecords
        self.strengthRows = StrengthStandards.rows(
            from: sessions,
            bodyweightKg: bodyweightKg,
            gender: gender
        )
        self.muscleRows = MuscleVolume.rows(from: sessions, now: now)
        self.topExercises = Self.topExerciseSeries(
            sessions: sessions,
            personalRecords: personalRecords,
            limit: topExerciseCount
        )
        self.recentSessions = Array(
            sessions
                .sorted { $0.endTime > $1.endTime }
                .prefix(recentSessionsCount)
        )
    }

    /// Monday-based start of week. Moved from ProgressScreen+StatCards.swift
    /// (was private there); internal static so the render-time streak /
    /// this-week helpers keep using the exact same grouping.
    static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    /// For each exercise in `sessions`, compute its per-session best
    /// completed set weight. Sort by total completed-set count desc, keep
    /// the top `limit`. Empty if no weighted sets exist.
    ///
    /// Moved from ProgressScreen+ExerciseCards.swift; `personalRecords` is
    /// passed in (the old code called `store.allPersonalRecords()` inline).
    private static func topExerciseSeries(sessions: [SavedSession],
                                          personalRecords: [PersonalRecord],
                                          limit: Int) -> [ExerciseSeries] {
        struct Agg {
            var unit: String
            var setCount: Int
            var perSession: [(Date, Double)] // sorted oldest first
        }
        var agg: [String: Agg] = [:]
        let ordered = sessions.sorted { $0.startTime < $1.startTime }
        for s in ordered {
            for ex in s.exercises {
                var bestThisSession: Double = 0
                var hasWeightedSet = false
                // Warmup sets excluded — per-exercise best-weight sparkline
                // tracks working sets only.
                for set in ex.sets where set.done && !set.isWarmup {
                    if let w = set.weightValue, w > 0 {
                        hasWeightedSet = true
                        if w > bestThisSession { bestThisSession = w }
                    }
                }
                if !hasWeightedSet { continue }
                var entry = agg[ex.name] ?? Agg(unit: ex.displayUnit, setCount: 0, perSession: [])
                entry.setCount += ex.sets.filter { $0.done && !$0.isWarmup }.count
                entry.perSession.append((s.startTime, bestThisSession))
                agg[ex.name] = entry
            }
        }
        let prsByExercise: [String: Date] = personalRecords
            .reduce(into: [:]) { acc, pr in
                // allPersonalRecords is newest-first, so first hit per name wins.
                if acc[pr.exerciseName] == nil { acc[pr.exerciseName] = pr.date }
            }
        return agg
            .sorted { $0.value.setCount > $1.value.setCount }
            .prefix(limit)
            .map { name, a in
                ExerciseSeries(
                    name: name,
                    unit: a.unit,
                    points: a.perSession.map { SparkPoint(date: $0.0, weight: $0.1) },
                    latest: a.perSession.last?.1 ?? 0,
                    lastPRDate: prsByExercise[name]
                )
            }
    }
}

// MARK: - Memo

/// One-slot memo for ProgressAggregates. Held by ProgressScreen in @State
/// as a plain (non-observable) class on purpose: refilling the cache during
/// a body evaluation must not trigger another render. `personalRecords` is
/// a closure so the SQL-backed PR replay only runs on a cache miss.
@MainActor
final class ProgressAggregatesCache {

    private struct Key: Equatable {
        let sessions: [SavedSession]
        let bodyweightKg: Double?
        let gender: Gender?
        let day: Date
    }

    private var key: Key?
    private var value: ProgressAggregates?

    func aggregates(sessions: [SavedSession],
                    bodyweightKg: Double?,
                    gender: Gender?,
                    weeks: Int,
                    topExerciseCount: Int,
                    recentSessionsCount: Int,
                    personalRecords: () -> [PersonalRecord],
                    now: Date = Date()) -> ProgressAggregates {
        let newKey = Key(
            sessions: sessions,
            bodyweightKg: bodyweightKg,
            gender: gender,
            day: Calendar.current.startOfDay(for: now)
        )
        if let key, let value, key == newKey { return value }
        let computed = ProgressAggregates(
            sessions: sessions,
            personalRecords: personalRecords(),
            bodyweightKg: bodyweightKg,
            gender: gender,
            weeks: weeks,
            topExerciseCount: topExerciseCount,
            recentSessionsCount: recentSessionsCount,
            now: now
        )
        key = newKey
        value = computed
        return computed
    }
}
