// PlannerTests.swift — golden tests for Planner.generate.
//
// These exercise the rules engine in isolation by hand-feeding TrainingMemory
// + a synthetic routine catalog. No coach.db dependency. We assert structural
// invariants (always 7 contiguous days, fixed sports stick, unavailable days
// rest, hash matches inputs) plus shape distribution per (sport, season).

import XCTest
@testable import PhaseTraining

final class PlannerTests: XCTestCase {

    // MARK: - Synthetic routine catalog

    private func catalog() -> [Routine] {
        // Cover every goal the planner asks for, across difficulties + durations.
        return [
            // Strength
            Routine(id: 1, name: "Beginner Strength A", slug: "str-1",
                    description: nil, goal: "strength", difficulty: "beginner",
                    phase: nil, durationMinutes: 45, environment: "gym",
                    exerciseCount: 5, setCount: 15),
            Routine(id: 2, name: "Intermediate Push", slug: "str-2",
                    description: nil, goal: "strength", difficulty: "intermediate",
                    phase: nil, durationMinutes: 50, environment: "gym",
                    exerciseCount: 6, setCount: 18),
            Routine(id: 3, name: "Advanced Lower", slug: "str-3",
                    description: nil, goal: "strength", difficulty: "advanced",
                    phase: nil, durationMinutes: 60, environment: "gym",
                    exerciseCount: 7, setCount: 21),
            // Power
            Routine(id: 4, name: "Power Circuit", slug: "pwr-1",
                    description: nil, goal: "power", difficulty: "intermediate",
                    phase: nil, durationMinutes: 30, environment: "gym",
                    exerciseCount: 4, setCount: 12),
            // Mobility
            Routine(id: 5, name: "Hip Mobility Flow", slug: "mob-1",
                    description: nil, goal: "mobility", difficulty: "beginner",
                    phase: nil, durationMinutes: 20, environment: "home",
                    exerciseCount: 6, setCount: 0),
            Routine(id: 6, name: "T-spine Reset", slug: "mob-2",
                    description: nil, goal: "mobility", difficulty: "beginner",
                    phase: nil, durationMinutes: 15, environment: "home",
                    exerciseCount: 4, setCount: 0),
            // Recovery / prehab
            Routine(id: 7, name: "Climber Antagonist", slug: "preh-1",
                    description: nil, goal: "prehab", difficulty: "beginner",
                    phase: nil, durationMinutes: 20, environment: "home",
                    exerciseCount: 5, setCount: 10),
        ]
    }

    /// Fixed-Monday anchor so dates are deterministic across CI clocks.
    private func mondayAnchor() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11   // Monday, May 11, 2026
        return Calendar.current.date(from: c)!
    }

    // MARK: - Structural invariants

    func testProducesExactlySevenContiguousDays() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.availableDays = Weekday.allCases

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        XCTAssertEqual(plan.days.count, 7)

        let cal = Calendar.current
        for i in 1..<plan.days.count {
            let prev = plan.days[i - 1].date
            let next = plan.days[i].date
            let diff = cal.dateComponents([.day], from: prev, to: next).day
            XCTAssertEqual(diff, 1, "days[\(i)] should be exactly +1 day from days[\(i-1)]")
        }
    }

    func testInputsHashMatchesMemory() {
        var memory = TrainingMemory()
        memory.focuses = [.hypertrophy]
        memory.availableDays = [.monday, .wednesday, .friday]
        memory.liftDaysPerWeek = 3

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        XCTAssertEqual(plan.inputsHash, memory.planInputsHash)
    }

    // MARK: - Availability gating

    func testUnavailableDaysAreForcedRest() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.availableDays = [.monday, .wednesday, .friday]   // 3 days only

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let cal = Calendar.current

        for day in plan.days {
            let weekday = Weekday.from(date: day.date, calendar: cal)
            if !memory.availableDays.contains(weekday) {
                XCTAssertEqual(day.kind, .rest,
                               "\(weekday.short) should be rest (not in availableDays)")
            }
        }
    }

    func testEmptyAvailableDaysDoesNotForceAllRest() {
        // If user picked zero days (degenerate), the planner shouldn't blanket-rest;
        // it should treat the schedule as unconstrained.
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.availableDays = []

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let restCount = plan.days.filter { $0.kind == .rest }.count
        XCTAssertLessThan(restCount, 7, "All-rest week is the failure mode we're guarding against")
    }

    // MARK: - Fixed sport days

    func testFixedSportDaysStickAndAreProtected() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.seasonsBySport = [climbing: .maintenance]
        memory.availableDays = Weekday.allCases
        memory.fixedSportDays = [.tuesday: climbing, .friday: climbing]

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let cal = Calendar.current

        for day in plan.days {
            let weekday = Weekday.from(date: day.date, calendar: cal)
            if memory.fixedSportDays.keys.contains(weekday) {
                XCTAssertEqual(day.kind, .sport,
                               "\(weekday.short) should be sport (fixed)")
                XCTAssertTrue(day.protected,
                              "\(weekday.short) sport should be protected")
                XCTAssertEqual(day.sport?.slug, "climbing")
            }
        }
    }

    // MARK: - Shape distribution

    func testClimbingInSeasonHasTwoSportsAndOneLift() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.seasonsBySport = [climbing: .inSeason]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 1   // shape says 1, user agrees

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let kinds = plan.days.map(\.kind)

        XCTAssertEqual(kinds.filter { $0 == .sport }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == .lift }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .mobility }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .rest }.count, 3)
    }

    func testRunningOffSeasonFavorsLifts() {
        let running = Sport.catalog.first { $0.slug == "running" }!
        var memory = TrainingMemory()
        memory.primarySport = running
        memory.seasonsBySport = [running: .offSeason]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 3   // shape default = 3 lifts

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let kinds = plan.days.map(\.kind)

        XCTAssertEqual(kinds.filter { $0 == .lift }.count, 3)
        XCTAssertEqual(kinds.filter { $0 == .sport }.count, 2)
    }

    func testGeneralFitnessFallbackProducesUsableShape() {
        var memory = TrainingMemory()
        memory.primarySport = nil          // no sport
        memory.focuses = [.generalStrength]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 3

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let liftCount = plan.days.filter { $0.kind == .lift }.count
        XCTAssertGreaterThanOrEqual(liftCount, 3)
    }

    // MARK: - Routine selection

    func testLiftDaysCarryRoutineId() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.experience = .intermediate
        memory.sessionMinutes = 45
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 3

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        for day in plan.days where day.kind == .lift {
            XCTAssertNotNil(day.routineId,
                            "\(day.title) should have a routineId from the catalog")
        }
    }

    func testBeginnerExperienceExcludesAdvancedRoutines() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.experience = .beginner
        memory.sessionMinutes = 45
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 3

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let routineIds = plan.days.compactMap(\.routineId)
        XCTAssertFalse(routineIds.contains(3),
                       "Advanced Lower (id 3) should never appear for a beginner")
    }

    func testDeterministicGivenSameInputs() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.experience = .intermediate
        memory.sessionMinutes = 45
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 3

        let a = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let b = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())

        XCTAssertEqual(a.days.map(\.kind),     b.days.map(\.kind))
        XCTAssertEqual(a.days.map(\.routineId), b.days.map(\.routineId))
        XCTAssertEqual(a.inputsHash,           b.inputsHash)
    }

    func testDifferentMemoriesProduceDifferentPlans() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var climberInSeason = TrainingMemory()
        climberInSeason.primarySport = climbing
        climberInSeason.seasonsBySport = [climbing: .inSeason]
        climberInSeason.availableDays = Weekday.allCases
        climberInSeason.liftDaysPerWeek = 1

        var liftHeavy = TrainingMemory()
        liftHeavy.focuses = [.hypertrophy]
        liftHeavy.availableDays = Weekday.allCases
        liftHeavy.liftDaysPerWeek = 5

        let a = Planner.generate(memory: climberInSeason, routines: catalog(), today: mondayAnchor())
        let b = Planner.generate(memory: liftHeavy,       routines: catalog(), today: mondayAnchor())

        XCTAssertNotEqual(a.days.map(\.kind), b.days.map(\.kind))
        XCTAssertNotEqual(a.inputsHash, b.inputsHash)
    }

    // MARK: - liftDaysPerWeek override

    func testLiftDaysOverrideAddsLiftsBeyondShape() {
        // General-strength shape gives 3 lifts; user wants 5.
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 5

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(lifts, 5, "User's lift target should override the shape's default")
    }

    func testLiftDaysOverrideRemovesLiftsBelowShape() {
        // Hypertrophy shape gives 5 lifts; user wants 2.
        var memory = TrainingMemory()
        memory.focuses = [.hypertrophy]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 2

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(lifts, 2)
    }

    func testLiftDaysCappedByAvailableDayCount() {
        // 3 available days, user asks for 5 lifts → planner caps at 3.
        var memory = TrainingMemory()
        memory.focuses = [.hypertrophy]
        memory.availableDays = [.monday, .wednesday, .friday]
        memory.liftDaysPerWeek = 5

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertLessThanOrEqual(lifts, 3,
                                 "Lift count must not exceed available day count")
    }

    func testZeroLiftDaysProducesNoLifts() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 0

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(lifts, 0)
    }

    // MARK: - Per-sport season

    func testPerSportSeasonDrivesShapeForPrimary() {
        // Two sports with different seasons: primary's season is what shapes the week.
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        let skiing   = Sport.catalog.first { $0.slug == "alpine-skiing" }!
        var memory = TrainingMemory()
        memory.sports = [climbing, skiing]
        memory.primarySport = climbing
        memory.seasonsBySport = [climbing: .inSeason, skiing: .preSeason]
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 1

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let kinds = plan.days.map(\.kind)
        // Climbing in-season: 2 sport + 1 lift + 1 mobility + 3 rest.
        XCTAssertEqual(kinds.filter { $0 == .sport }.count, 2)
        XCTAssertEqual(kinds.filter { $0 == .lift }.count, 1)
    }

    func testPerSportSeasonFallsThroughToDefault() {
        // Primary sport has no entry in seasonsBySport → defaultSeason used.
        let cycling = Sport.catalog.first { $0.slug == "cycling" }!
        var memory = TrainingMemory()
        memory.sports = [cycling]
        memory.primarySport = cycling
        memory.seasonsBySport = [:]                  // empty
        memory.defaultSeason = .inSeason
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 1

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let kinds = plan.days.map(\.kind)
        // Cycling in-season: 3 rides + 1 lift + 3 rest.
        XCTAssertEqual(kinds.filter { $0 == .sport }.count, 3)
    }

    // MARK: - Multi-focus

    func testMultiFocusUsesFirstAsPrimary() {
        var memory = TrainingMemory()
        memory.focuses = [.mobility, .hypertrophy]    // primary = mobility
        memory.availableDays = Weekday.allCases
        memory.liftDaysPerWeek = 1

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let mobs = plan.days.filter { $0.kind == .mobility }.count
        // Mobility focus shape: 4 mobility / 3 rest. With liftDaysPerWeek=1 we
        // promote 1 of the 4 mobilities → lift, leaving ≥3 mobilities.
        XCTAssertGreaterThanOrEqual(mobs, 3)
    }

    // MARK: - adjustForLiftBudget unit

    func testAdjustDemotesExcessLiftsFromTheEnd() {
        let queue: [DayKind] = [.lift, .rest, .lift, .rest, .lift, .mobility, .rest]
        let result = Planner.adjustForLiftBudget(queue, target: 1)
        XCTAssertEqual(result.filter { $0 == .lift }.count, 1)
        XCTAssertEqual(result.first, .lift, "First lift should survive (early-week emphasis)")
    }

    func testAdjustPromotesRestsFromTheFront() {
        let queue: [DayKind] = [.rest, .rest, .lift, .rest, .mobility, .rest, .rest]
        let result = Planner.adjustForLiftBudget(queue, target: 4)
        XCTAssertEqual(result.filter { $0 == .lift }.count, 4)
        XCTAssertEqual(result[0], .lift, "Front rests should promote first")
    }
}
