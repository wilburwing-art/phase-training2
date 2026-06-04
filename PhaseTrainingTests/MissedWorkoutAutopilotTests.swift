// MissedWorkoutAutopilotTests.swift — PR 8 of the weekly-coach roadmap.
//
// Pure-logic coverage for the detection + reshuffle engine. The
// PlanStore-glue tests live in PlanStoreMissedWorkoutTests; those
// exercise the persistence + counter + idempotency paths.

import XCTest
@testable import PhaseTraining

final class MissedWorkoutAutopilotTests: XCTestCase {

    // MARK: - Helpers

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11   // Monday
        return Calendar.current.date(from: c)!
    }

    /// Build a 7-day plan with the given kinds. Optional explicit titles
    /// per day for the reshuffle target tests.
    private func plan(_ kinds: [DayKind], titles: [String]? = nil) -> WeekPlan {
        precondition(kinds.count == 7)
        let cal = Calendar.current
        let start = monday()
        let days = (0..<7).map { i -> DayPlan in
            let kind = kinds[i]
            let title = titles?[i] ?? (kind == .lift ? "Push day" :
                                        kind == .sport ? "Climb" :
                                        kind == .rest ? "Rest" : "Event")
            return DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                kind: kind, title: title, routineId: nil,
                generatedWorkout: kind == .lift ? GeneratedWorkout(
                    title: title, summary: "", exercises: [],
                    estimatedMinutes: 60, provenance: "") : nil
            )
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    private func session(on date: Date) -> SavedSession {
        SavedSession(
            templateId: "t", name: "Workout", category: "",
            startTime: date, exercises: [], feel: nil, note: nil,
            endTime: date.addingTimeInterval(3600), duration: 3600
        )
    }

    // MARK: - Detection

    func test_detect_findsPastUnloggedLiftDay() {
        // Tue is a lift day, today is Wed → Tue is missed
        let p = plan([.rest, .lift, .rest, .lift, .rest, .rest, .rest])
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let missed = MissedWorkoutAutopilot.detect(
            plan: p, sessions: [], overrides: WeekOverrides(weekStart: monday()),
            now: wed
        )
        XCTAssertEqual(missed.count, 1)
        XCTAssertEqual(missed[0].kind, .lift)
    }

    func test_detect_skipsTodayAndFuture() {
        // Today=Wed; future lift on Fri shouldn't count as missed yet.
        let p = plan([.rest, .rest, .lift, .rest, .lift, .rest, .rest])
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let missed = MissedWorkoutAutopilot.detect(
            plan: p, sessions: [], overrides: WeekOverrides(weekStart: monday()),
            now: wed
        )
        // Wed lift is today — not strictly past — so 0 missed.
        XCTAssertEqual(missed.count, 0)
    }

    func test_detect_skipsCompletedSessions() {
        // Tue lift, but the user did log a session on Tue → not missed
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let missed = MissedWorkoutAutopilot.detect(
            plan: p, sessions: [session(on: tue)],
            overrides: WeekOverrides(weekStart: monday()), now: wed
        )
        XCTAssertEqual(missed.count, 0)
    }

    func test_detect_skipsUserRestOverride() {
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        var overrides = WeekOverrides(weekStart: monday())
        overrides.dayOverrides[tue] = .rest
        let missed = MissedWorkoutAutopilot.detect(
            plan: p, sessions: [], overrides: overrides, now: wed
        )
        XCTAssertEqual(missed.count, 0,
                       "explicit user rest override is intentional — not a miss")
    }

    func test_detect_skipsUnavailableWeekday() {
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        var overrides = WeekOverrides(weekStart: monday())
        overrides.unavailableDays.insert(.tuesday)
        let missed = MissedWorkoutAutopilot.detect(
            plan: p, sessions: [], overrides: overrides, now: wed
        )
        XCTAssertEqual(missed.count, 0)
    }

    func test_detect_restAndEventDaysNeverMiss() {
        // Past rest + past event days don't show up no matter what.
        let p = plan([.rest, .event, .rest, .rest, .rest, .rest, .rest])
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let missed = MissedWorkoutAutopilot.detect(
            plan: p, sessions: [], overrides: WeekOverrides(weekStart: monday()),
            now: wed
        )
        XCTAssertEqual(missed.count, 0)
    }

    // MARK: - Reshuffle

    func test_reshuffle_movesMissedLiftToFutureRest() {
        // Tue missed, Wed/Thu/Fri/Sat/Sun all rest → move to Wed
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: tue, plan: p, overrides: WeekOverrides(weekStart: monday()),
            remainingBudget: 2, now: wed
        )
        XCTAssertEqual(edits.count, 1)
        if case .move(_, let toDate) = edits[0] {
            XCTAssertTrue(Calendar.current.isDate(toDate, inSameDayAs: wed),
                          "first valid future rest day is the target")
        } else {
            XCTFail("expected .move edit, got \(edits[0])")
        }
    }

    func test_reshuffle_dropsAt4PlusLifts() {
        // 4 lifts already planned → don't crowd, drop the miss
        let p = plan([.lift, .lift, .lift, .lift, .rest, .rest, .rest])
        let mon = monday()
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: mon)!
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: mon, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: tue
        )
        XCTAssertEqual(edits.count, 0, "drop rule: ≥4 lift days/week → no reshuffle")
    }

    func test_reshuffle_skipsRestDayAfterHardDay() {
        // Mon missed (lift), Tue lift, Wed rest, Thu rest → Wed is
        // post-hard-day, must skip → target is Thu
        let p = plan([.lift, .lift, .rest, .rest, .rest, .rest, .rest])
        let mon = monday()
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        let thu = Calendar.current.date(byAdding: .day, value: 3, to: mon)!
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: mon, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: wed
        )
        guard case .move(_, let toDate) = edits.first else {
            XCTFail("expected a move edit"); return
        }
        XCTAssertFalse(Calendar.current.isDate(toDate, inSameDayAs: wed),
                       "Wed sits right after Tue lift → no stacking")
        XCTAssertTrue(Calendar.current.isDate(toDate, inSameDayAs: thu),
                      "Thu is the first valid non-stacked rest day")
    }

    func test_reshuffle_skipsUserLockedRest() {
        // Tue missed, Wed rest but user-locked → target is Thu instead
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let mon = monday()
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: mon)!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        let thu = Calendar.current.date(byAdding: .day, value: 3, to: mon)!
        var overrides = WeekOverrides(weekStart: mon)
        overrides.dayOverrides[wed] = .rest
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: tue, plan: p, overrides: overrides,
            remainingBudget: 2, now: wed
        )
        guard case .move(_, let toDate) = edits.first else {
            XCTFail("expected a move edit"); return
        }
        XCTAssertTrue(Calendar.current.isDate(toDate, inSameDayAs: thu))
    }

    func test_reshuffle_budgetZeroBlocksMove() {
        // Tue missed, plenty of rest days, but caller's budget is 0 → no edits
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let mon = monday()
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: mon)!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: tue, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 0, now: wed
        )
        XCTAssertEqual(edits.count, 0)
    }

    func test_reshuffle_returnsEmptyWhenNoFutureRestExists() {
        // Plan is all lift days the rest of the week → no rest target
        let p = plan([.lift, .rest, .lift, .lift, .lift, .lift, .lift])
        // Notably plannedLifts=6 → drop rule fires first
        // Use a plan with 3 lifts but all future days busy
        let p2 = plan([.rest, .lift, .lift, .sport, .lift, .sport, .sport])
        let mon = monday()
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        let edits = MissedWorkoutAutopilot.proposeReshuffle(
            missedDate: mon, plan: p2, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: wed
        )
        XCTAssertEqual(edits.count, 0, "no future rest days → no reshuffle")
        // Suppress unused-variable warning for p1 (kept for documentation)
        _ = p
    }

    // MARK: - Consolidation eligibility (D3 / Q4)

    func test_offerConsolidation_whenWeekFull() {
        // 4 lift days → drop rule fires (proposeReshuffle []), budget > 0,
        // missed day exists → consolidation eligible.
        let p = plan([.lift, .lift, .lift, .lift, .rest, .rest, .rest])
        let mon = monday()
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        XCTAssertTrue(MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: mon, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: wed))
    }

    func test_offerConsolidation_whenNoRestDay() {
        // <4 lifts but no rest day to host the missed workout.
        let p = plan([.lift, .sport, .sport, .sport, .sport, .sport, .sport])
        let mon = monday()
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        XCTAssertTrue(MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: mon, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: wed))
    }

    func test_noConsolidation_whenBudgetExhausted() {
        // Week-full would otherwise qualify, but the reshuffle budget is spent.
        let p = plan([.lift, .lift, .lift, .lift, .rest, .rest, .rest])
        let mon = monday()
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        XCTAssertFalse(MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: mon, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 0, now: wed))
    }

    func test_noConsolidation_whenCleanReshuffleSlotExists() {
        // Missed Tue with future rest days available → reshuffle handles it.
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let mon = monday()
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: mon)!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        XCTAssertFalse(MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: tue, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: wed))
    }

    func test_noConsolidation_whenMissedDayNotInPlan() {
        let p = plan([.rest, .lift, .rest, .rest, .rest, .rest, .rest])
        let mon = monday()
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: mon)!
        let farFuture = Calendar.current.date(byAdding: .day, value: 30, to: mon)!
        XCTAssertFalse(MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: farFuture, plan: p, overrides: WeekOverrides(weekStart: mon),
            remainingBudget: 2, now: wed))
    }
}
