import XCTest
@testable import PhaseTraining

/// Item 5 of the 2026-09-05 work plan.
///
/// thru-hiking, mountaineering and trail-running appeared in two to three test
/// assertions each against climbing's seventy. `FilterCompositionTests` walks
/// all eight sports, which is the floor; what was missing is a week-shape test
/// per sport, so a content regression in one of these (a routine deleted, a
/// phase left uncovered, the rotation collapsing to one routine) fails
/// something other than a composition count.
///
/// Healthy full-gym intermediate, every phase, default weekly shape, through
/// `Planner.generate` so the assertion holds on the path the app actually
/// takes.
final class ThinSportWeekShapeTests: XCTestCase {

    private static let sports = ["thru-hiking", "mountaineering", "trail-running"]

    private func plan(_ slug: String, _ phase: SeasonPhase) -> WeekPlan {
        var m = TrainingMemory()
        let sport = Sport.resolve(slug: slug)
        m.primarySport = sport
        m.sports = [sport]
        m.seasonsBySport = [sport: phase]
        m.defaultSeason = phase
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        return Planner.generate(memory: m, routines: [])
    }

    /// Every lift day, every phase: authored, non-empty, at or above the floor,
    /// within a sane movement count, and no duplicate movement inside a day.
    func test_everyPhaseServesARealAuthoredWeek() {
        for slug in Self.sports {
            for phase in SeasonPhase.allCases {
                let p = plan(slug, phase)
                let lifts = p.days.filter { $0.kind == .lift }
                XCTAssertGreaterThanOrEqual(lifts.count, 2, "[\(slug)/\(phase.rawValue)] fewer than two lift days in the default shape")
                for d in lifts {
                    guard let w = d.generatedWorkout else { XCTFail("[\(slug)/\(phase.rawValue)] lift day with no workout"); continue }
                    XCTAssertTrue(w.provenance.contains("Authored"), "[\(slug)/\(phase.rawValue)] not authored: \(w.provenance)")
                    XCTAssertGreaterThanOrEqual(w.exercises.count, AuthoredRoutineSelector.minimumMovements,
                                                "[\(slug)/\(phase.rawValue)] \(w.exercises.count) movements: '\(w.title)'")
                    XCTAssertLessThanOrEqual(w.exercises.count, 9, "[\(slug)/\(phase.rawValue)] \(w.exercises.count) movements is not a session: '\(w.title)'")
                    XCTAssertEqual(Set(w.exercises.map(\.exerciseId)).count, w.exercises.count,
                                   "[\(slug)/\(phase.rawValue)] duplicate movement in '\(w.title)'")
                    XCTAssertTrue(w.exercises.allSatisfy { $0.exerciseId > 0 }, "[\(slug)/\(phase.rawValue)] unresolved exercise id in '\(w.title)'")
                }
            }
        }
    }

    /// The rotation is real: across a phase's lift days the sport does not
    /// serve the same routine every day when it has more than one to offer.
    /// Measured against the selector's own candidate list so the assertion
    /// cannot demand variety the content does not have.
    func test_rotationVariesWhenTheSportHasMoreThanOneRoutine() {
        for slug in Self.sports {
            for phase in SeasonPhase.allCases {
                let candidates = CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.phaseLabels(for: phase))
                let pool = candidates.isEmpty
                    ? CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels)
                    : candidates
                let titles = Set(plan(slug, phase).days.filter { $0.kind == .lift }.compactMap { $0.generatedWorkout?.title })
                if pool.count >= 2 {
                    XCTAssertGreaterThanOrEqual(titles.count, 2,
                        "[\(slug)/\(phase.rawValue)] \(pool.count) routines available but the week served only \(titles)")
                } else {
                    XCTAssertEqual(titles.count, 1, "[\(slug)/\(phase.rawValue)] one routine available, expected one title, got \(titles)")
                }
            }
        }
    }

    /// The new bodyweight routines are reachable for a bodyweight user of each
    /// thin sport in every phase: this is the whole reason items 2 and R3-10
    /// existed, pinned per sport rather than only through the composition grid.
    func test_bodyweightUserGetsARealWeekInEveryPhase() {
        for slug in Self.sports {
            for phase in SeasonPhase.allCases {
                var m = TrainingMemory()
                let sport = Sport.resolve(slug: slug)
                m.primarySport = sport; m.sports = [sport]
                m.seasonsBySport = [sport: phase]; m.defaultSeason = phase
                m.equipment = [.bodyweight]; m.liftDaysPerWeek = 3
                let p = Planner.generate(memory: m, routines: [])
                for d in p.days where d.kind == .lift {
                    let w = d.generatedWorkout
                    XCTAssertFalse(w?.exercises.isEmpty ?? true, "[\(slug)/\(phase.rawValue)] bodyweight user got an empty lift day")
                    XCTAssertGreaterThanOrEqual(w?.exercises.count ?? 0, AuthoredRoutineSelector.minimumMovements,
                                                "[\(slug)/\(phase.rawValue)] bodyweight user got \(w?.exercises.count ?? 0) movements")
                }
            }
        }
    }
}
