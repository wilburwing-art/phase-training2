// ProgressScreen.swift — Progress tab (v2).
//
// Card stack (top → bottom), re-ordered 2026-10-13 so self-referenced
// progress (sessions, volume, strength vs your own earlier best) reads
// before body weight and composition, which research on adherence puts
// closest to dropout when they lead:
//   0. Season badge — phase + mesocycle state.
//   1. Heatmap      — a month of day cells shaded by minutes trained; tap a
//                     day to open its session.
//   2. Soreness pill, then the stat strip — this week vs. target, weekly-
//                     target streak, PRs this month, lifetime session count.
//   3. Sessions/wk  — 8-week bar chart with target line.
//   4. Volume/wk    — 8-week line (falls back to set count when no weights).
//   5. Strength     — est 1RM per canonical lift with the change since 90
//                     days ago, ratio to bodyweight, tier label.
//   6. Muscle balance, recovery section.
//   7. Per-exercise — top ~6 lifts by frequency, each with a best-weight
//                     sparkline (Swift Charts) + last-PR date.
//   8. PR feed      — chronological PR events, newest first.
//   9. Body weight and body composition trends.
//  10. Feedback     — last 10 FeedbackEntry rows with difficulty/hurt chips.
//  11. Recent sessions.
//
// Sessions / volume cards stay hand-drawn — bar/line geometry there is
// simple. The per-exercise sparklines use Swift Charts because the
// per-point math (irregular time axis, multiple series, animation) is
// where Charts pays back its weight.
//
// Card renderers live in Screens/Progress/ (architecture item 9):
//   ProgressScreen+Heatmap.swift       — training-days month heatmap
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
    /// Your lifts: the exercise a TOP EXERCISES row opens, and the full list.
    @State var liftDetail: Exercise?
    @State var showingAllLifts = false

    // Sheet toggles for the body-weight / body-composition trend cards
    // (ProgressScreen+BodyCards.swift). Stored properties can't live in an
    // extension, so they stay on the struct.
    @State var presentingBodyWeightSheet = false
    @State var presentingBodyCompositionSheet = false

    // Training heatmap (ProgressScreen+Heatmap.swift): months back from the
    // current one, the session a tapped day opens, and the choices offered
    // when a tapped day holds more than one session.
    @State var heatmapMonthOffset = 0
    @State var heatmapSession: SavedSession?
    @State var heatmapDayChoices: [SavedSession] = []

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
    /// Native plus imported sessions (`SessionStore.displaySessions`): every
    /// card counts history brought in from another app.
    var sessions: [SavedSession] {
        store.displaySessions(usesImperial: memoryStore.memory.usesImperial)
    }

    var aggregates: ProgressAggregates {
        aggregatesCache.aggregates(
            sessions: sessions,
            bodyweightKg: memoryStore.memory.weightKg,
            gender: memoryStore.memory.gender,
            weeks: Self.weeks,
            topExerciseCount: Self.topExerciseCount,
            recentSessionsCount: Self.recentSessionsPreview,
            personalRecords: { store.allPersonalRecords(usesImperial: memoryStore.memory.usesImperial) }
        )
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            // Gate per-card, not per-tab. The whole screen used to be replaced
            // by "Nothing yet." whenever no workout had been logged — hiding
            // body weight, body composition and the recovery silhouette, which
            // have their own data and render fine before the first session.
            if sessions.isEmpty && !hasNonWorkoutData {
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
                .font(.scaled("SpaceGrotesk-SemiBold", size: 32))
                .tracking(-0.025 * 32)
                .foregroundStyle(Color.ink)
            Text("Log a session and trends show up here.")
                .styled(.body)
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            // Soreness does not need a logged session, and a new user is
            // exactly who might record it first, so the check-in is offered
            // here too rather than only in the populated branch.
            SorenessCheckInPill()
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
                if !sessions.isEmpty {
                    heatmapCard
                }
                SorenessCheckInPill()
                statStrip
                sessionsCard
                volumeCard
                strengthRatiosCard
                muscleBalanceCard
                ProgressRecoverySection()
                perExerciseCard
                prFeedCard
                bodyWeightTrendCard
                bodyCompositionTrendCard
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
        .sheet(item: $liftDetail) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(isPresented: $showingAllLifts) {
            YourLiftsSheet()
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

    /// Implementation lives in ProgressStats so it can be tested at its
    /// magnitude boundaries — see ProgressFormattingTests.
    func formatBigNum(_ v: Double) -> String {
        ProgressStats.formatBigNum(v)
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
        .environmentObject(PlanStore(defaults: defaults))
}
