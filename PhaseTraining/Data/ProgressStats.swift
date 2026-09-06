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

// MARK: - Body-weight / body-composition card derivations

extension ProgressStats {

    /// Net change from the first to the last value in a series. Nil for
    /// series with fewer than two points — one reading is a value, not a
    /// trend, and the card renders no delta chip for it.
    static func trendDelta(_ values: [Double]) -> Double? {
        guard let first = values.first, let last = values.last, values.count >= 2 else {
            return nil
        }
        return last - first
    }

    /// Body-fat readings in log order, oldest first, skipping entries that
    /// carry only lean mass. Percent units ("18.5" means 18.5%).
    static func bodyFatSeries(in log: [BodyCompositionEntry]) -> [Double] {
        chronological(log).compactMap(\.bodyFatPercent)
    }

    /// Lean-mass readings in log order, oldest first, skipping entries that
    /// carry only body fat. Converted to lb when `imperial`.
    static func leanMassSeries(in log: [BodyCompositionEntry], imperial: Bool) -> [Double] {
        chronological(log).compactMap { entry in
            guard let lean = entry.leanMassKg else { return nil }
            return imperial ? BodyMetrics.kgToLb(lean) : lean
        }
    }

    /// Most recent NON-NIL body fat reading.
    ///
    /// Not simply `log.last?.bodyFatPercent`: DEXA users log both metrics
    /// while scale users log only body fat, so a newest entry carrying only
    /// lean mass would blank out the BF stat while its sparkline still
    /// rendered from the full series — a card showing a trend line above a
    /// missing number.
    static func latestBodyFatPercent(in log: [BodyCompositionEntry]) -> Double? {
        chronological(log).last(where: { $0.bodyFatPercent != nil })?.bodyFatPercent
    }

    /// Most recent NON-NIL lean-mass reading, in kg. Mirror of
    /// `latestBodyFatPercent` — see its note.
    static func latestLeanMassKg(in log: [BodyCompositionEntry]) -> Double? {
        chronological(log).last(where: { $0.leanMassKg != nil })?.leanMassKg
    }

    /// Net body-weight change across the whole log, in kg. Nil for a log
    /// with fewer than two entries.
    static func bodyWeightDeltaKg(in log: [BodyWeightEntry]) -> Double? {
        trendDelta(chronological(log).map(\.weightKg))
    }

    /// Most recent logged body weight, in kg.
    static func latestBodyWeightKg(in log: [BodyWeightEntry]) -> Double? {
        chronological(log).last?.weightKg
    }

    // The card sorts its log before rendering; these helpers sort too, so a
    // caller that forgets can't silently produce a "latest" reading from the
    // middle of the log.
    private static func chronological(_ log: [BodyCompositionEntry]) -> [BodyCompositionEntry] {
        log.sorted { $0.date < $1.date }
    }

    private static func chronological(_ log: [BodyWeightEntry]) -> [BodyWeightEntry] {
        log.sorted { $0.date < $1.date }
    }
}

// MARK: - Card presentation helpers

extension ProgressStats {

    /// Compact number for the stat cells, PR rows and the volume read-out.
    ///
    /// Under 1000 renders exactly (dropping a trailing ".0"), then switches
    /// to "k" — one decimal below 10k, whole thousands above. Weekly volume
    /// runs to six figures, which is why the display truncates rather than
    /// rounding to a unit: "42k" is the honest precision at that magnitude.
    static func formatBigNum(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v < 1000 {
            return v.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(v))"
                : String(format: "%.1f", v)
        }
        if v < 10_000 { return String(format: "%.1fk", v / 1000) }
        return "\(Int(v / 1000))k"
    }

    /// Relative day label for the PR feed, feedback rows and per-exercise
    /// PR suffixes.
    ///
    /// Counts whole ELAPSED days between the two instants, not calendar-date
    /// difference: something logged 23 hours ago reads "today" even after
    /// midnight. Anything not in the past reads "today" too.
    static func daysAgo(_ date: Date,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }

    /// Whether a PR is recent enough for the per-exercise tile to flag it.
    static func isWithinDays(_ days: Int,
                             of date: Date?,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> Bool {
        guard let date else { return false }
        let elapsed = calendar.dateComponents([.day], from: date, to: now).day ?? 999
        return elapsed <= days
    }

    /// Scale a per-session weight series into the 0...1 range ExerciseTile's
    /// sparkline draws in.
    ///
    /// A series with no spread (one point, or every session at the same
    /// weight) has no meaningful shape, so every point renders at 0.5 — a
    /// flat line through the middle of the tile. Mapping those to 0 would
    /// pin the line to the bottom edge and read as a collapse in strength
    /// rather than a plateau.
    static func normalizedPoints(_ pts: [ProgressAggregates.SparkPoint]) -> [Double] {
        guard let min = pts.map(\.weight).min(),
              let max = pts.map(\.weight).max(),
              max > min else {
            return Array(repeating: 0.5, count: pts.count)
        }
        return pts.map { ($0.weight - min) / (max - min) }
    }
}
