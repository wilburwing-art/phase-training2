// SupportSchedulerTest — invariants for the primary/support de-confliction
// layer (PLAN-primary-support.md).
//
// Most tests run on SYNTHETIC GeneratedWorkouts (the scheduler is a pure
// post-pass over persisted content, so no coach.db needed — no empty-catalog
// flake). One integration test runs the real SportSeasonGenerator week
// through the scheduler, gated on the DB being open.
//
// Assertions follow the invariant/metamorphic harness conventions
// (GeneratorInvariantTest): enumerate deterministic grids, assert behavior
// not names, keep orderings non-strict where a sparse effect could flake.

import XCTest
@testable import PhaseTraining

final class SupportSchedulerTest: XCTestCase {

    // MARK: - Fixtures

    /// A synthetic session; load = Σ sets × RPE, so (sets, rpe) pairs pin the
    /// heaviness ranking exactly.
    private func workout(_ title: String, _ shape: [(sets: Int, rpe: String?)]) -> GeneratedWorkout {
        let exercises = shape.enumerated().map { i, s in
            GeneratedExercise(id: "\(title)-\(i)", exerciseId: 1000 + i,
                              name: "\(title) ex\(i)", isCompound: i == 0,
                              sets: s.sets, reps: "5", restSeconds: 120, rpe: s.rpe)
        }
        return GeneratedWorkout(title: title, summary: "\(exercises.count) movements",
                                exercises: exercises, estimatedMinutes: 45,
                                provenance: "test", focus: .fullBodyA)
    }

    /// Off-season-shaped ski week: one clearly-heaviest session.
    private func skiWeek() -> [GeneratedWorkout] {
        [workout("Heavy", [(5, "8-9"), (4, "8"), (4, "7-8"), (3, "7")]),
         workout("Medium", [(4, "7"), (3, "7"), (3, "6-7"), (3, "6")]),
         workout("Light", [(3, "6"), (3, "6"), (2, "5-6"), (2, "5")])]
    }

    private func pattern(_ days: [(Weekday, SupportMagnitude)],
                         variant: SportVariant = .sportRoute) -> SupportPattern {
        SupportPattern(sportSlug: "climbing", variant: variant,
                       days: days.map { SupportDay(weekday: $0.0, magnitude: $0.1) })
    }

    private func heaviest(_ week: ScheduledWeek) -> ScheduledSession {
        week.sessions.max { SupportScheduler.sessionLoad($0.workout)
                          < SupportScheduler.sessionLoad($1.workout) }!
    }

    /// A deterministic grid of realistic patterns (the wedge: climb 1-3 days).
    private var patternGrid: [SupportPattern] {
        [pattern([(.tuesday, .medium), (.thursday, .medium)]),
         pattern([(.saturday, .big)]),
         pattern([(.tuesday, .medium), (.saturday, .big)]),
         pattern([(.tuesday, .light), (.thursday, .medium), (.saturday, .big)]),
         pattern([(.saturday, .big)], variant: .tradAlpine),
         pattern([(.wednesday, .big), (.saturday, .big)], variant: .tradAlpine),
         pattern([(.monday, .light), (.friday, .big)], variant: .boulder)]
    }

    // MARK: - No pattern → even spread

    func test_no_pattern_spreads_evenly_with_no_adjustments() {
        for count in 1...4 {
            let week = Array(skiWeek().prefix(count)) + (count == 4 ? [workout("Extra", [(3, "6")])] : [])
            let out = SupportScheduler.schedule(week: Array(week.prefix(count)),
                                                pattern: nil, primaryVariant: .backcountry)
            XCTAssertEqual(out.sessions.count, count)
            XCTAssertTrue(out.sessions.allSatisfy { $0.adjustments.isEmpty })
            // Max-spacing: no two sessions on adjacent days when count ≤ 3.
            if count <= 3 {
                let days = out.sessions.map(\.weekday).sorted()
                for (a, b) in zip(days, days.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(a.daysUntil(b), 2)
                }
            }
        }
    }

    // MARK: - Core invariants over the grid

    /// Sessions are never dropped, and never share a day with each other.
    func test_session_count_preserved_and_days_unique() {
        for p in patternGrid {
            let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                                primaryVariant: .backcountry)
            XCTAssertEqual(out.sessions.count, 3, "\(p.days)")
            XCTAssertEqual(Set(out.sessions.map(\.weekday)).count, 3, "\(p.days)")
        }
    }

    /// Rule 1: session days and support days are disjoint whenever the week
    /// has capacity (every grid pattern leaves ≥ 3 free days).
    func test_sessions_avoid_support_days() {
        for p in patternGrid {
            let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                                primaryVariant: .backcountry)
            let supportSet = Set(p.days.map(\.weekday))
            for s in out.sessions {
                XCTAssertFalse(supportSet.contains(s.weekday),
                               "\(s.workout.title) stacked on a support day: \(p.days)")
            }
        }
    }

    /// Rule 2: the heaviest session never sits inside a support day's
    /// restDaysBefore buffer (free legal days exist for every grid pattern).
    func test_heaviest_respects_recovery_buffer() {
        for p in patternGrid {
            let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                                primaryVariant: .backcountry)
            let h = heaviest(out)
            XCTAssertFalse(SupportScheduler.violatesBuffer(h.weekday, pattern: p,
                                                           primaryVariant: .backcountry),
                           "heaviest on \(h.weekday.short) violates buffer: \(p.days)")
        }
    }

    /// Rule 5: pure function — same inputs, same week.
    func test_deterministic() {
        for p in patternGrid {
            let a = SupportScheduler.schedule(week: skiWeek(), pattern: p, primaryVariant: .backcountry)
            let b = SupportScheduler.schedule(week: skiWeek(), pattern: p, primaryVariant: .backcountry)
            XCTAssertEqual(a, b)
        }
    }

    // MARK: - Metamorphic: upgrading a support day never pulls training closer

    /// light→big on the same weekday: the heaviest session's distance-before
    /// that day must not DECREASE (non-strict, per harness convention).
    func test_upgrade_magnitude_never_moves_heavy_session_closer() {
        let day = Weekday.saturday
        for variant in [SportVariant.sportRoute, .boulder, .tradAlpine] {
            var before: [SupportMagnitude: Int] = [:]
            for mag in SupportMagnitude.allCases {
                let p = pattern([(day, mag), (.tuesday, .light)], variant: variant)
                let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                                    primaryVariant: .backcountry)
                before[mag] = heaviest(out).weekday.daysUntil(day)
            }
            XCTAssertLessThanOrEqual(before[.light]!, before[.medium]!,
                                     "[\(variant)] light→medium pulled heavy session closer")
            XCTAssertLessThanOrEqual(before[.medium]!, before[.big]!,
                                     "[\(variant)] medium→big pulled heavy session closer")
        }
    }

    /// Adding a support day never increases the scheduled week's total volume.
    func test_adding_support_never_adds_volume() {
        let base = SupportScheduler.schedule(week: skiWeek(), pattern: nil,
                                             primaryVariant: .backcountry)
        let baseSets = base.sessions.flatMap { $0.workout.exercises }.reduce(0) { $0 + $1.sets }
        for p in patternGrid {
            let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                                primaryVariant: .backcountry)
            let sets = out.sessions.flatMap { $0.workout.exercises }.reduce(0) { $0 + $1.sets }
            XCTAssertLessThanOrEqual(sets, baseSets, "\(p.days)")
        }
    }

    // MARK: - Weekly budget (rule 4)

    /// tradAlpine big (1.0) + medium (0.5) = 1.5 session-equivalents → exactly
    /// one exercise dropped, from the heaviest session, floor respected.
    func test_budget_lightens_heaviest_session() {
        let p = pattern([(.wednesday, .medium), (.saturday, .big)], variant: .tradAlpine)
        let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                            primaryVariant: .backcountry)
        let heavy = out.sessions.first { $0.workout.title == "Heavy" }!
        XCTAssertEqual(heavy.workout.exercises.count, 3, "one exercise dropped from the heaviest")
        XCTAssertFalse(out.notes.isEmpty, "budget lighten must explain itself")
        // The other sessions keep their full content.
        for s in out.sessions where s.workout.title != "Heavy" {
            XCTAssertEqual(s.workout.exercises.count, 4)
        }
    }

    /// Sub-equivalent support load (sportRoute medium ×2 = 0.6) never lightens.
    func test_budget_below_one_equivalent_never_lightens() {
        let p = pattern([(.tuesday, .medium), (.thursday, .medium)])
        let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                            primaryVariant: .backcountry)
        XCTAssertTrue(out.notes.isEmpty)
        for s in out.sessions { XCTAssertEqual(s.workout.exercises.count, 4) }
    }

    // MARK: - Collision week: downgrade, never skip

    /// 6 support days leave 1 free day for 3 sessions: everything still
    /// scheduled, forced stacks are downgraded (floor 3) and explained.
    func test_collision_week_downgrades_not_skips() {
        let p = pattern([(.monday, .big), (.tuesday, .big), (.wednesday, .big),
                         (.thursday, .big), (.friday, .big), (.saturday, .big)],
                        variant: .tradAlpine)
        let out = SupportScheduler.schedule(week: skiWeek(), pattern: p,
                                            primaryVariant: .backcountry)
        XCTAssertEqual(out.sessions.count, 3, "collision must never skip a session")
        for s in out.sessions {
            XCTAssertGreaterThanOrEqual(s.workout.exercises.count, 3, "3-exercise floor")
        }
        let stacked = out.sessions.filter { s in p.days.contains { $0.weekday == s.weekday } }
        XCTAssertFalse(stacked.isEmpty, "with 1 free day, some sessions must stack")
        for s in stacked {
            XCTAssertFalse(s.adjustments.isEmpty, "\(s.workout.title) stacked without explanation")
        }
    }

    // MARK: - Integration: real generator output

    /// The PLAN's canonical fixture: splitboard off-season build × climbing
    /// in-season (Tue/Thu medium + Sat big). All core invariants over the
    /// real engine's week.
    func test_real_ski_offseason_week_with_climb_support() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db unavailable")
        var m = TrainingMemory()
        let sport = Sport(slug: "alpine-skiing", name: "Alpine Skiing")
        m.primarySport = sport
        m.seasonsBySport = [sport: .offSeason]
        m.defaultSeason = .offSeason
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        m.age = 32
        let athlete = AthleteState.from(m, variant: .backcountry)
        let week = SportSeasonGenerator.generateWeek(athlete)
        XCTAssertFalse(week.isEmpty, "generator produced no sessions — empty-catalog flake? re-run")

        let p = pattern([(.tuesday, .medium), (.thursday, .medium), (.saturday, .big)])
        let out = SupportScheduler.schedule(week: week, pattern: p,
                                            primaryVariant: .backcountry)
        XCTAssertEqual(out.sessions.count, week.count)
        let supportSet = Set(p.days.map(\.weekday))
        for s in out.sessions {
            XCTAssertFalse(supportSet.contains(s.weekday))
            XCTAssertGreaterThanOrEqual(s.workout.exercises.count, 3)
        }
        // Real off-season sessions share a rule → their loads often TIE. The
        // scheduler protects one maximal session (first by placement order);
        // the invariant on ties is that SOME max-load session is buffer-safe.
        let maxLoad = out.sessions.map { SupportScheduler.sessionLoad($0.workout) }.max()!
        let tiedHeaviest = out.sessions.filter {
            abs(SupportScheduler.sessionLoad($0.workout) - maxLoad) < 0.001
        }
        XCTAssertTrue(tiedHeaviest.contains { !SupportScheduler.violatesBuffer(
            $0.weekday, pattern: p, primaryVariant: .backcountry) },
            "no maximal-load session respects the recovery buffer")
    }
}
