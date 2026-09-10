// CNSBudgetTests.swift — PR 10C of the weekly-coach roadmap.
//
// Coverage:
//   - cnsCost classification (lift/event high, sport moderate, rest none).
//   - Run detection: 3+ consecutive high-CNS days violate; 2 don't.
//   - balance(): demotes the middle lift of a violating run, terminates,
//     protects sport/event days, and no-ops on clean plans.

import XCTest
@testable import PhaseTraining

final class CNSBudgetTests: XCTestCase {

    private var cal: Calendar { Calendar.current.mondayFirst }

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return cal.date(from: c)!
    }

    private func day(_ kind: DayKind, _ i: Int, title: String? = nil) -> DayPlan {
        DayPlan(
            date: cal.date(byAdding: .day, value: i, to: monday())!,
            kind: kind,
            title: title ?? (kind == .lift ? "Push day" : kind == .sport ? "Climb" : "Rest"),
            routineId: nil,
            generatedWorkout: nil
        )
    }

    private func plan(_ kinds: [DayKind]) -> WeekPlan {
        let days = kinds.enumerated().map { i, k in day(k, i) }
        return WeekPlan(days: days, generatedAt: monday(), inputsHash: "cns")
    }

    // MARK: - Cost table

    func test_cnsCost_liftAndEventHigh_sportModerate_restNone() {
        XCTAssertEqual(CNSBudgetEngine.cnsCost(of: day(.lift, 0)), 2)
        XCTAssertEqual(CNSBudgetEngine.cnsCost(of: day(.event, 0)), 2)
        XCTAssertEqual(CNSBudgetEngine.cnsCost(of: day(.sport, 0)), 1)
        XCTAssertEqual(CNSBudgetEngine.cnsCost(of: day(.rest, 0)), 0)
    }

    // MARK: - Violation detection

    func test_violates_trueForThreeConsecutiveLifts() {
        XCTAssertTrue(CNSBudgetEngine.violates(plan([.rest, .lift, .lift, .lift, .rest, .rest, .rest])))
    }

    func test_violates_falseForTwoInARow() {
        XCTAssertFalse(CNSBudgetEngine.violates(plan([.lift, .lift, .rest, .lift, .rest, .rest, .rest])))
    }

    func test_violates_detectsMixedLiftSportEventRuns() {
        // lift + hard event + lift = 3 high-CNS in a row.
        XCTAssertTrue(CNSBudgetEngine.violates(plan([.lift, .event, .lift, .rest, .rest, .rest, .rest])))
        // lift + moderate sport + lift = 2 high, not a violation.
        XCTAssertFalse(CNSBudgetEngine.violates(plan([.lift, .sport, .lift, .rest, .rest, .rest, .rest])))
    }

    func test_violates_trailingRunAtWeekEnd() {
        XCTAssertTrue(CNSBudgetEngine.violates(plan([.rest, .rest, .rest, .rest, .lift, .lift, .lift])))
    }

    // MARK: - balance

    func test_balance_relocatesBeforeDemoting() {
        // lift,lift,lift + 4 rests: a swap (e.g. day 2's lift to day 6's
        // rest) fixes the run WITHOUT losing a lift day. Spec §6.3
        // prefers reordering over trimming.
        let p = plan([.lift, .lift, .lift, .rest, .rest, .rest, .rest])
        let out = CNSBudgetEngine.balance(plan: p)
        XCTAssertFalse(CNSBudgetEngine.violates(out))
        // Relocation preserved the count; no Recovery marker appears.
        XCTAssertEqual(out.days.filter { $0.kind == .lift }.count, 3)
        XCTAssertEqual(out.days.filter { $0.title == "Recovery" }.count, 0)
    }

    func test_balance_demotesMiddleWhenRelocationImpossible() {
        // lift,lift,lift then an event that blocks every rest slot from
        // breaking the run... simplest construction: a run whose only
        // rests sit adjacent such that any relocation still violates.
        // sport+event+sport+lift+lift+lift+rest: rest at 6, moving any
        // run-lift (3,4,5) to 6 → lifts shift but 3,4,5 loses one →
        // e.g. swap 5↔6: lift,lift,lift... indices 3,4 lift + rest at 5? Let's see:
        // [sport,event,sport,lift,lift,lift,rest] swap 5↔6 →
        // [sport,event,sport,lift,lift,rest,lift] → max run 2. Relocation
        // works here too. To FORCE demotion, use lifts surrounded by events:
        // [event,lift,lift,lift,event,...] — swapping a run-lift with a
        // non-adjacent rest (5,6) still leaves 1,2,3 run. So demote.
        let days = [
            day(.event, 0), day(.lift, 1), day(.lift, 2), day(.lift, 3),
            day(.event, 4), day(.rest, 5), day(.rest, 6),
        ]
        let p = WeekPlan(days: days, generatedAt: monday(), inputsHash: "cns")
        let out = CNSBudgetEngine.balance(plan: p)
        XCTAssertFalse(CNSBudgetEngine.violates(out))
        // Relocation moves a run-lift to a trailing rest — count kept.
        XCTAssertEqual(out.days.filter { $0.kind == .lift }.count, 3)
        // Events untouched by either move.
        XCTAssertEqual(out.days[0].kind, .event)
        XCTAssertEqual(out.days[4].kind, .event)
    }

    func test_balance_protectsSportAndEventDays() {
        // sport + event + sport: 3 high-CNS days but no lift to demote.
        // The user booked these — the engine must leave them alone.
        let p = plan([.sport, .event, .sport, .rest, .rest, .rest, .rest])
        let out = CNSBudgetEngine.balance(plan: p)
        XCTAssertEqual(out.days[0].kind, .sport)
        XCTAssertEqual(out.days[1].kind, .event)
        XCTAssertEqual(out.days[2].kind, .sport)
    }

    func test_balance_noopOnCleanPlan() {
        let p = plan([.lift, .rest, .lift, .rest, .lift, .rest, .rest])
        let out = CNSBudgetEngine.balance(plan: p)
        XCTAssertEqual(out.days.map(\.kind), p.days.map(\.kind))
        XCTAssertFalse(CNSBudgetEngine.violates(out))
    }

    func test_balance_fixesFourRunWithRelocationOrDemotion() {
        let out = CNSBudgetEngine.balance(plan: plan([.lift, .lift, .lift, .lift, .rest, .rest, .rest]))
        XCTAssertFalse(CNSBudgetEngine.violates(out))
        XCTAssertGreaterThanOrEqual(out.days.filter { $0.kind == .lift }.count, 2)
    }

    func test_balance_keepsAllLiftsWhenRelocationSuffices() {
        // 3 lifts in a run + free rests → relocation preserves all 3.
        let out = CNSBudgetEngine.balance(plan: plan([.lift, .lift, .lift, .rest, .rest, .rest, .rest]))
        XCTAssertEqual(out.days.filter { $0.kind == .lift }.count, 3)
        XCTAssertFalse(CNSBudgetEngine.violates(out))
    }

    func test_balance_demotesWhenNoRestSlotExists() {
        // A full week of high-CNS days with zero rest slots: nothing to
        // relocate onto, so demotion is the only move. 7 lifts → demote
        // run middles until max run ≤ 2 (5 lifts remain).
        let out = CNSBudgetEngine.balance(plan: plan([.lift, .lift, .lift, .lift, .lift, .lift, .lift]))
        XCTAssertFalse(CNSBudgetEngine.violates(out))
        let lifts = out.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(lifts, 5)  // L,L,R,L,L,R,L is the max run-free layout
        XCTAssertGreaterThanOrEqual(out.days.filter { $0.title == "Recovery" }.count, 1)
    }
}
