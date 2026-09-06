// ProgressStatStripTests.swift — the Progress stat strip's render-time math.
//
// Covers ProgressStats (Data/ProgressStats.swift), extracted from the private
// helpers on ProgressScreen+StatCards.swift so `now` is injectable. Every
// case below pins its own week grid off a fixed `now`; nothing reads the
// real clock, so the suite is stable across a Monday-midnight run.
//
// `test_streak_graceWeek_*` is the assertion guarding a fixed bug: an
// in-progress week is normally short of target and must not zero a streak
// the user is still holding.

import XCTest
@testable import PhaseTraining

final class ProgressStatStripTests: XCTestCase {

    // MARK: - Fixtures

    /// A fixed instant mid-week so "this week" is unambiguous and the grace
    /// path is reachable: Wednesday 2026-03-11, 15:00 UTC.
    private let now: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 11; comps.hour = 15
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }()

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Monday-based start of the week `weeksAgo` weeks before `now`, using
    /// the same grouping the aggregates layer keys on.
    private func weekStart(_ weeksAgo: Int) -> Date {
        let thisWeek = ProgressAggregates.startOfWeek(for: now, calendar: calendar)
        return calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)!
    }

    /// `[weeksAgo: sessionCount]` → the `byWeek` grouping shape.
    private func byWeek(_ counts: [Int: Int]) -> [Date: Int] {
        counts.reduce(into: [Date: Int]()) { acc, pair in
            acc[weekStart(pair.key)] = pair.value
        }
    }

    private func streak(target: Int, _ counts: [Int: Int]) -> Int {
        ProgressStats.currentWeeklyTargetStreak(
            target: target,
            byWeek: byWeek(counts),
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Streak

    func test_streak_countsConsecutiveWeeksMeetingTarget() {
        // This week already met target, so counting starts here and runs
        // back through every week that also met it.
        XCTAssertEqual(streak(target: 3, [0: 3, 1: 4, 2: 3]), 3)
    }

    func test_streak_graceWeek_startsFromLastWeekWhenThisWeekShort() {
        // A week in progress is normally short of target. That must not
        // zero a streak the user is still holding — the cursor drops to
        // last week and counts from there.
        XCTAssertEqual(streak(target: 3, [0: 1, 1: 3, 2: 3]), 2)

        // Nothing logged yet this week is the same case.
        XCTAssertEqual(streak(target: 3, [1: 3, 2: 3]), 2)
    }

    func test_streak_gapWeekBreaksTheRun() {
        // Week 2 fell short, so the run is only weeks 0 and 1 — the older
        // qualifying weeks behind the gap don't rejoin it.
        XCTAssertEqual(streak(target: 2, [0: 2, 1: 2, 2: 1, 3: 5, 4: 5]), 2)
    }

    func test_streak_weekUnderTargetIsNotCounted() {
        // Grace moves the cursor back one week only. If last week also
        // missed, there is no streak to report.
        XCTAssertEqual(streak(target: 3, [0: 1, 1: 2]), 0)

        // A history that stops well before this week is stale, not a streak.
        XCTAssertEqual(streak(target: 2, [4: 5, 5: 5]), 0)
    }

    func test_streak_emptyHistory_isZero() {
        XCTAssertEqual(streak(target: 3, [:]), 0)
        XCTAssertEqual(streak(target: 1, [:]), 0)
    }

    func test_streak_targetOfOne_countsAnyLoggedWeek() {
        // liftDaysPerWeek is clamped to >= 1 at the call site, so target 1
        // is the floor the card can ask for.
        XCTAssertEqual(streak(target: 1, [0: 1, 1: 1, 2: 1]), 3)
        // A zero-session week still breaks it, even at target 1.
        XCTAssertEqual(streak(target: 1, [0: 1, 1: 0, 2: 1]), 1)
    }

    func test_streak_terminatesWhenEveryKnownWeekMeetsTarget() {
        // A long unbroken run counts every qualifying week and stops at the
        // oldest one present. This does not reproduce the original hang
        // (that needed date arithmetic to return nil, which the `guard let
        // prev` now catches), but it does pin the walk's termination and its
        // count over a history where the target check never fails.
        let counts = Dictionary(uniqueKeysWithValues: (0...25).map { ($0, 5) })
        XCTAssertEqual(streak(target: 2, counts), 26)
    }

    // MARK: - This week

    func test_thisWeekCount_sumsWeeksAtOrAfterThisWeekStart() {
        let counts = byWeek([0: 2, 1: 4, 3: 1])
        XCTAssertEqual(
            ProgressStats.sessionsThisWeekCount(byWeek: counts, now: now, calendar: calendar),
            2
        )
    }

    func test_thisWeekCount_includesFutureDatedSessions() {
        // The old card filtered `startTime >= weekStart`, which swept in a
        // future-dated session; summing keys >= thisWeekStart preserves that.
        var counts = byWeek([0: 2, 1: 4])
        counts[calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart(0))!] = 3
        XCTAssertEqual(
            ProgressStats.sessionsThisWeekCount(byWeek: counts, now: now, calendar: calendar),
            5
        )
    }

    func test_thisWeekCount_emptyHistoryIsZero() {
        XCTAssertEqual(
            ProgressStats.sessionsThisWeekCount(byWeek: [:], now: now, calendar: calendar),
            0
        )
    }

    // MARK: - PRs · 30d

    func test_prsInLastDays_filtersOnCutoff() {
        let records = [
            pr(daysAgo: 0),
            pr(daysAgo: 29),
            pr(daysAgo: 31),
            pr(daysAgo: 120),
        ]
        XCTAssertEqual(
            ProgressStats.prsInLastDays(30, in: records, now: now, calendar: calendar),
            2
        )
    }

    func test_prsInLastDays_cutoffIsInclusive() {
        // Exactly 30 days back lands on the cutoff instant and counts.
        let records = [pr(daysAgo: 30)]
        XCTAssertEqual(
            ProgressStats.prsInLastDays(30, in: records, now: now, calendar: calendar),
            1
        )
    }

    func test_prsInLastDays_emptyRecordsIsZero() {
        XCTAssertEqual(
            ProgressStats.prsInLastDays(30, in: [], now: now, calendar: calendar),
            0
        )
    }

    private func pr(daysAgo: Int) -> PersonalRecord {
        PersonalRecord(
            exerciseName: "Barbell Bench Press",
            reps: 5,
            weight: 185,
            previousBest: 180,
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        )
    }
}
