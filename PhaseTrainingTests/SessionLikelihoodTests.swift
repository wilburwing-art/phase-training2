// SessionLikelihoodTests.swift — 3b: "will today happen?"
//
// The prior with no history, weekday shrinkage toward the pooled rate, the
// skip-streak report, travel and time-of-day adjustments, sample hygiene (window,
// dedupe, non-workout days), the week helper, and the coach block.

import XCTest
@testable import PhaseTraining

final class SessionLikelihoodTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    /// Monday 2026-10-05, local midnight.
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 5))! }
    private func at(_ dayOffset: Int, _ hour: Int = 0) -> Date {
        cal.date(byAdding: .hour, value: dayOffset * 24 + hour, to: monday)!
    }

    private func outcome(_ dayOffset: Int, planned: DayKind? = .lift, kind: DayOutcomeKind = .asPlanned) -> DayOutcome {
        DayOutcome(sessionId: Double.random(in: 0...1e9), date: at(dayOffset), kind: kind,
                   plannedDayKind: planned, plannedTitle: nil, plannedRoutineId: nil,
                   plannedExercises: [], plannedWorkingSets: 0, plannedMinutes: nil, targetMinutes: nil,
                   loggedTemplateId: "", loggedTitle: "", loggedExercises: [], completedWorkingSets: 0,
                   durationMinutes: 0, swaps: [], dropped: [], added: [], recordedAt: at(dayOffset))
    }
    private func miss(_ dayOffset: Int) -> MissedWorkoutEntry {
        MissedWorkoutEntry(date: at(dayOffset), plannedKind: .lift, plannedTitle: "Lift",
                           resolution: .dropped, loggedAt: at(dayOffset + 1))
    }
    private func history(_ outcomes: [DayOutcome] = [], _ missed: [MissedWorkoutEntry] = [],
                         starts: [Date] = []) -> SessionLikelihoodEngine.History {
        SessionLikelihoodEngine.History(outcomes: outcomes, missed: missed, sessionStarts: starts)
    }
    private func estimate(_ dayOffset: Int, kind: DayKind = .lift, travel: Bool = false,
                          _ h: SessionLikelihoodEngine.History, now: Date? = nil) -> SessionLikelihood? {
        SessionLikelihoodEngine.estimate(date: at(dayOffset), dayKind: kind, isTravel: travel,
                                         history: h, now: now ?? at(0, 5), calendar: cal)
    }

    private typealias E = SessionLikelihoodEngine
    /// The no-history rate: the Beta prior's mean.
    private let p0 = E.priorHappened / (E.priorHappened + E.priorMissed)

    // MARK: - Base rate

    func test_noHistory_startsAtThePrior_andRestDaysHaveNoEstimate() throws {
        let l = try XCTUnwrap(estimate(1, history()))
        XCTAssertEqual(l.probability, p0, accuracy: 1e-9)
        XCTAssertEqual(l.samples, 0)
        XCTAssertTrue(l.reasons.first?.contains("starts at \(Int((p0 * 100).rounded()))%") ?? false, "\(l.reasons)")
        XCTAssertNil(estimate(1, kind: .rest, history()))
        XCTAssertNil(estimate(1, kind: .event, history()))
        XCTAssertNotNil(estimate(1, kind: .sport, history()))
    }

    func test_weekdayRate_isShrunkTowardThePooledRate() throws {
        // Eight Mondays all happened; Thursdays: 1 happened, 2 missed (not a streak).
        let mondays = (1...8).map { outcome(-7 * $0) }
        let h = history(mondays + [outcome(-4)], [miss(-11), miss(-18)])
        let pooled = (9 + E.priorHappened) / (11 + E.priorHappened + E.priorMissed)
        let thu = try XCTUnwrap(estimate(3, h))
        XCTAssertEqual(thu.probability, (1 + E.weekdayShrink * pooled) / (3 + E.weekdayShrink), accuracy: 1e-9)
        XCTAssertEqual(thu.weekdayHappened, 1)
        XCTAssertEqual(thu.weekdayMissed, 2)
        XCTAssertEqual(thu.samples, 11)
        XCTAssertTrue(thu.reasons[0].hasPrefix("1 of 3 planned Thu sessions happened"), thu.reasons[0])
        let mon = try XCTUnwrap(estimate(7, h))
        XCTAssertEqual(mon.probability, (8 + E.weekdayShrink * pooled) / (8 + E.weekdayShrink), accuracy: 1e-9)
        XCTAssertGreaterThan(mon.probability, thu.probability)
        XCTAssertLessThan(mon.probability, 1, "eight for eight still is not certain")
        // A weekday with no samples reads the pooled rate.
        XCTAssertEqual(try XCTUnwrap(estimate(5, h)).probability, pooled, accuracy: 1e-9)
    }

    func test_samples_oneperDay_inTheWindow_plannedWorkoutDaysOnly() throws {
        let h = history([outcome(-7), outcome(-6, planned: .rest), outcome(-5, planned: nil),
                         outcome(0), outcome(-3, planned: .sport, kind: .unplanned)],
                        [miss(-7), miss(-100)])
        let l = try XCTUnwrap(estimate(7, h))
        XCTAssertEqual(l.samples, 2, "Mon -7 once (outcome wins over the miss) and the sport day; rest, unplanned-day, today and 100-day-old rows do not count")
        XCTAssertEqual(l.weekdayHappened, 1)
        XCTAssertEqual(l.weekdayMissed, 0)
    }

    // MARK: - Adjustments

    func test_skipStreak_isReported_andTheWeekdayRateCarriesIt() throws {
        let h = history([], [miss(-5), miss(-12), miss(-19)])
        let wed = try XCTUnwrap(estimate(2, h))
        let pooled = E.priorHappened / (3 + E.priorHappened + E.priorMissed)
        XCTAssertEqual(wed.weekdayRate, E.weekdayShrink * pooled / (3 + E.weekdayShrink), accuracy: 1e-9)
        XCTAssertEqual(wed.probability, wed.weekdayRate, accuracy: 1e-9, "no second discount for the same misses")
        XCTAssertLessThan(wed.probability, try XCTUnwrap(estimate(3, h)).probability)
        XCTAssertTrue(wed.reasons.contains { $0.contains("skip streak") }, "\(wed.reasons)")
        let thu = try XCTUnwrap(estimate(3, h))
        XCTAssertFalse(thu.reasons.contains { $0.contains("skip streak") }, "the streak is Wednesday's only")
    }

    func test_travel_multipliesDown() throws {
        let l = try XCTUnwrap(estimate(1, travel: true, history()))
        XCTAssertEqual(l.probability, p0 * E.travelFactor, accuracy: 1e-9)
        XCTAssertTrue(l.reasons.contains { $0.hasPrefix("Travel day") })
    }

    func test_timeOfDay_countsOnlyToday_andOnlyWellPastTheUsualStart() throws {
        let starts = (1...5).map { at(-$0, 7) }
        let h = history(starts: starts)
        XCTAssertEqual(SessionLikelihoodEngine.usualStartHour(starts, now: at(0, 11), calendar: cal), 7)

        let late = try XCTUnwrap(estimate(0, h, now: at(0, 11)))
        XCTAssertEqual(late.probability, p0 * (1 - 0.12 * 3), accuracy: 1e-9)
        XCTAssertTrue(late.reasons.contains("Sessions usually start around 7 AM; it is 4 hours past that."), "\(late.reasons)")

        let early = try XCTUnwrap(estimate(0, h, now: at(0, 6)))
        XCTAssertEqual(early.probability, p0, accuracy: 1e-9)
        XCTAssertTrue(early.reasons.contains { $0.hasPrefix("Still before the usual start") })

        let withinGrace = try XCTUnwrap(estimate(0, h, now: at(0, 8)))
        XCTAssertEqual(withinGrace.probability, p0, accuracy: 1e-9)

        let midnight = try XCTUnwrap(estimate(0, h, now: at(0, 23)))
        XCTAssertEqual(midnight.probability, p0 * E.lateFloor, accuracy: 1e-9)

        let tomorrow = try XCTUnwrap(estimate(1, h, now: at(0, 23)))
        XCTAssertEqual(tomorrow.probability, p0, accuracy: 1e-9, "a future day ignores the clock")

        XCTAssertNil(SessionLikelihoodEngine.usualStartHour(Array(starts.prefix(4)), now: at(0, 11), calendar: cal),
                     "fewer than five starts is not a habit")
    }

    func test_alreadyLoggedToday_isCertain() throws {
        let l = try XCTUnwrap(estimate(0, history([], [miss(-7), miss(-14), miss(-21)], starts: [at(0, 6)]),
                                       now: at(0, 20)))
        XCTAssertEqual(l.probability, 1)
    }

    // MARK: - Week and surfaces

    func test_week_estimatesWorkoutDaysOnly_withTravelFromEvents() {
        let kinds: [DayKind] = [.lift, .rest, .sport, .rest, .lift, .event, .rest]
        let days = kinds.enumerated().map { i, k in
            DayPlan(date: at(7 + i), kind: k, title: "d\(i)", routineId: nil, generatedWorkout: nil, generatedReason: "test")
        }
        let plan = WeekPlan(days: days, generatedAt: monday, inputsHash: "fixture")
        let events = [WeekEvent(date: at(9), title: "Travel", kind: .outOfTown),
                      WeekEvent(date: at(11), title: "Race", kind: .race)]
        let week = SessionLikelihoodEngine.week(plan: plan, events: events, history: history(),
                                                now: at(0, 12), calendar: cal)
        XCTAssertEqual(week.map { cal.dateComponents([.day], from: monday, to: $0.date).day! }, [7, 9, 11])
        XCTAssertEqual(week[0].probability, p0, accuracy: 1e-9)
        XCTAssertEqual(week[1].probability, p0 * E.travelFactor, accuracy: 1e-9)
        XCTAssertEqual(week[2].probability, p0, accuracy: 1e-9, "a race event is not travel")
    }

    func test_clock() {
        XCTAssertEqual(SessionLikelihoodEngine.clock(7), "7 AM")
        XCTAssertEqual(SessionLikelihoodEngine.clock(0), "12 AM")
        XCTAssertEqual(SessionLikelihoodEngine.clock(12), "12 PM")
        XCTAssertEqual(SessionLikelihoodEngine.clock(18.4), "6 PM")
    }

    func test_coachBlock() throws {
        XCTAssertNil(CoachContext.sessionLikelihoodSection(nil))
        let l = try XCTUnwrap(estimate(1, travel: true, history()))
        let block = try XCTUnwrap(CoachContext.sessionLikelihoodSection(l))
        XCTAssertTrue(block.hasPrefix("TODAY'S SESSION LIKELIHOOD"))
        XCTAssertTrue(block.contains("estimate: \(l.percent)%"), block)
        XCTAssertEqual(l.percent, 59)
        XCTAssertTrue(block.contains("Travel day"))
        XCTAssertFalse(block.contains("\u{2014}"), "no em dashes")
    }
}
