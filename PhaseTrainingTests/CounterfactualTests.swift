// CounterfactualTests.swift — 2a: the counterfactual engine on synthetic weeks.

import XCTest
@testable import PhaseTraining

final class CounterfactualTests: XCTestCase {

    private let monday = Date(timeIntervalSince1970: 1_759_104_000) // 2025-09-29, a Monday UTC
    private var now: Date { monday.addingTimeInterval(8 * 3600) }
    /// English weekday names, so the summary test reads "Mon" on any device locale.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func at(_ day: Int) -> Date { monday.addingTimeInterval(Double(day) * 86_400) }

    /// A week from Monday; `kinds` is Mon..Sun.
    private func week(_ kinds: [DayKind]) -> WeekPlan {
        let days = kinds.enumerated().map { i, k in
            DayPlan(date: at(i), kind: k, title: k.label, routineId: nil,
                    generatedWorkout: nil, durationMinutes: k == .lift ? 60 : nil,
                    generatedReason: "test")
        }
        return WeekPlan(days: days, generatedAt: monday, inputsHash: "test")
    }

    /// An hour about 3 times a week for the prior eight weeks, the last one two days ago.
    private var history: [ReadinessEvent] {
        stride(from: -2, through: -56, by: -2).filter { $0 % 7 != 0 }
            .map { ReadinessEvent(startTime: at($0), duration: 3600) }
    }

    private func run(_ plan: WeekPlan, history: [ReadinessEvent]? = nil,
                     saved: [CustomRoutine] = []) -> CounterfactualReport {
        Counterfactual.evaluate(plan: plan, history: history ?? self.history,
                                savedRoutines: saved, now: now, calendar: utc)
    }

    // Mon lift, Tue rest, Wed lift, Thu rest, Fri rest, Sat sport, Sun rest.
    private var typical: WeekPlan { week([.lift, .rest, .lift, .rest, .rest, .sport, .rest]) }

    func test_targetsTheNextSportDay_andOffersEveryAlternativePerLiftDay() throws {
        let saved = CustomRoutine(id: "r1", name: "Mine", exercises: [], createdAt: monday)
        let r = run(typical, saved: [saved])
        XCTAssertEqual(r.sportDay, at(5))
        XCTAssertNotNil(r.baseline)
        XCTAssertEqual(Set(r.outcomes.map(\.day)), [at(0), at(2)])
        let mon = r.outcomes.filter { $0.day == at(0) }.map(\.alternative)
        XCTAssertEqual(mon, [.skip, .move(to: at(1)), .move(to: at(3)), .move(to: at(4)),
                             .shorter(minutes: 30), .savedRoutine(id: "r1", name: "Mine")],
                       "moves go only to rest days before the sport day")
    }

    func test_skippingALiftDaysBeforeTheSportDay_raisesForm() throws {
        // Fatigue forgets in about a week, fitness in about six, so a session
        // in the last few days before Saturday costs more fatigue than it adds fitness.
        let skips = run(typical).outcomes.filter { $0.alternative == .skip }
        XCTAssertEqual(skips.count, 2)
        for s in skips {
            XCTAssertGreaterThan(try XCTUnwrap(s.delta), 0)
        }
        let mon = try XCTUnwrap(skips.first { $0.day == at(0) }?.delta)
        let wed = try XCTUnwrap(skips.first { $0.day == at(2) }?.delta)
        XCTAssertGreaterThan(wed, mon, "the later session carries more unrecovered fatigue")
    }

    func test_movingCloserToTheSportDay_lowersForm() throws {
        let r = run(week([.lift, .rest, .rest, .rest, .rest, .sport, .rest]))
        let moves = r.outcomes.compactMap { o -> (Date, Double)? in
            if case .move(let to) = o.alternative, let s = o.score { return (to, s) }
            return nil
        }
        XCTAssertEqual(moves.map { $0.0 }, [at(1), at(2), at(3), at(4)])
        var previous = try XCTUnwrap(r.baseline)
        for (_, score) in moves {
            XCTAssertLessThan(score, previous)
            previous = score
        }
    }

    func test_shorterRaisesForm_savedRoutineIsZero() throws {
        let saved = CustomRoutine(id: "r1", name: "Mine", exercises: [], createdAt: monday)
        var sawShorter = false
        for o in run(typical, saved: [saved]).outcomes {
            switch o.alternative {
            case .shorter:
                sawShorter = true
                XCTAssertGreaterThan(try XCTUnwrap(o.delta), 0)
            case .savedRoutine:
                XCTAssertEqual(try XCTUnwrap(o.delta), 0, accuracy: 1e-12,
                               "same slot, same minutes; load does not read content yet")
            default: break
            }
        }
        XCTAssertTrue(sawShorter)
    }

    func test_noSportDayAhead_isEmpty() {
        XCTAssertEqual(run(week([.lift, .rest, .lift, .rest, .lift, .rest, .rest])), .empty)
        // A sport day today is not "next": nothing before it can change.
        XCTAssertEqual(run(week([.sport, .rest, .lift, .rest, .rest, .rest, .rest])), .empty)
    }

    func test_aDayAlreadyLoggedIsHistory_notPlan() {
        let logged = history + [ReadinessEvent(startTime: now, duration: 3600)]
        let r = run(typical, history: logged)
        XCTAssertEqual(Set(r.outcomes.map(\.day)), [at(2)])
    }

    func test_skippingTheOnlyEvent_isNoData_notANeutralScore() throws {
        let r = run(week([.lift, .rest, .rest, .rest, .rest, .sport, .rest]), history: [])
        let skip = try XCTUnwrap(r.outcomes.first { $0.alternative == .skip })
        XCTAssertNil(skip.score)
        XCTAssertNil(skip.delta)
    }

    func test_deterministic_andIndependentOfDayOrder() {
        let a = run(typical)
        XCTAssertEqual(a, run(typical))
        var shuffled = typical
        shuffled.days.reverse()
        XCTAssertEqual(a, run(shuffled))
    }

    func test_summaryReadsLikeTheRoadmapLine() throws {
        let r = run(typical)
        let skip = try XCTUnwrap(r.outcomes.first { $0.alternative == .skip })
        let sat = try XCTUnwrap(r.sportDay)
        let line = Counterfactual.summary(skip, sportDay: sat, calendar: utc)
        XCTAssertTrue(line.hasPrefix("skip Mon: Sat readiness "), line)
        XCTAssertTrue(line.contains(" -> "), line)
    }
}
