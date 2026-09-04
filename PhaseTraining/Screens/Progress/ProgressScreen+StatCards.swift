// ProgressScreen+StatCards.swift — stat strip + weekly sessions/volume cards.
//
// Split out of ProgressScreen.swift (architecture item 9, pure move): the
// stat strip, the two weekly charts, and the bucketing/streak helpers they
// read. Card-entry vars are internal (referenced from `content` in the main
// file); everything else stays private to this file.
//
// Architecture item 8: the weeklyBuckets walk moved to ProgressAggregates —
// cards read the memoized buckets via `aggregates`. The this-week / streak /
// PRs·30d helpers stay render-time (they depend on the current Date and the
// weekly target, which aren't cache-keyed) but now read the cached byWeek
// grouping and PR list instead of walking savedSessions.

import SwiftUI

extension ProgressScreen {

    // MARK: - Stat strip

    var statStrip: some View {
        let agg = aggregates
        let target = max(memoryStore.memory.liftDaysPerWeek, 1)
        let thisWeek = sessionsThisWeekCount(byWeek: agg.sessionCountByWeekStart)
        let streak = currentWeeklyTargetStreak(target: target, byWeek: agg.sessionCountByWeekStart)
        let prsThisMonth = prsInLastDays(30, in: agg.personalRecords)
        let total = agg.totalSessions
        return HStack(spacing: 8) {
            statCell(label: "THIS WEEK", value: "\(thisWeek)", sub: "/ \(target)", emphasised: thisWeek >= target)
            statCell(label: "STREAK", value: "\(streak)", sub: streak == 1 ? "wk" : "wks", emphasised: streak > 0)
            statCell(label: "PRs · 30d", value: "\(prsThisMonth)", sub: nil, emphasised: prsThisMonth > 0)
            statCell(label: "TOTAL", value: "\(total)", sub: nil, emphasised: false)
        }
    }

    private func statCell(label: String, value: String, sub: String?, emphasised: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 26))
                    .tracking(-0.025 * 26)
                    .foregroundStyle(emphasised ? Color.accent : Color.ink)
                if let sub {
                    Text(sub)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // VoiceOver: "SESSIONS" / "12" / "this month" as three elements says
        // nothing. One element, label then value then qualifier.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized), \(value)\(sub.map { ", \($0)" } ?? "")")
    }

    // MARK: - Sessions per week

    var sessionsCard: some View {
        let buckets = aggregates.sessionsPerWeek
        let target = max(memoryStore.memory.liftDaysPerWeek, 1)
        let maxVal = max(buckets.max() ?? 0, target + 1)
        return card(title: "SESSIONS / WEEK") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(buckets.indices, id: \.self) { i in
                        sessionBar(count: buckets[i], maxCount: maxVal, target: target)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 88)
                HStack {
                    Text("\(Self.weeks)w ago")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    Text("target: \(target)/wk")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    Text("this week")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func sessionBar(count: Int, maxCount: Int, target: Int) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fillH = h * CGFloat(count) / CGFloat(maxCount)
            let targetY = h - h * CGFloat(target) / CGFloat(maxCount)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.elevated)
                RoundedRectangle(cornerRadius: 4)
                    .fill(count >= target ? Color.accent : Color.accentDim)
                    .frame(height: max(fillH, count == 0 ? 0 : 2))
                Rectangle()
                    .fill(Color.accent.opacity(0.4))
                    .frame(height: 0.5)
                    .offset(y: -(h - targetY))
            }
        }
    }

    // MARK: - Volume trend

    var volumeCard: some View {
        // Warmup sets excluded — VOLUME / WEEK reflects working sets only
        // (the walk lives in ProgressAggregates).
        let agg = aggregates
        let volumes = agg.weeklyVolume
        let useSetCount = volumes.allSatisfy { $0 == 0 }
        let series: [Double] = useSetCount ? agg.weeklySetCounts : volumes
        let maxVal = max(series.max() ?? 0, 1)
        return card(title: useSetCount ? "SETS / WEEK" : "VOLUME / WEEK") {
            VStack(alignment: .leading, spacing: 10) {
                LineSpark(points: series, maxValue: maxVal)
                    .frame(height: 70)
                HStack {
                    Text("0")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    Text(formatBigNum(series.last ?? 0))
                        .font(.monoXS)
                        .foregroundStyle(series.last ?? 0 > 0 ? Color.accent : Color.ink3)
                }
            }
        }
    }

    // MARK: - Stat helpers
    //
    // weeklyBuckets / startOfWeek moved to ProgressAggregates (item 8). The
    // helpers below stay here because they mix cached data with render-time
    // inputs (current Date, weekly target).

    /// Was a filter over savedSessions (`startTime >= weekStart`); summing
    /// the byWeek grouping over keys >= this week's start counts exactly the
    /// same sessions — `startOfWeek(d) >= thisWeekStart ⟺ d >= thisWeekStart`.
    private func sessionsThisWeekCount(byWeek: [Date: Int]) -> Int {
        let cal = Calendar.current
        let weekStart = ProgressAggregates.startOfWeek(for: Date(), calendar: cal)
        return byWeek.reduce(0) { $0 + ($1.key >= weekStart ? $1.value : 0) }
    }

    /// Consecutive weeks (ending with the most recent week that has any
    /// session) where session count ≥ target. Returns 0 if the most-recent
    /// session is older than this-week-or-last-week or never met target.
    private func currentWeeklyTargetStreak(target: Int, byWeek: [Date: Int]) -> Int {
        let cal = Calendar.current
        let thisWeekStart = ProgressAggregates.startOfWeek(for: Date(), calendar: cal)

        // Walk back from this week (or last week if this week is empty) and
        // count consecutive weeks meeting target.
        var streak = 0
        var cursor = thisWeekStart
        if (byWeek[cursor] ?? 0) < target {
            // Allow grace: if user hasn't trained yet this week, start
            // counting from last week instead.
            cursor = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        // Bounded by the oldest week we actually have data for. The old loop
        // advanced with `?? cursor`, so a nil from date arithmetic left the
        // cursor pinned while `byWeek[cursor] >= target` stayed true — an
        // infinite loop on the main thread, inside a body evaluation.
        let oldestWeek = byWeek.keys.min() ?? cursor
        while (byWeek[cursor] ?? 0) >= target, cursor >= oldestWeek {
            streak += 1
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private func prsInLastDays(_ days: Int, in records: [PersonalRecord]) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return records.filter { $0.date >= cutoff }.count
    }
}
