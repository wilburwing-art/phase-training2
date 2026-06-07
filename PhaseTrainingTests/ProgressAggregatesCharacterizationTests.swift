// ProgressAggregatesCharacterizationTests.swift — architecture item 8 gate.
//
// The architecture report (§10.c) requires that switching the Progress cards
// from per-render walks over store.savedSessions to the memoized
// ProgressAggregates layer is behavior-preserving: same sessions in → same
// buckets / series / rows out as the previous per-render computation.
//
// The "legacy" oracles below are VERBATIM copies of the pre-memoization code
// (commit 7a39445: ProgressScreen+StatCards.swift weeklyBuckets/startOfWeek/
// currentWeeklyTargetStreak grouping, ProgressScreen+ExerciseCards.swift
// topExerciseSeries, ProgressScreen+BodyCards.swift card call sites,
// recentSessionsCard), parameterized only on what was implicit view state:
// `store.savedSessions` → a sessions argument, `Date()` → a fixed `now`
// shared by both sides of every assertion. Do not "fix" the oracles — their
// job is to pin the old behavior exactly.

import XCTest
@testable import PhaseTraining

final class ProgressAggregatesCharacterizationTests: XCTestCase {

    // MARK: - Legacy oracles (verbatim, pre-memoization)

    /// Copy of the old private `startOfWeek(for:calendar:)` — Monday-based.
    private func legacyStartOfWeek(for date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    /// Copy of the old private `weeklyBuckets(value:)` — the per-card walk
    /// the memoization replaced. Returns `weeks` values, oldest at index 0.
    private func legacyWeeklyBuckets<T: Numeric>(sessions: [SavedSession],
                                                 weeks: Int,
                                                 now: Date,
                                                 value: (SavedSession, Int) -> T) -> [T] {
        let cal = Calendar.current
        let thisWeekStart = legacyStartOfWeek(for: now, calendar: cal)
        var buckets = Array(repeating: T.zero, count: weeks)

        for session in sessions {
            let weekStart = legacyStartOfWeek(for: session.startTime, calendar: cal)
            guard let weeksAgo = cal.dateComponents([.weekOfYear], from: weekStart, to: thisWeekStart).weekOfYear else { continue }
            let idx = weeks - 1 - weeksAgo
            guard idx >= 0, idx < weeks else { continue }
            buckets[idx] = buckets[idx] + value(session, idx)
        }

        return buckets
    }

    private struct LegacySeries {
        let name: String
        let unit: String
        let points: [(Date, Double)]
        let latest: Double
        let lastPRDate: Date?
    }

    /// Copy of the old private `topExerciseSeries(limit:)`. The original
    /// called `store.allPersonalRecords()` inline; the PR list is a parameter
    /// here so both sides of the assertion consume the identical list.
    private func legacyTopExerciseSeries(sessions: [SavedSession],
                                         personalRecords: [PersonalRecord],
                                         limit: Int) -> [LegacySeries] {
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
                LegacySeries(
                    name: name,
                    unit: a.unit,
                    points: a.perSession,
                    latest: a.perSession.last?.1 ?? 0,
                    lastPRDate: prsByExercise[name]
                )
            }
    }

    // MARK: - Fixtures

    private func loggedExercise(name: String,
                                unit: String = "lbs",
                                sets: [(weight: String, reps: String, done: Bool, warmup: Bool)]) -> LoggedExercise {
        LoggedExercise(
            id: name, name: name, type: nil, unit: unit,
            targetSets: sets.count, targetReps: 5, rest: 90,
            sets: sets.enumerated().map { i, s in
                LoggedSet(num: i + 1, weight: s.weight, reps: s.reps, rpe: "", done: s.done, isWarmup: s.warmup)
            },
            prevSets: []
        )
    }

    private func savedSession(offsetDays: Int,
                              exercises: [LoggedExercise],
                              now: Date) -> SavedSession {
        let start = Calendar.current.date(byAdding: .day, value: offsetDays, to: now) ?? now
        return SavedSession(
            templateId: "t", name: "Workout", category: "",
            startTime: start, exercises: exercises,
            feel: nil, note: nil,
            endTime: start.addingTimeInterval(3600), duration: 3600
        )
    }

    /// Mixed history exercising the edges the old per-render walks handled
    /// implicitly:
    ///  - s0: 63 days back — outside the 8-week chart window (dropped from
    ///        buckets), still inside byWeek / PRs / topExercises.
    ///  - s1: 24 days back — warmup set HEAVIER than the working sets; must
    ///        stay excluded from volume / series / PRs / standards.
    ///  - s2: 10 days back — includes a reps-only bodyweight exercise (no
    ///        weight logged): counts toward set counts, never topExercises.
    ///  - s3:  3 days back — includes an undone set (excluded everywhere).
    ///  - s4:  1 day back — distinct per-exercise set counts pin the ranking.
    ///  - s5:  8 days ahead — outside the chart window on the future side;
    ///        still present in byWeek / topExercises / recents.
    /// Exercise names resolve in coach.db ("Barbell Bench Press",
    /// "Barbell Back Squat") so strength-ratio + muscle-volume rows are
    /// non-empty — the characterization must not pass vacuously.
    private func fixtureSessions(now: Date) -> [SavedSession] {
        let bench = "Barbell Bench Press"
        let squat = "Barbell Back Squat"
        return [
            savedSession(offsetDays: -63, exercises: [
                loggedExercise(name: bench, sets: [
                    ("135", "5", true, false),
                    ("135", "5", true, false),
                ]),
            ], now: now),
            savedSession(offsetDays: -24, exercises: [
                loggedExercise(name: bench, sets: [
                    ("999", "5", true, true), // warmup heavier than working
                    ("145", "5", true, false),
                    ("145", "5", true, false),
                    ("145", "5", true, false),
                ]),
                loggedExercise(name: squat, sets: [
                    ("185", "5", true, false),
                    ("185", "5", true, false),
                ]),
            ], now: now),
            savedSession(offsetDays: -10, exercises: [
                loggedExercise(name: bench, sets: [
                    ("155", "5", true, false),
                    ("155", "5", true, false),
                    ("155", "5", true, false),
                ]),
                loggedExercise(name: squat, sets: [
                    ("205", "5", true, false),
                    ("205", "5", true, false),
                ]),
                loggedExercise(name: "Plank", unit: LoggedExercise.bodyweightUnit, sets: [
                    ("", "30", true, false),
                    ("", "30", true, false),
                ]),
            ], now: now),
            savedSession(offsetDays: -3, exercises: [
                loggedExercise(name: bench, sets: [
                    ("165", "5", true, false),
                    ("165", "5", true, false),
                    ("165", "5", true, false),
                    ("175", "5", false, false), // undone — excluded
                ]),
            ], now: now),
            savedSession(offsetDays: -1, exercises: [
                loggedExercise(name: squat, sets: [
                    ("225", "5", true, false),
                    ("225", "5", true, false),
                ]),
                loggedExercise(name: "Dumbbell Row", sets: [
                    ("80", "8", true, false),
                ]),
            ], now: now),
            savedSession(offsetDays: 8, exercises: [
                loggedExercise(name: bench, sets: [
                    ("100", "5", true, false),
                ]),
            ], now: now),
        ]
    }

    private func makeAggregates(sessions: [SavedSession],
                                personalRecords: [PersonalRecord] = [],
                                bodyweightKg: Double? = nil,
                                gender: Gender? = nil,
                                weeks: Int = 8,
                                topExerciseCount: Int = 6,
                                recentSessionsCount: Int = 5,
                                now: Date) -> ProgressAggregates {
        ProgressAggregates(
            sessions: sessions,
            personalRecords: personalRecords,
            bodyweightKg: bodyweightKg,
            gender: gender,
            weeks: weeks,
            topExerciseCount: topExerciseCount,
            recentSessionsCount: recentSessionsCount,
            now: now
        )
    }

    private func freshStore(_ suite: String = #function) -> SessionStore {
        let name = "ProgressAggregatesCharacterizationTests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SessionStore(defaults: defaults, userDB: UserDatabase(path: ":memory:"))
    }

    // MARK: - (1) Weekly buckets / volume sums / session counts

    func test_weeklyBuckets_matchLegacyPerRenderComputation() {
        let now = Date()
        let sessions = fixtureSessions(now: now)
        let agg = makeAggregates(sessions: sessions, now: now)

        // sessionsCard: weeklyBuckets { _, _ in 1 }
        let legacySessions: [Int] = legacyWeeklyBuckets(sessions: sessions, weeks: 8, now: now) { _, _ in 1 }
        XCTAssertEqual(agg.sessionsPerWeek, legacySessions)

        // volumeCard: verbatim legacy volume contribution closure.
        let legacyVolume: [Double] = legacyWeeklyBuckets(sessions: sessions, weeks: 8, now: now) { session, _ in
            session.exercises.reduce(0.0) { acc, ex in
                acc + ex.sets.reduce(0.0) { a, set in
                    guard set.done, !set.isWarmup,
                          let w = set.weightValue,
                          let r = set.repsValue else { return a }
                    return a + (w * Double(r))
                }
            }
        }
        XCTAssertEqual(agg.weeklyVolume, legacyVolume)

        // volumeCard set-count fallback: verbatim legacy closure.
        let legacySetCounts: [Double] = legacyWeeklyBuckets(sessions: sessions, weeks: 8, now: now) { s, _ in
            Double(s.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && !$0.isWarmup }.count })
        }
        XCTAssertEqual(agg.weeklySetCounts, legacySetCounts)

        // Stat strip TOTAL was `store.savedSessions.count`.
        XCTAssertEqual(agg.totalSessions, sessions.count)

        // Fixture sanity — the window edges are actually exercised: the
        // 63-days-back and 8-days-ahead sessions fall outside the 8-week
        // window in any timezone/weekday, the middle four fall inside.
        XCTAssertEqual(agg.sessionsPerWeek.reduce(0, +), 4)
        XCTAssertGreaterThan(agg.weeklyVolume.reduce(0, +), 0)
    }

    func test_sessionCountByWeekStart_matchesLegacyGroupingAndThisWeekFilter() {
        let now = Date()
        let sessions = fixtureSessions(now: now)
        let agg = makeAggregates(sessions: sessions, now: now)
        let cal = Calendar.current

        // The moved startOfWeek helper must group exactly like the old one.
        for s in sessions {
            XCTAssertEqual(ProgressAggregates.startOfWeek(for: s.startTime, calendar: cal),
                           legacyStartOfWeek(for: s.startTime, calendar: cal))
        }

        // Legacy currentWeeklyTargetStreak built this grouping per render.
        var legacyByWeek: [Date: Int] = [:]
        for s in sessions {
            legacyByWeek[legacyStartOfWeek(for: s.startTime, calendar: cal), default: 0] += 1
        }
        XCTAssertEqual(agg.sessionCountByWeekStart, legacyByWeek)

        // THIS WEEK was `savedSessions.filter { $0.startTime >= weekStart }
        // .count`; the stat now sums the cached grouping over keys >=
        // weekStart. Same count required.
        let weekStart = legacyStartOfWeek(for: now, calendar: cal)
        let legacyThisWeek = sessions.filter { $0.startTime >= weekStart }.count
        let newThisWeek = agg.sessionCountByWeekStart.reduce(0) { $0 + ($1.key >= weekStart ? $1.value : 0) }
        XCTAssertEqual(newThisWeek, legacyThisWeek)
    }

    // MARK: - (2) topExerciseSeries ordering / ranking / series content

    func test_topExercises_matchLegacyOrderingRankingAndSeries() {
        let now = Date()
        let store = freshStore()
        store.saveAll(fixtureSessions(now: now))
        let sessions = store.savedSessions
        let prs = store.allPersonalRecords()

        // limit 2 with 3 weighted exercises (bench 12 / squat 6 / row 1
        // completed working sets) characterizes the prefix(limit) cut and
        // the set-count ranking; distinct counts keep the sort total.
        let agg = makeAggregates(sessions: sessions, personalRecords: prs,
                                 topExerciseCount: 2, now: now)
        let legacy = legacyTopExerciseSeries(sessions: sessions, personalRecords: prs, limit: 2)

        XCTAssertEqual(agg.topExercises.count, legacy.count)
        XCTAssertEqual(agg.topExercises.map(\.name), legacy.map(\.name))
        XCTAssertEqual(agg.topExercises.map(\.name),
                       ["Barbell Bench Press", "Barbell Back Squat"],
                       "Ranking is by completed working-set count, desc")

        for (new, old) in zip(agg.topExercises, legacy) {
            XCTAssertEqual(new.unit, old.unit)
            XCTAssertEqual(new.latest, old.latest)
            XCTAssertEqual(new.lastPRDate, old.lastPRDate)
            XCTAssertEqual(new.points.map(\.date), old.points.map(\.0))
            XCTAssertEqual(new.points.map(\.weight), old.points.map(\.1))
        }

        // Warmup pin: the 24-days-back session's bench best is the 145
        // working set, never the 999 warmup.
        guard let bench = agg.topExercises.first else {
            return XCTFail("Expected a top-exercise series for the bench fixture")
        }
        XCTAssertEqual(bench.points.map(\.weight).max(), 165,
                       "Best-ever bench point comes from working sets only")
        XCTAssertFalse(bench.points.map(\.weight).contains(999))
        XCTAssertNotNil(bench.lastPRDate, "Fixture sanity — bench has PR events")
    }

    // MARK: - (3) personalRecords pass-through + filtering

    func test_personalRecords_passThroughAndFiltersUnchanged() {
        let now = Date()
        let store = freshStore()
        store.saveAll(fixtureSessions(now: now))
        let direct = store.allPersonalRecords()
        let agg = makeAggregates(sessions: store.savedSessions,
                                 personalRecords: direct, now: now)

        // The PR feed used store.allPersonalRecords() inline; the aggregate
        // carries the same list through unchanged.
        XCTAssertEqual(agg.personalRecords, direct)
        XCTAssertFalse(direct.isEmpty, "Fixture sanity — progressing bench produces PR events")

        // PR feed prefix(10) over the cached list == over the direct list.
        XCTAssertEqual(Array(agg.personalRecords.prefix(10)), Array(direct.prefix(10)))

        // PRs·30d stat: legacy filtered the fresh allPersonalRecords();
        // the stat now filters the cached list with the same cutoff.
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        XCTAssertEqual(agg.personalRecords.filter { $0.date >= cutoff }.count,
                       direct.filter { $0.date >= cutoff }.count)
    }

    // MARK: - (4) StrengthStandards.rows / MuscleVolume.rows outputs

    func test_strengthRows_matchDirectStrengthStandardsCall() {
        let now = Date()
        let sessions = fixtureSessions(now: now)
        let bw = BodyMetrics.lbToKg(180)

        // Old card: StrengthStandards.rows(from: store.savedSessions,
        // bodyweightKg: memory.weightKg, gender: memory.gender) per render.
        let agg = makeAggregates(sessions: sessions, bodyweightKg: bw, gender: .male, now: now)
        let direct = StrengthStandards.rows(from: sessions, bodyweightKg: bw, gender: .male)
        XCTAssertEqual(agg.strengthRows, direct)
        XCTAssertEqual(Set(direct.map(\.lift)), [.bench, .squat],
                       "Fixture sanity — both canonical lifts produce rows (non-vacuous)")

        // Without bodyweight the old call returned [] (card hid itself).
        XCTAssertTrue(makeAggregates(sessions: sessions, bodyweightKg: nil,
                                     gender: .male, now: now).strengthRows.isEmpty)
    }

    func test_muscleRows_matchDirectMuscleVolumeCall() {
        let now = Date()
        let sessions = fixtureSessions(now: now)

        // Old card: MuscleVolume.rows(from: store.savedSessions) per render
        // (defaults: weeks 4, limit 8, default coach.db resolver, now =
        // Date()). The aggregate pins `now` but is otherwise the same call.
        let agg = makeAggregates(sessions: sessions, now: now)
        let direct = MuscleVolume.rows(from: sessions, now: now)
        // MuscleVolume.rows sorts by volume only (MuscleVolume.swift:89), so
        // EQUAL-volume rows land in dictionary-iteration order — legacy code
        // itself isn't call-to-call stable for ties. Normalize ties by slug
        // before comparing; content and volume ordering are what's pinned.
        func tieStable(_ rows: [MuscleVolume.Row]) -> [MuscleVolume.Row] {
            rows.sorted { $0.volume == $1.volume ? $0.slug < $1.slug : $0.volume > $1.volume }
        }
        XCTAssertEqual(tieStable(agg.muscleRows), tieStable(direct))

        // Non-vacuous: the fixture lifts resolve in the bundled coach.db.
        XCTAssertNotNil(MuscleVolume.defaultResolve("Barbell Bench Press"))
        XCTAssertFalse(direct.isEmpty,
                       "Fixture sanity — resolvable lifts inside the 4-week window")
    }

    // MARK: - Recent sessions (sort + prefix preserved)

    func test_recentSessions_matchLegacySortAndPrefix() {
        let now = Date()
        let sessions = fixtureSessions(now: now)

        // Old card: savedSessions.sorted { $0.endTime > $1.endTime }
        // .prefix(recentSessionsPreview). Fixture endTimes are distinct so
        // the sort is total.
        let agg = makeAggregates(sessions: sessions, recentSessionsCount: 3, now: now)
        let legacy = Array(sessions.sorted { $0.endTime > $1.endTime }.prefix(3))
        XCTAssertEqual(agg.recentSessions, legacy)
        XCTAssertEqual(agg.recentSessions.count, 3)
    }

    // MARK: - Memo behavior (item 8 hazard: stale cache)

    @MainActor
    func test_cache_servesMemoizedValueAndRecomputesOnInputChange() {
        let now = Date()
        var sessions = fixtureSessions(now: now)
        let cache = ProgressAggregatesCache()
        var prReplays = 0

        func read(_ s: [SavedSession], bodyweightKg: Double? = nil) -> ProgressAggregates {
            cache.aggregates(
                sessions: s,
                bodyweightKg: bodyweightKg,
                gender: nil,
                weeks: 8,
                topExerciseCount: 6,
                recentSessionsCount: 5,
                personalRecords: { prReplays += 1; return [] },
                now: now
            )
        }

        let first = read(sessions)
        XCTAssertEqual(prReplays, 1)

        // Key hit: identical inputs must not replay the SQL-backed PR walk
        // and must serve identical aggregates.
        let second = read(sessions)
        XCTAssertEqual(prReplays, 1, "Cache hit must skip recomputation")
        XCTAssertEqual(second.totalSessions, first.totalSessions)
        XCTAssertEqual(second.sessionsPerWeek, first.sessionsPerWeek)
        XCTAssertEqual(second.weeklyVolume, first.weeklyVolume)

        // Stale-cache hazard (report §10.d): finishing a workout reassigns
        // savedSessions — the next read must miss the key and recompute.
        sessions.append(savedSession(offsetDays: 0, exercises: [
            loggedExercise(name: "Barbell Back Squat", sets: [("245", "5", true, false)]),
        ], now: now))
        let third = read(sessions)
        XCTAssertEqual(prReplays, 2, "Changed sessions must invalidate the memo")
        XCTAssertEqual(third.totalSessions, first.totalSessions + 1)

        // bodyweight is part of the key (strengthRows depend on it).
        let fourth = read(sessions, bodyweightKg: BodyMetrics.lbToKg(180))
        XCTAssertEqual(prReplays, 3, "Changed bodyweight must invalidate the memo")
        XCTAssertFalse(fourth.strengthRows.isEmpty)
        XCTAssertTrue(third.strengthRows.isEmpty, "No bodyweight → no strength rows")
    }
}
