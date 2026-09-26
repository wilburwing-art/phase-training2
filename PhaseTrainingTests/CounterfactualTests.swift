// CounterfactualTests.swift — 2a: the counterfactual engine on synthetic weeks.

import XCTest
@testable import PhaseTraining

final class CounterfactualTests: XCTestCase {

    private let monday = Date(timeIntervalSince1970: 1_759_104_000) // 2025-09-29, a Monday UTC
    private var now: Date { monday.addingTimeInterval(8 * 3600) }
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
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

    /// About 3 a week over the prior four weeks, the last one two days ago.
    private var history: [ReadinessEvent] {
        [-2, -4, -7, -9, -11, -14, -16, -18, -21, -23, -25].map { ReadinessEvent(startTime: at($0)) }
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

    func test_skipLowersOrKeepsReadiness() throws {
        let skips = run(typical).outcomes.filter { $0.alternative == .skip }
        XCTAssertEqual(skips.count, 2)
        for s in skips {
            let d = try XCTUnwrap(s.delta)
            XCTAssertLessThan(d, 0, "one fewer session lowers density")
        }
    }

    func test_movingCloserToTheSportDayRaisesRecency() throws {
        // One lift on Monday, five days before Saturday: recency is on its ramp.
        let r = run(week([.lift, .rest, .rest, .rest, .rest, .sport, .rest]))
        let moves = r.outcomes.compactMap { o -> (Date, Double)? in
            if case .move(let to) = o.alternative, let s = o.score { return (to, s) }
            return nil
        }
        XCTAssertEqual(moves.map { $0.0 }, [at(1), at(2), at(3), at(4)])
        let baseline = try XCTUnwrap(r.baseline)
        XCTAssertGreaterThan(moves[0].1, baseline)
        XCTAssertGreaterThan(moves[1].1, moves[0].1)
        XCTAssertEqual(moves[3].1, moves[1].1, accuracy: 1e-12,
                       "Wed, Thu and Fri are all within 3 days of Saturday: full recency")
        XCTAssertEqual(r.largestImpact?.alternative, .skip,
                       "losing the only session costs more than any move gains")
    }

    func test_shorterAndSavedRoutine_areZeroUnderReadinessSignal() throws {
        let saved = CustomRoutine(id: "r1", name: "Mine", exercises: [], createdAt: monday)
        for o in run(typical, saved: [saved]).outcomes {
            switch o.alternative {
            case .shorter, .savedRoutine:
                XCTAssertEqual(try XCTUnwrap(o.delta), 0, accuracy: 1e-12,
                               "ReadinessSignal ignores duration and content")
            default: break
            }
        }
    }

    func test_noSportDayAhead_isEmpty() {
        XCTAssertEqual(run(week([.lift, .rest, .lift, .rest, .lift, .rest, .rest])), .empty)
        // A sport day today is not "next": nothing before it can change.
        XCTAssertEqual(run(week([.sport, .rest, .lift, .rest, .rest, .rest, .rest])), .empty)
    }

    func test_aDayAlreadyLoggedIsHistory_notPlan() {
        let logged = history + [ReadinessEvent(startTime: now)]
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

    func test_liveScoreMatchesTheGeneratorContext() throws {
        let sessions = [-1, -3, -6, -10, -20].map { d -> SavedSession in
            SavedSession(templateId: "t", name: "Lift", category: "", startTime: at(d), exercises: [],
                         feel: nil, note: nil, endTime: at(d).addingTimeInterval(3600), duration: 3600)
        }
        let ctx = GeneratorContext.from(sessions: sessions, soreness: [], feedback: [], now: now)
        let events = GeneratorContext.buildReadinessEvents(sessions: sessions, importedWorkouts: [],
                                                           sportLogs: [], now: now)
        XCTAssertEqual(try XCTUnwrap(Counterfactual.liveScore(history: events, now: now)),
                       ctx.readinessScore, accuracy: 1e-12)
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
