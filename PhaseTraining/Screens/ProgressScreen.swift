// ProgressScreen.swift — Progress tab (v2).
//
// Card stack (top → bottom):
//   1. Stat strip   — this week vs. target, weekly-target streak, PRs this
//                     month, lifetime session count.
//   2. Sessions/wk  — 8-week bar chart with target line.
//   3. Volume/wk    — 8-week line (falls back to set count when no weights).
//   4. Per-exercise — top ~6 lifts by frequency, each with a best-weight
//                     sparkline (Swift Charts) + last-PR date.
//   5. PR feed      — chronological PR events, newest first.
//   6. Feedback     — last 10 FeedbackEntry rows with difficulty/hurt chips.
//
// Sessions / volume cards stay hand-drawn — bar/line geometry there is
// simple. The per-exercise sparklines use Swift Charts because the
// per-point math (irregular time axis, multiple series, animation) is
// where Charts pays back its weight.

import SwiftUI
import Charts

struct ProgressScreen: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var memoryStore: MemoryStore

    private static let weeks = 8
    private static let topExerciseCount = 6

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            if store.savedSessions.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("PROGRESS")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text("Nothing yet.")
                .font(.custom("SpaceGrotesk-SemiBold", size: 32))
                .tracking(-0.025 * 32)
                .foregroundStyle(Color.ink)
            Text("Log a session and trends show up here.")
                .styled(.body)
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statStrip
                sessionsCard
                volumeCard
                perExerciseCard
                prFeedCard
                feedbackCard
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROGRESS")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text("Last 8 weeks")
                .font(.custom("SpaceGrotesk-SemiBold", size: 30))
                .tracking(-0.025 * 30)
                .foregroundStyle(Color.ink)
        }
    }

    // MARK: - Stat strip

    private var statStrip: some View {
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

    private var sessionsCard: some View {
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

    private var volumeCard: some View {
        let volumes = weeklyBuckets { session, _ in
            session.exercises.reduce(0.0) { acc, ex in
                acc + ex.sets.reduce(0.0) { a, set in
                    guard set.done,
                          let w = Double(set.weight),
                          let r = Double(set.reps) else { return a }
                    return a + (w * r)
                }
            }
        }
        let useSetCount = volumes.allSatisfy { $0 == 0 }
        let series: [Double] = useSetCount
            ? weeklyBuckets { s, _ in Double(s.exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }) }
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

    // MARK: - Per-exercise PR card

    private var perExerciseCard: some View {
        let series = topExerciseSeries(limit: Self.topExerciseCount)
        return card(title: "TOP EXERCISES") {
            if series.isEmpty {
                Text("Log weighted sets to see per-exercise trends.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(series.enumerated()), id: \.element.name) { idx, s in
                        exerciseRow(s)
                        if idx < series.count - 1 {
                            Rectangle()
                                .fill(Color.lineSoft)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }

    private func exerciseRow(_ s: ExerciseSeries) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(formatBigNum(s.latest)) \(s.unit)")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink2)
                    if let prDate = s.lastPRDate {
                        Text("· PR \(daysAgo(prDate))")
                            .font(.monoXS)
                            .foregroundStyle(Color.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ExerciseSparkline(points: s.points)
                .frame(width: 96, height: 32)
        }
        .padding(.vertical, 10)
    }

    // MARK: - PR feed

    private var prFeedCard: some View {
        let prs = store.allPersonalRecords().prefix(10)
        return card(title: "RECENT PRs") {
            if prs.isEmpty {
                Text("No PRs yet. Beat any prior set to land one.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(prs.enumerated()), id: \.offset) { idx, pr in
                        prRow(pr)
                        if idx < prs.count - 1 {
                            Rectangle()
                                .fill(Color.lineSoft)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }

    private func prRow(_ pr: PersonalRecord) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.exerciseName)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(formatBigNum(pr.weight)) × \(pr.reps)")
                        .font(.monoXS)
                        .foregroundStyle(Color.accent)
                    if let prior = pr.previousBest {
                        Text("+\(formatBigNum(pr.weight - prior))")
                            .font(.monoXS)
                            .foregroundStyle(Color.ok)
                    } else {
                        Text("first")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(daysAgo(pr.date))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Recent feedback

    private var feedbackCard: some View {
        let recent = Array(memoryStore.memory.feedback.suffix(10).reversed())
        return card(title: "RECENT FEEDBACK") {
            if recent.isEmpty {
                Text("None yet. Add notes from the Complete screen.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, entry in
                        feedbackRow(entry)
                        if idx < recent.count - 1 {
                            Rectangle()
                                .fill(Color.lineSoft)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
    }

    private func feedbackRow(_ entry: FeedbackEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let d = entry.difficulty {
                        difficultyChip(d)
                    }
                    if entry.ranLong {
                        Text("RAN LONG")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                    }
                    if !entry.hurtAreas.isEmpty {
                        Text("HURT: \(entry.hurtAreas.joined(separator: ", "))")
                            .styled(.micro)
                            .foregroundStyle(Color.danger)
                            .lineLimit(1)
                    }
                }
                if let n = entry.notes, !n.isEmpty {
                    Text(n)
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color.ink2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(daysAgo(entry.date))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, 10)
    }

    private func difficultyChip(_ d: String) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch d {
            case "too_easy": return ("TOO EASY", Color.ok.opacity(0.85), Color.accentInk)
            case "right":    return ("RIGHT",    Color.accent,           Color.accentInk)
            case "too_hard": return ("TOO HARD", Color.danger.opacity(0.9), Color.accentInk)
            default:         return (d.uppercased(), Color.elevated, Color.ink2)
            }
        }()
        return Text(label)
            .styled(.micro)
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Card chrome

    private func card<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: - Per-exercise series

    private struct ExerciseSeries {
        let name: String
        let unit: String
        let points: [SparkPoint]
        let latest: Double
        let lastPRDate: Date?
    }

    struct SparkPoint: Identifiable {
        let id = UUID()
        let date: Date
        let weight: Double
    }

    /// For each exercise in `savedSessions`, compute its per-session best
    /// completed set weight. Sort by total completed-set count desc, keep
    /// the top `limit`. Empty if no weighted sets exist.
    private func topExerciseSeries(limit: Int) -> [ExerciseSeries] {
        struct Agg {
            var unit: String
            var setCount: Int
            var perSession: [(Date, Double)] // sorted oldest first
        }
        var agg: [String: Agg] = [:]
        let ordered = store.savedSessions.sorted { $0.startTime < $1.startTime }
        for s in ordered {
            for ex in s.exercises {
                var bestThisSession: Double = 0
                var hasWeightedSet = false
                for set in ex.sets where set.done {
                    if let w = Double(set.weight), w > 0 {
                        hasWeightedSet = true
                        if w > bestThisSession { bestThisSession = w }
                    }
                }
                if !hasWeightedSet { continue }
                var entry = agg[ex.name] ?? Agg(unit: ex.unit, setCount: 0, perSession: [])
                entry.setCount += ex.sets.filter(\.done).count
                entry.perSession.append((s.startTime, bestThisSession))
                agg[ex.name] = entry
            }
        }
        let prsByExercise: [String: Date] = store.allPersonalRecords()
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

    // MARK: - Helpers

    private func daysAgo(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }

    private func formatBigNum(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v < 1000 { return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v) }
        if v < 10_000 { return String(format: "%.1fk", v / 1000) }
        return "\(Int(v / 1000))k"
    }
}

// MARK: - LineSpark (hand-drawn — used by Volume card)

private struct LineSpark: View {
    let points: [Double]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(points.count, 1)
            let stepX = count > 1 ? w / CGFloat(count - 1) : w / 2

            ZStack {
                // Baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(Color.line, lineWidth: 0.5)

                // Line
                Path { p in
                    for (i, value) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = h - (h * CGFloat(value / maxValue))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                // Dots
                ForEach(points.indices, id: \.self) { i in
                    let x = CGFloat(i) * stepX
                    let y = h - (h * CGFloat(points[i] / maxValue))
                    Circle()
                        .fill(Color.accent)
                        .frame(width: i == points.count - 1 ? 6 : 3, height: i == points.count - 1 ? 6 : 3)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - ExerciseSparkline (Swift Charts — used by per-exercise card)

private struct ExerciseSparkline: View {
    let points: [ProgressScreen.SparkPoint]

    var body: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("date", p.date), y: .value("weight", p.weight))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            if let last = points.last {
                PointMark(x: .value("date", last.date), y: .value("weight", last.weight))
                    .foregroundStyle(Color.accent)
                    .symbolSize(24)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.background(Color.clear) }
    }
}

// MARK: - Preview

#Preview {
    let suite = "ProgressScreen.preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let store = SessionStore(defaults: defaults)
    let memory = MemoryStore(defaults: defaults)

    // Seed 6 sessions across the last 5 weeks with progressing weights so
    // PR feed + per-exercise sparklines have content.
    let cal = Calendar.current
    let now = Date()
    var sessions: [SavedSession] = []
    let progression: [(daysBack: Int, bench: String, pull: String)] = [
        (32, "115", "0"),
        (24, "125", "10"),
        (16, "135", "15"),
        (10, "145", "20"),
        (4,  "150", "25"),
        (1,  "155", "30"),
    ]
    for p in progression {
        let start = cal.date(byAdding: .day, value: -p.daysBack, to: now) ?? now
        sessions.append(SavedSession(
            templateId: "upper-1",
            name: "Upper Body",
            category: "Push / Pull",
            startTime: start,
            exercises: [
                LoggedExercise(
                    id: "bench", name: "Bench", type: "Barbell", unit: "lbs",
                    targetSets: 5, targetReps: 5, rest: 120,
                    sets: [
                        LoggedSet(num: 1, weight: p.bench, reps: "5", rpe: "7", done: true),
                        LoggedSet(num: 2, weight: p.bench, reps: "5", rpe: "8", done: true),
                        LoggedSet(num: 3, weight: p.bench, reps: "5", rpe: "9", done: true),
                    ],
                    prevSets: []
                ),
                LoggedExercise(
                    id: "pull", name: "Weighted Pull-Up", type: "Bodyweight", unit: "lbs",
                    targetSets: 4, targetReps: 6, rest: 150,
                    sets: [
                        LoggedSet(num: 1, weight: p.pull, reps: "6", rpe: "7", done: true),
                        LoggedSet(num: 2, weight: p.pull, reps: "6", rpe: "8", done: true),
                    ],
                    prevSets: []
                )
            ],
            feel: "Right", note: nil,
            endTime: start.addingTimeInterval(2700), duration: 2700
        ))
    }
    store.saveAll(sessions)
    memory.update { m in
        m.liftDaysPerWeek = 3
        m.feedback = [
            FeedbackEntry(date: now.addingTimeInterval(-86400),
                          sessionId: "upper-1",
                          difficulty: "too_hard",
                          hurtAreas: ["bench"],
                          ranLong: false,
                          notes: "Shoulder ached on press"),
            FeedbackEntry(date: now.addingTimeInterval(-3 * 86400),
                          sessionId: "upper-1",
                          difficulty: "right",
                          ranLong: true,
                          notes: nil)
        ]
    }

    return ProgressScreen()
        .environmentObject(store)
        .environmentObject(memory)
}
