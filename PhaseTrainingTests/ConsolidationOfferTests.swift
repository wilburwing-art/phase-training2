// ConsolidationOfferTests.swift — D3 of the adaptive-week PRD.
//
// Characterization coverage for the consolidation OFFER gate, which is
// split across two layers:
//
//   - MissedWorkoutAutopilot.shouldOfferConsolidation — pure escalation
//     check: "reshuffle found no clean slot for a non-budget, non-data
//     reason" (week full, or no valid future rest day).
//   - PlanStore.shouldOfferConsolidation — the banner-facing gate that
//     layers the 1/week consolidation cap and the ≥2 future focus-tagged
//     lift-days requirement on top of the autopilot escalation.
//
// The autopilot's own branch matrix (week-full / no-rest-day / budget /
// not-in-plan) is covered in MissedWorkoutAutopilotTests; this file targets
// the PlanStore wrapper's lift-count + cap gates and the end-of-week date
// edges.

import XCTest
@testable import PhaseTraining

final class ConsolidationOfferTests: XCTestCase {

    // MARK: - Helpers

    /// Monday 2026-05-11 — same anchor date as the other missed-workout
    /// tests, so day offsets read as Mon=0 … Sun=6.
    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return Calendar.current.date(from: c)!
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: monday())!
    }

    /// Lift day with an optional persisted focus. `focus: nil` reproduces
    /// plans saved before GeneratedWorkout.focus existed — those days can't
    /// be consolidated because consolidateWeek can't recover their focus.
    private func liftDay(_ offset: Int, focus: WorkoutFocus?,
                         protected: Bool = false) -> DayPlan {
        DayPlan(
            date: day(offset), kind: .lift,
            title: focus?.title ?? "Lift", routineId: nil,
            generatedWorkout: GeneratedWorkout(
                title: focus?.title ?? "Lift", summary: "", exercises: [],
                estimatedMinutes: 60, provenance: "", focus: focus),
            protected: protected
        )
    }

    private func restDay(_ offset: Int) -> DayPlan {
        DayPlan(date: day(offset), kind: .rest, title: "Rest",
                routineId: nil, generatedWorkout: nil)
    }

    private func sportDay(_ offset: Int) -> DayPlan {
        DayPlan(date: day(offset), kind: .sport, title: "Climb",
                routineId: nil, generatedWorkout: nil)
    }

    private func weekPlan(_ days: [DayPlan]) -> WeekPlan {
        precondition(days.count == 7)
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    private func freshStore(today: Date) -> PlanStore {
        let suite = "consolidation-offer-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PlanStore(defaults: defaults, today: today)
    }

    /// Week-full reference plan: 4 lifts (Mon/Wed/Fri/Sat, all focus-tagged)
    /// → the drop rule fires, reshuffle returns [], and — as of Wed — three
    /// focus-tagged future lifts remain. The canonical "offer" shape.
    private func weekFullPlan() -> WeekPlan {
        weekPlan([liftDay(0, focus: .push), restDay(1),
                  liftDay(2, focus: .pull), restDay(3),
                  liftDay(4, focus: .legs), liftDay(5, focus: .upper),
                  restDay(6)])
    }

    // MARK: - Offered: ≥2 future focus-tagged lift days

    func test_offerConsolidation_weekFull_withThreeFutureFocusLifts() {
        // Mon push missed; 4-lift week trips the drop rule so reshuffle has
        // no proposal; Wed/Fri/Sat remain focus-tagged → offer.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekFullPlan())
        XCTAssertTrue(store.shouldOfferConsolidation(missedDate: day(0), now: wed))
    }

    func test_offerConsolidation_atExactlyTwoFutureLifts() {
        // 3 lifts (<4 → no drop rule) but zero rest days, so reshuffle has
        // no slot → escalate. Exactly 2 future focus lifts (Wed, Fri) is
        // the minimum reducible remainder — boundary of the ≥2 gate.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekPlan([liftDay(0, focus: .push), sportDay(1),
                                liftDay(2, focus: .pull), sportDay(3),
                                liftDay(4, focus: .legs), sportDay(5),
                                sportDay(6)]))
        XCTAssertTrue(store.shouldOfferConsolidation(missedDate: day(0), now: wed))
    }

    // MARK: - Not offered: <2 future lift days

    func test_noOffer_withOneFutureLift() {
        // Same no-rest-day escalation shape, but only Wed's lift remains —
        // a 1-day remainder can't be reduced → no offer.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekPlan([liftDay(0, focus: .push), sportDay(1),
                                liftDay(2, focus: .pull), sportDay(3),
                                sportDay(4), sportDay(5), sportDay(6)]))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: wed))
    }

    func test_noOffer_whenFutureLiftsLackFocus() {
        // Week-full escalation with 3 future lifts — but none carry a
        // persisted focus (pre-focus-field plans), so consolidateWeek
        // couldn't actually apply → don't offer.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekPlan([liftDay(0, focus: .push), restDay(1),
                                liftDay(2, focus: nil), restDay(3),
                                liftDay(4, focus: nil), liftDay(5, focus: nil),
                                restDay(6)]))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: wed))
    }

    func test_noOffer_whenFutureLiftsProtected() {
        // Week-full escalation, but 2 of the 3 future lifts are user-locked
        // → only 1 reducible lift remains → below the ≥2 gate.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekPlan([liftDay(0, focus: .push), restDay(1),
                                liftDay(2, focus: .pull, protected: true), restDay(3),
                                liftDay(4, focus: .legs, protected: true),
                                liftDay(5, focus: .upper), restDay(6)]))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: wed))
    }

    // MARK: - Weekly caps

    func test_noOffer_whenConsolidationCapReached() {
        // Identical to the canonical offer shape, except the 1/week
        // consolidation cap is already spent → suppress.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekFullPlan())
        store.midWeekConsolidationCount = PlanStore.weeklyConsolidationCap
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: wed),
                       "1/week consolidation cap should suppress the offer")
    }

    func test_noOffer_whenReshuffleBudgetExhausted() {
        // PRD §6 Q4 — an exhausted reshuffle budget is the decision-fatigue
        // case: consolidation must NOT be offered on top of it, even though
        // the week-full shape would otherwise qualify.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekFullPlan())
        store.midWeekReshuffleCount = PlanStore.weeklyReshuffleCap
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: wed),
                       "budget exhaustion is not a consolidation trigger")
    }

    // MARK: - Reshuffle precedence

    func test_noOffer_whenCleanReshuffleSlotExists() {
        // 3 lifts with open rest days — reshuffle can host the missed Mon on
        // Sunday (the only non-stacked rest day), so consolidation must NOT
        // be offered even though 2 focus-tagged future lifts remain.
        let wed = day(2)
        let store = freshStore(today: wed)
        store.setPlan(weekPlan([liftDay(0, focus: .push), restDay(1),
                                liftDay(2, focus: .pull), restDay(3),
                                liftDay(4, focus: .legs), restDay(5),
                                restDay(6)]))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: wed),
                       "a clean reshuffle slot means reshuffle handles it")
    }

    // MARK: - Date edges: missed date at the end of the week

    func test_noOffer_missedSunday_weekOver() {
        // Sunday is the last planned day; the soonest it can register as
        // missed is the following Monday — at which point zero plan days
        // remain in the future, so there's nothing left to consolidate.
        let nextMonday = day(7)
        let store = freshStore(today: nextMonday)
        store.setPlan(weekPlan([liftDay(0, focus: .push), restDay(1),
                                liftDay(2, focus: .pull), restDay(3),
                                liftDay(4, focus: .legs), restDay(5),
                                liftDay(6, focus: .upper)]))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(6), now: nextMonday),
                       "missed last-day-of-week leaves no future lifts → no offer")
    }

    func test_noOffer_missedSaturday_oneLiftDayLeft() {
        // Missed Saturday with only Sunday remaining: 1 future lift < 2 →
        // no offer, even though the week-full shape escalates.
        let sun = day(6)
        let store = freshStore(today: sun)
        store.setPlan(weekPlan([liftDay(0, focus: .push), restDay(1),
                                liftDay(2, focus: .pull), restDay(3),
                                restDay(4), liftDay(5, focus: .legs),
                                liftDay(6, focus: .upper)]))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(5), now: sun))
    }

    func test_autopilot_escalates_whenMissedDateIsLastDayOfWeek() {
        // Pure layer: the autopilot itself still says "escalate" for a missed
        // Sunday (week-full → reshuffle []), because the ≥2-future-lifts gate
        // intentionally lives in the PlanStore wrapper, not here. Documents
        // the layering the two tests above rely on.
        let p = weekPlan([liftDay(0, focus: .push), restDay(1),
                          liftDay(2, focus: .pull), restDay(3),
                          liftDay(4, focus: .legs), restDay(5),
                          liftDay(6, focus: .upper)])
        XCTAssertTrue(MissedWorkoutAutopilot.shouldOfferConsolidation(
            missedDate: day(6), plan: p,
            overrides: WeekOverrides(weekStart: monday()),
            remainingBudget: 2, now: day(7)))
    }

    // MARK: - Empty input

    func test_noOffer_withNoPlan() {
        let store = freshStore(today: day(2))
        XCTAssertFalse(store.shouldOfferConsolidation(missedDate: day(0), now: day(2)))
    }
}
