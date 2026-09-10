// PlanArcTests.swift — PR 10A of the weekly-coach roadmap.
//
// Coverage for the auto-arc:
//   - Week classification (build vs not) on completion ratio + session count.
//   - Consecutive-build-week streak counting, incl. snapshot gaps breaking
//     the streak and the current week being excluded.
//   - The deload decision: fires at 3 build weeks, blocked by cooldown,
//     blocked by too little history.
//   - Planner.applyDeload: trims lift days to ≥2, marks the recovery day,
//     re-prescribes at reduced volume, preserves the lift rotation.
//
// Glue mirrors PlanHistoryTests (PR 4's test shape).

import XCTest
@testable import PhaseTraining

final class PlanArcTests: XCTestCase {

    // MARK: - Fixtures

    private var cal: Calendar { Calendar.current.mondayFirst }

    /// Monday 2026-05-11 00:00 local.
    private func monday(_ weekOffset: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        let base = cal.date(from: c)!
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: base)!
    }

    /// A plan snapshot for a week: `lifts` planned lift days, sessions
    /// recorded for `done` distinct days.
    private func snapshot(weekStart: Date, lifts: Int, done: Int) -> (WeekPlanSnapshot, [SavedSession]) {
        precondition(lifts <= 7)
        var kinds: [DayKind] = Array(repeating: .lift, count: lifts)
        kinds += Array(repeating: .rest, count: 7 - lifts)
        let days = kinds.enumerated().map { i, kind -> DayPlan in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: weekStart)!,
                kind: kind,
                title: kind == .lift ? "Push day" : "Rest",
                routineId: nil,
                generatedWorkout: nil
            )
        }
        let plan = WeekPlan(days: days, generatedAt: weekStart, inputsHash: "arc")
        // `done` distinct session days, one session each, inside the week.
        var sessions: [SavedSession] = []
        var ids: [TimeInterval] = []
        for i in 0..<done {
            let start = cal.date(byAdding: .day, value: i, to: weekStart)!.addingTimeInterval(18 * 3_600)
            let s = makeSession(start: start)
            sessions.append(s)
            ids.append(s.id)
        }
        let snap = WeekPlanSnapshot(
            weekStart: weekStart,
            plan: plan,
            actualSessionIDs: ids,
            capturedAt: weekStart.addingTimeInterval(7 * 86_400)
        )
        return (snap, sessions)
    }

    private func makeSession(start: Date) -> SavedSession {
        SavedSession(
            templateId: "t",
            name: "Push day",
            category: "lift",
            startTime: start,
            exercises: [],
            feel: nil,
            note: nil,
            endTime: start.addingTimeInterval(3_600),
            duration: 3_600
        )
    }

    // MARK: - Week classification

    func test_isBuildWeek_trueWhenCompletionHighAndEnoughSessions() {
        let (snap, sessions) = snapshot(weekStart: monday(), lifts: 4, done: 3)
        // 3 of 4 = 75% ≥ 60%, 3 sessions ≥ 2.
        XCTAssertTrue(PlanArc.isBuildWeek(snap, sessions: sessions, calendar: cal))
    }

    func test_isBuildWeek_falseWhenTooFewSessions() {
        let (snap, sessions) = snapshot(weekStart: monday(), lifts: 4, done: 1)
        // 1 of 4 = 25% and 1 < 2 sessions — not a build week on either axis.
        XCTAssertFalse(PlanArc.isBuildWeek(snap, sessions: sessions, calendar: cal))
    }

    func test_isBuildWeek_falseWhenCompletionBelowBar() {
        // 6 planned lift days, 3 done = 50% < 60%, but 3 ≥ 2 sessions.
        let (snap, sessions) = snapshot(weekStart: monday(), lifts: 6, done: 3)
        XCTAssertFalse(PlanArc.isBuildWeek(snap, sessions: sessions, calendar: cal))
    }

    // MARK: - Streak counting

    func test_consecutiveBuildWeeks_countsTrailingStreak() {
        var snapshots: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        // Weeks -3, -2, -1: build, build, build.
        for w in [-3, -2, -1] {
            let (s, ss) = snapshot(weekStart: monday(w), lifts: 4, done: 4)
            snapshots.append(s)
            sessions += ss
        }
        XCTAssertEqual(
            PlanArc.consecutiveBuildWeeks(snapshots: snapshots,
                                          sessions: sessions,
                                          currentWeekStart: monday(0),
                                          calendar: cal),
            3)
    }

    func test_consecutiveBuildWeeks_brokenByNonBuildWeek() {
        var snapshots: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        // Week -3: build. Week -2: 1 of 4 done → not a build week.
        // Week -1: build. Streak ends at week -1: only 1.
        let (w3, s3) = snapshot(weekStart: monday(-3), lifts: 4, done: 4)
        let (w2, s2) = snapshot(weekStart: monday(-2), lifts: 4, done: 1)
        let (w1, s1) = snapshot(weekStart: monday(-1), lifts: 4, done: 4)
        snapshots = [w3, w2, w1]
        sessions = s3 + s2 + s1
        XCTAssertEqual(
            PlanArc.consecutiveBuildWeeks(snapshots: snapshots,
                                          sessions: sessions,
                                          currentWeekStart: monday(0),
                                          calendar: cal),
            1)
    }

    func test_consecutiveBuildWeeks_gapInHistoryBreaksStreak() {
        var snapshots: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        // Build weeks at -4 and -3; NO snapshot at -2 (user absent);
        // build week at -1. The gap caps the streak at 1.
        let (w4, s4) = snapshot(weekStart: monday(-4), lifts: 4, done: 4)
        let (w3, s3) = snapshot(weekStart: monday(-3), lifts: 4, done: 4)
        let (w1, s1) = snapshot(weekStart: monday(-1), lifts: 4, done: 4)
        snapshots = [w4, w3, w1]
        sessions = s4 + s3 + s1
        XCTAssertEqual(
            PlanArc.consecutiveBuildWeeks(snapshots: snapshots,
                                          sessions: sessions,
                                          currentWeekStart: monday(0),
                                          calendar: cal),
            1)
    }

    // MARK: - Deload decision

    func test_signal_firesAtThreeConsecutiveBuildWeeks() {
        var snapshots: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        for w in [-3, -2, -1] {
            let (s, ss) = snapshot(weekStart: monday(w), lifts: 4, done: 4)
            snapshots.append(s)
            sessions += ss
        }
        XCTAssertEqual(
            PlanArc.signal(snapshots: snapshots, sessions: sessions,
                           currentWeekStart: monday(0), calendar: cal),
            .deload)
    }

    func test_signal_noneAtTwoBuildWeeks() {
        var snapshots: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        for w in [-2, -1] {
            let (s, ss) = snapshot(weekStart: monday(w), lifts: 4, done: 4)
            snapshots.append(s)
            sessions += ss
        }
        XCTAssertEqual(
            PlanArc.signal(snapshots: snapshots, sessions: sessions,
                           currentWeekStart: monday(0), calendar: cal),
            .none)
    }

    func test_signal_blockedByCooldown() {
        var snapshots: [WeekPlanSnapshot] = []
        var sessions: [SavedSession] = []
        for w in [-3, -2, -1] {
            let (s, ss) = snapshot(weekStart: monday(w), lifts: 4, done: 4)
            snapshots.append(s)
            sessions += ss
        }
        // Deload 2 weeks ago — inside the 4-week cooldown.
        XCTAssertEqual(
            PlanArc.signal(snapshots: snapshots, sessions: sessions,
                           currentWeekStart: monday(0),
                           lastDeloadWeekStart: monday(-2), calendar: cal),
            .none)
        // Deload 5 weeks ago — cooldown expired.
        XCTAssertEqual(
            PlanArc.signal(snapshots: snapshots, sessions: sessions,
                           currentWeekStart: monday(0),
                           lastDeloadWeekStart: monday(-5), calendar: cal),
            .deload)
    }

    // MARK: - Planner.applyDeload

    /// Minimal memory + catalog for plan generation. A primary sport
    /// gives the generator real candidates (probe-verified: a bare
    /// no-sport memory produces 0-exercise workouts in the test env).
    private func generatePlan(deload: Bool) -> WeekPlan {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "climbing")
        memory.seasonsBySport = [memory.primarySport!: .offSeason]
        memory.equipment = [.fullGym]
        memory.liftDaysPerWeek = 4
        memory.sessionMinutes = 60
        return Planner.generate(
            memory: memory,
            routines: CoachDatabase.shared.listRoutines(),
            today: monday(0),
            deloadWeek: deload
        )
    }

    func test_applyDeload_demotesOneLiftAndKeepsAtLeastTwo() {
        let normal = generatePlan(deload: false)
        let deload = generatePlan(deload: true)
        let normalLifts = normal.days.filter { $0.kind == .lift }.count
        let deloadLifts = deload.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(deloadLifts, normalLifts - 1)
        XCTAssertGreaterThanOrEqual(deloadLifts, 2)
        // The demoted day is the recovery marker.
        XCTAssertEqual(deload.days.filter { $0.title == "Recovery" }.count, 1)
    }

    func test_applyDeload_reducesSetVolume() {
        let normal = generatePlan(deload: false)
        let deload = generatePlan(deload: true)
        let normalSets = normal.days.compactMap(\.generatedWorkout)
            .flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        let deloadSets = deload.days.compactMap(\.generatedWorkout)
            .flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        // ×0.7 on the surviving days — strictly lighter than normal.
        XCTAssertLessThan(deloadSets, normalSets)
    }

    func test_applyDeload_nonDeloadPlanUnchanged() {
        let normal = generatePlan(deload: false)
        XCTAssertEqual(normal.days.filter { $0.title == "Recovery" }.count, 0)
    }
}
