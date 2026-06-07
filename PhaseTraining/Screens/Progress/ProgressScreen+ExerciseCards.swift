// ProgressScreen+ExerciseCards.swift — per-exercise trends + activity feed.
//
// Split out of ProgressScreen.swift (architecture item 9, pure move): the
// per-exercise sparkline card, PR feed, recent feedback, and recent sessions
// cards. Card-entry vars are internal (referenced from `content` in the main
// file); everything else stays private to this file.
//
// Architecture item 8: the series aggregation (topExerciseSeries +
// SparkPoint/ExerciseSeries) moved to Data/ProgressAggregates.swift — cards
// read the memoized `aggregates` instead of walking savedSessions /
// replaying allPersonalRecords per render. ProgressCharts.swift's
// ExerciseSparkline now takes `[ProgressAggregates.SparkPoint]`.

import SwiftUI

extension ProgressScreen {

    // MARK: - Per-exercise PR card

    /// HANDOFF §4: replaces the bespoke per-exercise row + ad-hoc card chrome
    /// with TileList + ExerciseTile (.sparkline trailing). Card title moves
    /// to TileList's eyebrow row, dropping the local `card(title:)` wrapper.
    var perExerciseCard: some View {
        let series = aggregates.topExercises
        if series.isEmpty {
            return AnyView(
                card(title: "TOP EXERCISES") {
                    Text("Log weighted sets to see per-exercise trends.")
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            )
        }
        return AnyView(
            TileList(label: "TOP EXERCISES", count: series.count) {
                ForEach(series, id: \.name) { s in
                    ExerciseTile(
                        vm: .init(
                            leading: .none,
                            title: s.name,
                            meta: "\(formatBigNum(s.latest)) \(s.unit)\(prDateSuffix(s.lastPRDate))",
                            trailing: .sparkline(
                                points: normalizedPoints(s.points),
                                pr: isWithin14Days(s.lastPRDate)
                            )
                        ),
                        density: .flat
                    )
                }
            }
        )
    }

    /// Convert per-session SparkPoints (date, weight) to a normalized 0..1
    /// series for `ExerciseTile.sparkline`. Flat series → all zeros.
    private func normalizedPoints(_ pts: [ProgressAggregates.SparkPoint]) -> [Double] {
        guard let min = pts.map(\.weight).min(),
              let max = pts.map(\.weight).max(),
              max > min else {
            return Array(repeating: 0.5, count: pts.count)
        }
        return pts.map { ($0.weight - min) / (max - min) }
    }

    private func prDateSuffix(_ date: Date?) -> String {
        guard let date else { return "" }
        return " · PR \(daysAgo(date))"
    }

    private func isWithin14Days(_ date: Date?) -> Bool {
        guard let date else { return false }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
        return days <= 14
    }

    // MARK: - PR feed

    var prFeedCard: some View {
        let prs = aggregates.personalRecords.prefix(10)
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

    var feedbackCard: some View {
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

    // MARK: - Recent sessions card

    /// Replaces the old History tab that hung off TodayScreen. Shows the
    /// last N sessions inline with a "See all" link that opens the full
    /// HistoryScreen as a sheet. Keeps Progress as the home for past
    /// activity instead of orphaning it on a Today affordance.
    var recentSessionsCard: some View {
        let recent = aggregates.recentSessions
        return card(title: "RECENT SESSIONS") {
            if recent.isEmpty {
                Text("Complete a workout and it'll show up here.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, session in
                        sessionRow(session)
                        if idx < recent.count - 1 {
                            Rectangle()
                                .fill(Color.lineSoft)
                                .frame(height: 0.5)
                        }
                    }
                }

                Button {
                    showingHistory = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all sessions")
                            .styled(.micro)
                            .foregroundStyle(Color.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .accessibilityIdentifier("progress-see-all-sessions")
            }
        }
    }

    private func sessionRow(_ session: SavedSession) -> some View {
        HStack(spacing: 10) {
            Text(SessionRowMeta.monthDayLabel(session.endTime).uppercased())
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 56, alignment: .leading)
            Text(session.name)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(SessionRowMeta.durationLabel(session.duration, style: .spelled))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func daysAgo(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }
}
