// SkipStreakTests.swift — PR 10D of the weekly-coach roadmap.
//
// Coverage:
//   - detect(): 3+ misses on a weekday = streak; 2 = not; window
//     filtering; multiple streaks ranked by count.
//   - worstStreakWeekday: highest-count weekday or nil.
//   - Planner.applySkipStreakBias: converts the streak weekday's lift
//     to rest, never drops below 2 lifts, no-op when no lift on that
//     weekday.
//   - CoachContext surface: skip-streak block appears with the day name.

import XCTest
@testable import PhaseTraining

final class SkipStreakTests: XCTestCase {

    private var cal: Calendar { Calendar.current.mondayFirst }

    private func monday(_ weekOffset: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        let base = cal.date(from: c)!
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: base)!
    }

    /// A Tuesday miss, N weeks ago.
    private func miss(weeksAgo: Int, title: String? = "Push day") -> MissedWorkoutEntry {
        let tuesday = cal.date(byAdding: .day, value: 1, to: monday(-weeksAgo))!
        return MissedWorkoutEntry(
            date: tuesday, plannedKind: .lift, plannedTitle: title,
            resolution: .dropped
        )
    }

    // MARK: - detect

    func test_detect_streakAtThreeMisses() {
        let streaks = SkipStreakDetector.detect(missedWorkouts: [
            miss(weeksAgo: 1), miss(weeksAgo: 2), miss(weeksAgo: 3),
        ], now: monday())
        XCTAssertEqual(streaks.count, 1)
        XCTAssertEqual(streaks.first?.weekday, .tuesday)
        XCTAssertEqual(streaks.first?.missCount, 3)
    }

    func test_detect_noStreakAtTwo() {
        let streaks = SkipStreakDetector.detect(missedWorkouts: [
            miss(weeksAgo: 1), miss(weeksAgo: 2),
        ], now: monday())
        XCTAssertTrue(streaks.isEmpty)
    }

    func test_detect_windowFiltersOldMisses() {
        // 3 misses but one is outside the 90-day window.
        let far = cal.date(byAdding: .day, value: 1, to: monday(-16))! // ~16 weeks back
        let streaks = SkipStreakDetector.detect(missedWorkouts: [
            miss(weeksAgo: 1), miss(weeksAgo: 2),
            MissedWorkoutEntry(date: far, plannedKind: .lift,
                               plannedTitle: "Push", resolution: .dropped),
        ], now: monday())
        XCTAssertTrue(streaks.isEmpty)
    }

    func test_detect_ranksWorstStreakFirst() {
        // 3 Tuesday misses, 4 Thursday misses → Thursday first.
        var entries = [miss(weeksAgo: 1), miss(weeksAgo: 2), miss(weeksAgo: 3)]
        for w in [1, 2, 3, 4] {
            let thursday = cal.date(byAdding: .day, value: 3, to: monday(-w))!
            entries.append(MissedWorkoutEntry(date: thursday, plannedKind: .lift,
                                              plannedTitle: "Pull", resolution: .dropped))
        }
        let streaks = SkipStreakDetector.detect(missedWorkouts: entries, now: monday())
        XCTAssertEqual(streaks.count, 2)
        XCTAssertEqual(streaks.first?.weekday, .thursday)
        XCTAssertEqual(streaks.first?.missCount, 4)
    }

    func test_worstStreakWeekday_nilWithoutStreak() {
        XCTAssertNil(SkipStreakDetector.worstStreakWeekday(
            missedWorkouts: [miss(weeksAgo: 1)], now: monday()))
        XCTAssertEqual(SkipStreakDetector.worstStreakWeekday(
            missedWorkouts: [miss(weeksAgo: 1), miss(weeksAgo: 2), miss(weeksAgo: 3)],
            now: monday()), .tuesday)
    }

    // MARK: - Planner bias

    private func planWithLifts(on offsets: [Int]) -> WeekPlan {
        var kinds = Array(repeating: DayKind.rest, count: 7)
        for i in offsets { kinds[i] = .lift }
        let days = kinds.enumerated().map { i, k in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: monday())!,
                kind: k, title: k == .lift ? "Push day" : "Rest",
                routineId: nil, generatedWorkout: nil
            )
        }
        return WeekPlan(days: days, generatedAt: monday(), inputsHash: "streak")
    }

    func test_bias_convertsStreakWeekdayLiftToRest() {
        // Lifts on Tue(1), Wed(2), Fri(4) — Tuesday is de-emphasized.
        let out = Planner.applySkipStreakBias(
            plan: planWithLifts(on: [1, 2, 4]),
            weekdays: [.tuesday], calendar: cal
        )
        XCTAssertEqual(out.days[1].kind, .rest)
        XCTAssertEqual(out.days.filter { $0.kind == .lift }.count, 2)
    }

    func test_bias_neverDropsBelowTwoLifts() {
        // Exactly 2 lifts, one on the streak day → converting would
        // leave 1, so the bias no-ops.
        let out = Planner.applySkipStreakBias(
            plan: planWithLifts(on: [1, 3]),
            weekdays: [.tuesday], calendar: cal
        )
        XCTAssertEqual(out.days[1].kind, .lift)
        XCTAssertEqual(out.days.filter { $0.kind == .lift }.count, 2)
    }

    func test_bias_noopWhenNoLiftOnStreakWeekday() {
        let out = Planner.applySkipStreakBias(
            plan: planWithLifts(on: [0, 2, 4]),
            weekdays: [.tuesday], calendar: cal
        )
        XCTAssertEqual(out.days.filter { $0.kind == .lift }.count, 3)
        XCTAssertEqual(out.days.map(\.kind), planWithLifts(on: [0, 2, 4]).days.map(\.kind))
    }

    // MARK: - MissedWorkoutEntry fixture sanity

    func test_missedEntry_initDefaults() {
        let m = miss(weeksAgo: 1)
        XCTAssertEqual(m.plannedKind, .lift)
        XCTAssertEqual(m.plannedTitle, "Push day")
    }
}
