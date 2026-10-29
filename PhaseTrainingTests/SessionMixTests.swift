import XCTest
@testable import PhaseTraining

/// Sport sessions plus complement sessions (SessionMix): the dose table, how
/// the sport sessions spread, what complement days train, and the week the
/// planner builds from it.
final class SessionMixTests: XCTestCase {

    // MARK: - Table

    /// Every cell of the table Wilbur chose on 2026-10-28.
    func test_sportDose_matchesTheTable() {
        let expected: [SeasonPhase: [Int]] = [
            .offSeason:   [1, 2, 2, 2, 3, 3],
            .preSeason:   [1, 2, 2, 2, 2, 3],
            .eventPrep:   [1, 2, 2, 2, 2, 3],
            .inSeason:    [1, 1, 1, 1, 2, 2],
            .maintenance: [1, 1, 1, 1, 2, 2],
        ]
        for (phase, doses) in expected {
            for (i, dose) in doses.enumerated() {
                XCTAssertEqual(SessionMix.sportDose(phase: phase, liftDays: i + 1), dose, "\(phase) at \(i + 1) days")
            }
        }
        XCTAssertEqual(SessionMix.sportDose(phase: .preSeason, liftDays: 0), 0)
    }

    func test_sportPositions_neverBackToBackWhenThereIsRoom() {
        XCTAssertEqual(SessionMix.sportPositions(totalLifts: 3, dose: 2), [0, 2])
        XCTAssertEqual(SessionMix.sportPositions(totalLifts: 5, dose: 2), [1, 3])
        XCTAssertEqual(SessionMix.sportPositions(totalLifts: 6, dose: 3), [1, 3, 5])
        for total in 1...7 {
            for dose in 1...total {
                let p = SessionMix.sportPositions(totalLifts: total, dose: dose)
                XCTAssertEqual(p.count, dose)
                XCTAssertEqual(Set(p).count, dose, "duplicate position at \(dose) of \(total)")
                XCTAssertTrue(p.allSatisfy { (0..<total).contains($0) })
                if dose * 2 <= total {
                    XCTAssertTrue(zip(p, p.dropFirst()).allSatisfy { $1 - $0 >= 2 }, "\(p) of \(total)")
                }
            }
        }
    }

    /// Roles across a week: the right count of each, sport ordinals 0..<dose,
    /// distinct complement titles.
    func test_roles_coverTheWeek() {
        for phase in SeasonPhase.allCases {
            for total in 1...6 {
                for family in [SessionMix.Family.legsDominant, .upperDominant] {
                    let roles = (0..<total).map {
                        SessionMix.role(liftIndex: $0, totalLifts: total, phase: phase, family: family)
                    }
                    var sport: [Int] = [], titles: [String] = []
                    for role in roles {
                        switch role {
                        case .sport(let index, let of):
                            XCTAssertEqual(of, SessionMix.sportDose(phase: phase, liftDays: total))
                            sport.append(index)
                        case .complement(let slot):
                            titles.append(slot.title)
                        }
                    }
                    XCTAssertEqual(sport, Array(0..<SessionMix.sportDose(phase: phase, liftDays: total)))
                    XCTAssertEqual(Set(titles).count, titles.count, "\(phase) \(total) \(family): \(titles)")
                }
            }
        }
    }

    func test_complementRotation_legsDominantNeverTrainsLegs() {
        for count in 1...6 {
            let focuses = SessionMix.complementRotation(family: .legsDominant, count: count)
            XCTAssertEqual(focuses.count, count)
            XCTAssertTrue(focuses.allSatisfy { $0.demandWeights[.legStrength] == nil }, "\(focuses)")
        }
        XCTAssertEqual(SessionMix.complementRotation(family: .legsDominant, count: 1), [.upperBody])
        XCTAssertEqual(SessionMix.complementRotation(family: .legsDominant, count: 2), [.pushCore, .pullArms])
        XCTAssertEqual(SessionMix.complementRotation(family: .legsDominant, count: 3), [.upperPush, .upperPull, .coreArms])
    }

    // MARK: - Engine

    private func memory(_ slug: String, _ phase: SeasonPhase, days: Int,
                        equipment: [Equipment] = [.fullGym], injuries: [String] = []) throws -> TrainingMemory {
        var m = TrainingMemory()
        let sport = try XCTUnwrap(Sport.resolve(slug: slug))
        m.sports = [sport]; m.primarySport = sport
        m.seasonsBySport = [sport: phase]; m.defaultSeason = phase
        m.experience = .intermediate; m.equipment = equipment
        m.liftDaysPerWeek = days; m.sessionMinutes = 60
        m.onboardedAt = Date()
        return m
    }

    private let legBuckets: Set<String> = ["quads", "hamstrings", "glutes", "calves"]

    /// No ski or snowboard complement day loads legs as the prime mover, in
    /// any focus, phase or equipment setup; each holds at least 3 movements.
    func test_legsDominantComplementDays_haveNoLegPrimaries() throws {
        for slug in ["alpine-skiing", "snowboarding"] {
            for phase in SeasonPhase.allCases {
                for equipment in [[Equipment.fullGym], [.bodyweight]] {
                    let m = try memory(slug, phase, days: 6, equipment: equipment)
                    for focus in [ComplementFocus.upperBody, .pushCore, .pullArms, .upperPush, .upperPull, .coreArms] {
                        let athlete = AthleteState.from(m, variant: SportSeasonGenerator.defaultVariant(forSport: slug))
                        let w = SportSeasonGenerator.generateSession(
                            athlete, sessionIndex: 0, complement: ComplementSlot(focus: focus, repeatNumber: 1))
                        let label = "\(slug) \(phase) \(equipment) \(focus)"
                        XCTAssertGreaterThanOrEqual(w.exercises.count, 3, "\(label): \(w.exercises.map(\.name))")
                        for ex in w.exercises {
                            let buckets = WorkoutGenerator.primaryMuscleBuckets(exerciseId: ex.exerciseId)
                            XCTAssertTrue(buckets.isDisjoint(with: legBuckets), "\(label): \(ex.name) loads \(buckets)")
                        }
                        XCTAssertEqual(w.title, focus.title)
                        XCTAssertEqual(w.focus, focus.workoutFocus)
                    }
                }
            }
        }
    }

    // MARK: - Planner

    /// Wilbur's example: pre-season, 5 gym days.
    func test_preSeasonFiveDays_isTwoSportAndThreeComplement() throws {
        for slug in ["alpine-skiing", "snowboarding"] {
            let plan = Planner.generate(memory: try memory(slug, .preSeason, days: 5), routines: [])
            let lifts = plan.days.filter { $0.kind == .lift }
            XCTAssertEqual(lifts.count, 5, "\(slug): the phase cap used to cut this to 3")
            let sport = lifts.filter { !$0.isComplementSession }
            let complement = lifts.filter(\.isComplementSession)
            XCTAssertEqual(sport.count, 2, "\(slug): \(lifts.map(\.title))")
            XCTAssertEqual(complement.map(\.title), ["Upper push", "Upper pull", "Core + arms"], slug)
            let order = lifts.map(\.isComplementSession)
            XCTAssertFalse(zip(order, order.dropFirst()).contains { !$0 && !$1 }, "\(slug): sport sessions back to back \(order)")
            let f = DateFormatter(); f.dateFormat = "EEE"
            print("WEEK \(slug) pre 5x: " + plan.days.map { "\(f.string(from: $0.date)) \($0.kind == .lift ? $0.title : "-")" }.joined(separator: " | "))
        }
    }

    /// A moved workout keeps its role: it carries its lift index.
    func test_movedComplementDay_staysAComplementDay() throws {
        let m = try memory("alpine-skiing", .preSeason, days: 5)
        let suite = "SessionMixTests.\(UUID().uuidString)"
        let store = PlanStore(defaults: UserDefaults(suiteName: suite)!, today: Date())
        _ = store.generate(from: m)
        let days = try XCTUnwrap(store.plan?.days)
        let cal = Calendar.current
        guard let src = days.first(where: \.isComplementSession),
              let dst = days.first(where: { $0.kind == .rest && cal.startOfDay(for: $0.date) > cal.startOfDay(for: src.date) })
        else { throw XCTSkip("this week's layout has no rest day after a complement day") }
        store.swap(sourceDate: src.date, targetDate: dst.date, memory: m)
        let moved = try XCTUnwrap(store.plan?.days.first { cal.isDate($0.date, inSameDayAs: dst.date) })
        XCTAssertEqual(moved.title, src.title)
        XCTAssertTrue(moved.isComplementSession)
    }

    /// Prints the weeks the plan asked to see (titles per day).
    func test_printWeeks() throws {
        for (slug, phase, days) in [("alpine-skiing", SeasonPhase.preSeason, 3), ("alpine-skiing", .preSeason, 6),
                                    ("climbing", .inSeason, 4)] {
            let plan = Planner.generate(memory: try memory(slug, phase, days: days), routines: [])
            for d in plan.days where d.kind == .lift {
                let prim = d.generatedWorkout?.exercises.map {
                    WorkoutGenerator.primaryMuscleBuckets(exerciseId: $0.exerciseId).sorted().joined(separator: "/")
                } ?? []
                print("WEEK \(slug) \(phase) \(days)x  \(d.title): \(prim.joined(separator: ", "))")
            }
        }
    }
}
