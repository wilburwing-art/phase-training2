// ProgressScreen+StatCards.swift — stat strip + weekly sessions/volume cards.
//
// Split out of ProgressScreen.swift (architecture item 9, pure move): the
// stat strip, the two weekly charts, and the bucketing/streak helpers they
// read. Card-entry vars are internal (referenced from `content` in the main
// file); everything else stays private to this file.

import SwiftUI

extension ProgressScreen {

    // MARK: - Stat strip

    var statStrip: some View {
        let target = max(memoryStore.memory.liftDaysPerWeek, 1)
        let thisWeek = sessionsThisWeekCount()
        let streak = currentWeeklyTargetStreak(target: target)
        let prsThisMonth = prsInLastDays(30)
        let total = store.savedSessions.count
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
    }

    // MARK: - Sessions per week

    var sessionsCard: some View {
        let buckets = weeklyBuckets { _, _ in 1 }
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
        // Warmup sets excluded — VOLUME / WEEK reflects working sets only.
        let volumes = weeklyBuckets { session, _ in
            session.exercises.reduce(0.0) { acc, ex in
                acc + ex.sets.reduce(0.0) { a, set in
                    guard set.done, !set.isWarmup,
                          let w = set.weightValue,
                          let r = set.repsValue else { return a }
                    return a + (w * Double(r))
                }
            }
        }
        let useSetCount = volumes.allSatisfy { $0 == 0 }
        let series: [Double] = useSetCount
            ? weeklyBuckets { s, _ in Double(s.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && !$0.isWarmup }.count }) }
            : volumes
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

    // MARK: - Bucketing

    /// Returns `weeks` values, oldest at index 0. `value(session, weekIndex)`
    /// returns a per-session contribution; rows are summed.
    private func weeklyBuckets<T: Numeric>(value: (SavedSession, Int) -> T) -> [T] {
        let cal = Calendar.current
        let thisWeekStart = startOfWeek(for: Date(), calendar: cal)
        var buckets = Array(repeating: T.zero, count: Self.weeks)

        for session in store.savedSessions {
            let weekStart = startOfWeek(for: session.startTime, calendar: cal)
            guard let weeksAgo = cal.dateComponents([.weekOfYear], from: weekStart, to: thisWeekStart).weekOfYear else { continue }
            let idx = Self.weeks - 1 - weeksAgo
            guard idx >= 0, idx < Self.weeks else { continue }
            buckets[idx] = buckets[idx] + value(session, idx)
        }

        return buckets
    }

    private func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    // MARK: - Stat helpers

    private func sessionsThisWeekCount() -> Int {
        let cal = Calendar.current
        let weekStart = startOfWeek(for: Date(), calendar: cal)
        return store.savedSessions.filter { $0.startTime >= weekStart }.count
    }

    /// Consecutive weeks (ending with the most recent week that has any
    /// session) where session count ≥ target. Returns 0 if the most-recent
    /// session is older than this-week-or-last-week or never met target.
    private func currentWeeklyTargetStreak(target: Int) -> Int {
        let cal = Calendar.current
        let thisWeekStart = startOfWeek(for: Date(), calendar: cal)

        // Group sessions by week-start.
        var byWeek: [Date: Int] = [:]
        for s in store.savedSessions {
            let ws = startOfWeek(for: s.startTime, calendar: cal)
            byWeek[ws, default: 0] += 1
        }

        // Walk back from this week (or last week if this week is empty) and
        // count consecutive weeks meeting target.
        var streak = 0
        var cursor = thisWeekStart
        if (byWeek[cursor] ?? 0) < target {
            // Allow grace: if user hasn't trained yet this week, start
            // counting from last week instead.
            cursor = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        while (byWeek[cursor] ?? 0) >= target {
            streak += 1
            cursor = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    private func prsInLastDays(_ days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return store.allPersonalRecords().filter { $0.date >= cutoff }.count
    }
}
