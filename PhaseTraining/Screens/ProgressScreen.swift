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
//
// Card renderers live in Screens/Progress/ (architecture item 9):
//   ProgressScreen+StatCards.swift     — stat strip, sessions/wk, volume/wk
//   ProgressScreen+BodyCards.swift     — body weight/composition, strength
//                                        ratios, muscle balance
//   ProgressScreen+ExerciseCards.swift — per-exercise, PR feed, feedback,
//                                        recent sessions
//   ProgressCharts.swift               — LineSpark, BodyWeightSpark,
//                                        ExerciseSparkline
// This file keeps the shell: body/content/emptyState, the card() chrome,
// shared state, and formatBigNum.
//
// Session-derived card inputs are memoized through ProgressAggregates
// (Data/ProgressAggregates.swift, architecture item 8) — cards read
// `aggregates` instead of walking store.savedSessions per render.

import SwiftUI

struct ProgressScreen: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var memoryStore: MemoryStore

    /// Build 92: history surfaced from here via "See all sessions" on the
    /// Recent Sessions card. Previously lived as a tab off the Today screen.
    @State var showingHistory = false

    // Sheet toggles for the body-weight / body-composition trend cards
    // (ProgressScreen+BodyCards.swift). Stored properties can't live in an
    // extension, so they stay on the struct.
    @State var presentingBodyWeightSheet = false
    @State var presentingBodyCompositionSheet = false

    static let weeks = 8
    static let topExerciseCount = 6
    static let recentSessionsPreview = 5

    // MARK: - Memoized aggregates (architecture item 8)

    /// Plain class in @State — deliberately not observable, so refilling the
    /// memo during a body evaluation doesn't trigger another render. The card
    /// extensions read it through `aggregates` below, so it stays private.
    @State private var aggregatesCache = ProgressAggregatesCache()

    /// One-stop read for every session-derived card input. The memo's key is
    /// checked on each access (savedSessions content + bodyweight + gender +
    /// calendar day), so a save / restore / profile edit recomputes on the
    /// very next render — no view-lifecycle invalidation to go stale.
    var aggregates: ProgressAggregates {
        aggregatesCache.aggregates(
            sessions: store.savedSessions,
            bodyweightKg: memoryStore.memory.weightKg,
            gender: memoryStore.memory.gender,
            weeks: Self.weeks,
            topExerciseCount: Self.topExerciseCount,
            recentSessionsCount: Self.recentSessionsPreview,
            personalRecords: { store.allPersonalRecords() }
        )
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            // Gate per-card, not per-tab. The whole screen used to be replaced
            // by "Nothing yet." whenever no workout had been logged — hiding
            // body weight, body composition and the recovery silhouette, which
            // have their own data and render fine before the first session.
            if store.savedSessions.isEmpty && !hasNonWorkoutData {
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

    /// Data that exists independently of logged workouts, so the tab has
    /// something real to show before the first session is finished.
    private var hasNonWorkoutData: Bool {
        !memoryStore.memory.bodyWeightLog.isEmpty
            || !memoryStore.memory.bodyCompositionLog.isEmpty
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TabHeader(
                    eyebrow: "PROGRESS",
                    eyebrowTrailing: "LAST \(Self.weeks) WK",
                    title: "Last \(Self.weeks) weeks",
                    subtitle: nil
                )
                .padding(.horizontal, -20)
                SeasonPhaseBadge(style: .full, surface: "progress")
                statStrip
                bodyWeightTrendCard
                bodyCompositionTrendCard
                sessionsCard
                volumeCard
                strengthRatiosCard
                muscleBalanceCard
                ProgressRecoverySection()
                perExerciseCard
                prFeedCard
                feedbackCard
                recentSessionsCard
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryScreen()
                .environmentObject(store)
        }
    }

    // MARK: - Card chrome

    func card<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
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

    // MARK: - Helpers

    func formatBigNum(_ v: Double) -> String {
        if v == 0 { return "0" }
        if v < 1000 { return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v) }
        if v < 10_000 { return String(format: "%.1fk", v / 1000) }
        return "\(Int(v / 1000))k"
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
