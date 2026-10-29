import XCTest
@testable import PhaseTraining

/// The training goal re-bands strength work on every season-engine session
/// and leaves sport-quality work alone.
final class TrainingGoalTests: XCTestCase {

    private func memory(_ slug: String, _ season: SeasonPhase, goal: TrainingGoal) throws -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 5
        let sport = try XCTUnwrap(Sport.resolve(slug: slug))
        m.sports = [sport]
        m.primarySport = sport
        m.seasonsBySport = [sport: season]
        m.defaultSeason = season
        m.trainingGoal = goal
        return m
    }

    private func sessions(_ m: TrainingMemory) -> [GeneratedWorkout] {
        let athlete = AthleteState.from(m, variant: SportSeasonGenerator.defaultVariant(forSport: m.primarySport?.slug))
        var out = (0..<3).map { SportSeasonGenerator.generateSession(athlete, sessionIndex: $0, sessionsInWeek: 3) }
        let family = SessionMix.family(forSport: m.primarySport?.slug)
        for focus in SessionMix.complementRotation(family: family, count: 3) {
            out.append(SportSeasonGenerator.generateSession(athlete, sessionIndex: 0,
                                                            complement: ComplementSlot(focus: focus, repeatNumber: 1)))
        }
        return out
    }

    /// (demand, exercise) pairs, read from the provenance's demand list,
    /// which runs in exercise order.
    private func pairs(_ w: GeneratedWorkout) -> [(Demand, GeneratedExercise)] {
        let tail = w.provenance.components(separatedBy: "demands: ").last ?? ""
        let demands = tail.split(separator: "/").compactMap { Demand(rawValue: String($0)) }
        return Array(zip(demands, w.exercises))
    }

    private let cases: [(String, SeasonPhase)] = [
        ("alpine-skiing", .offSeason), ("alpine-skiing", .preSeason),
        ("climbing", .offSeason), ("climbing", .inSeason),
    ]

    func test_sportPerformance_isTodaysPrescription() {
        let modes: [ProgressionMode] = [.progressiveOverload, .autoregulateHold, .maintainMinimal, .deload]
        for demand in Demand.allCases {
            for mode in modes {
                XCTAssertEqual(DemandScheme.scheme(for: demand, progression: mode, goal: .sportPerformance),
                               (DemandScheme.base[demand] ?? DemandScheme.fallback).modulated(by: mode),
                               "\(demand) \(mode)")
            }
        }
    }

    func test_eachGoal_rebandsStrengthDemands_only() throws {
        let expectedRest: [TrainingGoal: Int] = [.strength: 180, .size: 90, .endurance: 45]
        for goal in [TrainingGoal.strength, .size, .endurance] {
            var rebanded = 0
            for (slug, season) in cases {
                let baseline = sessions(try memory(slug, season, goal: .sportPerformance))
                let withGoal = sessions(try memory(slug, season, goal: goal))
                XCTAssertEqual(withGoal.map { $0.exercises.map(\.exerciseId) },
                               baseline.map { $0.exercises.map(\.exerciseId) },
                               "\(goal) \(slug) \(season): the goal changed which movements were picked")
                for (w, b) in zip(withGoal, baseline) {
                    for ((demand, ex), (_, bex)) in zip(pairs(w), pairs(b)) {
                        let hasProtocol = ex.reps == bex.reps && ex.restSeconds == bex.restSeconds
                            && ex.sets == bex.sets
                        if TrainingGoal.rebandable.contains(demand) {
                            // A cited protocol keeps its own numbers.
                            if hasProtocol { continue }
                            XCTAssertEqual(ex.restSeconds, expectedRest[goal],
                                           "\(goal) \(slug) \(demand) \(ex.name)")
                            rebanded += 1
                        } else {
                            XCTAssertEqual(ex.reps, bex.reps, "\(goal) changed \(demand) \(ex.name)")
                            XCTAssertEqual(ex.restSeconds, bex.restSeconds, "\(goal) changed \(demand) \(ex.name)")
                        }
                    }
                }
            }
            XCTAssertGreaterThan(rebanded, 5, "\(goal) re-banded almost nothing")
            print("GOAL-MEASURE \(goal): \(rebanded) strength rows re-banded")
        }
    }

    func test_goalBands_match_theTable() {
        let base = DemandScheme.base[.upperPush]!
        let s = TrainingGoal.strength.band(over: base, demand: .upperPush)!
        XCTAssertEqual([s.repsLow, s.repsHigh], [3, 6]); XCTAssertEqual(s.restSeconds, 180)
        let z = TrainingGoal.size.band(over: base, demand: .upperPush)!
        XCTAssertEqual([z.repsLow, z.repsHigh], [8, 12]); XCTAssertEqual(z.restSeconds, 90)
        let e = TrainingGoal.endurance.band(over: base, demand: .upperPush)!
        XCTAssertEqual([e.repsLow, e.repsHigh], [15, 20]); XCTAssertEqual(e.restSeconds, 45)
        XCTAssertNil(TrainingGoal.strength.band(over: DemandScheme.base[.power]!, demand: .power))
        XCTAssertNil(TrainingGoal.endurance.band(over: DemandScheme.base[.fingerStrength]!, demand: .fingerStrength))
        XCTAssertNil(TrainingGoal.sportPerformance.band(over: base, demand: .upperPush))
    }

    func test_goal_isPersisted_andOldMemoryDecodes() throws {
        var m = TrainingMemory()
        m.trainingGoal = .size
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(TrainingMemory.self, from: data).trainingGoal, .size)

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "trainingGoal")
        let old = try JSONDecoder().decode(TrainingMemory.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.trainingGoal, .sportPerformance)
    }

    func test_defaultGoal_leavesThePlanHashAlone_andAChangeMovesIt() {
        var m = TrainingMemory()
        let before = m.planInputsHash
        m.trainingGoal = .sportPerformance
        XCTAssertEqual(m.planInputsHash, before)
        m.trainingGoal = .endurance
        XCTAssertNotEqual(m.planInputsHash, before)
    }
}
