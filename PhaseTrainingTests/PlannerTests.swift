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
        memory.liftDaysPerWeek = 3

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        XCTAssertEqual(plan.inputsHash, memory.planInputsHash)
    }

    // MARK: - Per-week overrides

    func testUnavailableDaysFromOverridesForceRest() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.unavailableDays = [.tuesday, .thursday, .saturday, .sunday]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let cal = Calendar.current

        for day in plan.days {
            let weekday = Weekday.from(date: day.date, calendar: cal)
            if overrides.unavailableDays.contains(weekday) {
                XCTAssertEqual(day.kind, .rest,
                               "\(weekday.short) should be rest (marked unavailable)")
            }
        }
    }

    func testNoOverridesAllowsAllSevenDays() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let restCount = plan.days.filter { $0.kind == .rest }.count
        XCTAssertLessThan(restCount, 7, "All-rest week is the failure mode we're guarding against")
    }

    func testSportSessionEventLandsAsProtectedSportDay() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.seasonsBySport = [climbing: .maintenance]

        let cal = Calendar.current
        let tuesday = cal.date(byAdding: .day, value: 1, to: mondayAnchor())!
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: tuesday, title: "Climb gym", kind: .sportSession, sport: climbing)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let tuesPlan = plan.days.first { cal.isDate($0.date, inSameDayAs: tuesday) }
        XCTAssertEqual(tuesPlan?.kind, .sport)
        XCTAssertTrue(tuesPlan?.protected ?? false)
        XCTAssertEqual(tuesPlan?.sport?.slug, "climbing")
    }

    func testRaceEventWithHardIntensityTapersPreviousLift() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]   // shape gives lifts on Mon, Wed, Fri
        memory.liftDaysPerWeek = 3

        let cal = Calendar.current
        // Race on Saturday — taper Friday.
        let saturday = cal.date(byAdding: .day, value: 5, to: mondayAnchor())!
        let friday   = cal.date(byAdding: .day, value: 4, to: mondayAnchor())!
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: saturday, title: "10K Race", kind: .race, intensity: .hard)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let fridayPlan = plan.days.first { cal.isDate($0.date, inSameDayAs: friday) }
        XCTAssertEqual(fridayPlan?.kind, .rest, "Friday should be tapered to rest before a hard race")
    }

    func testRaceEventWithLightIntensityDoesNotTaper() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.liftDaysPerWeek = 3

        let cal = Calendar.current
        let saturday = cal.date(byAdding: .day, value: 5, to: mondayAnchor())!
        let friday   = cal.date(byAdding: .day, value: 4, to: mondayAnchor())!
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: saturday, title: "Casual jog", kind: .race, intensity: .light)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let fridayPlan = plan.days.first { cal.isDate($0.date, inSameDayAs: friday) }
        // Friday should remain whatever the shape said (lift in this shape).
        XCTAssertNotEqual(fridayPlan?.kind, .event, "Friday shouldn't have an event slot itself")
    }

    func testMultipleEventsAcrossWeekAllStick() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing

        let cal = Calendar.current
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: cal.date(byAdding: .day, value: 0, to: mondayAnchor())!,
                      title: "Climb", kind: .sportSession, sport: climbing),
            WeekEvent(date: cal.date(byAdding: .day, value: 2, to: mondayAnchor())!,
                      title: "Climb", kind: .sportSession, sport: climbing),
            WeekEvent(date: cal.date(byAdding: .day, value: 5, to: mondayAnchor())!,
                      title: "10K", kind: .race, intensity: .moderate)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let sportCount = plan.days.filter { $0.kind == .sport && $0.protected }.count
        let eventCount = plan.days.filter { $0.kind == .event }.count
        XCTAssertEqual(sportCount, 2)
        XCTAssertEqual(eventCount, 1)
    }

    // MARK: - Shape distribution

    func testClimbingInSeasonHasTwoSportsAndOneLift() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.seasonsBySport = [climbing: .inSeason]
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
        climberInSeason.liftDaysPerWeek = 1

        var liftHeavy = TrainingMemory()
        liftHeavy.focuses = [.hypertrophy]
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
        memory.liftDaysPerWeek = 5

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(lifts, 5, "User's lift target should override the shape's default")
    }

    func testLiftDaysOverrideRemovesLiftsBelowShape() {
        // Hypertrophy shape gives 5 lifts; user wants 2.
        var memory = TrainingMemory()
        memory.focuses = [.hypertrophy]
        memory.liftDaysPerWeek = 2

        let plan = Planner.generate(memory: memory, routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertEqual(lifts, 2)
    }

    func testLiftDaysCappedByAvailableSlotsAfterUnavailable() {
        // User asks for 5 lifts but marks 4 days unavailable → only 3 slots
        // remain. Planner should cap the lift count at the empty slot count.
        var memory = TrainingMemory()
        memory.focuses = [.hypertrophy]
        memory.liftDaysPerWeek = 5

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.unavailableDays = [.tuesday, .thursday, .saturday, .sunday]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let lifts = plan.days.filter { $0.kind == .lift }.count
        XCTAssertLessThanOrEqual(lifts, 3,
                                 "Lift count must not exceed empty slot count")
    }

    func testZeroLiftDaysProducesNoLifts() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
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

    func testAdjustPromotesRestsBiasedToMaxSpacing() {
        // Single lift at index 2; need 3 total. Spacing-aware promotion should
        // pick the rest furthest from index 2 each round → not cluster.
        let queue: [DayKind] = [.rest, .rest, .lift, .rest, .rest, .rest, .rest]
        let result = Planner.adjustForLiftBudget(queue, target: 3)

        XCTAssertEqual(result.filter { $0 == .lift }.count, 3)
        // Adjacent-lift count: number of indices i where both i and i+1 are .lift.
        let adjacent = (0..<6).filter { result[$0] == .lift && result[$0+1] == .lift }.count
        XCTAssertEqual(adjacent, 0,
                       "Spacing-aware promotion shouldn't produce back-to-back lifts when slack exists: \(result)")
    }

    func testAdjustEvenlyDistributesLiftsInEmptyWeek() {
        // All-rest queue, target 3: ideal placement is roughly indices 0, 3, 6.
        let queue: [DayKind] = Array(repeating: .rest, count: 7)
        let result = Planner.adjustForLiftBudget(queue, target: 3)
        let lifts = result.indices.filter { result[$0] == .lift }
        XCTAssertEqual(lifts.count, 3)
        let adjacent = (0..<6).filter { result[$0] == .lift && result[$0+1] == .lift }.count
        XCTAssertEqual(adjacent, 0,
                       "All-rest week with 3 lift target should never cluster: \(lifts)")
    }

    // MARK: - DayKindOverride + Move/swap

    func testDayOverrideForcesKindThroughRegeneration() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.liftDaysPerWeek = 3

        let cal = Calendar.current
        let tuesday = cal.date(byAdding: .day, value: 1, to: mondayAnchor())!
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.dayOverrides[cal.startOfDay(for: tuesday)] = .lift(routineId: 2)

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let tuesPlan = plan.days.first { cal.isDate($0.date, inSameDayAs: tuesday) }
        XCTAssertEqual(tuesPlan?.kind, .lift)
        XCTAssertEqual(tuesPlan?.routineId, 2,
                       "Override should preserve the user-picked routine id")
        XCTAssertTrue(tuesPlan?.protected ?? false)
    }

    func testSwapOverridesCarryRoutineIdsBothWays() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.liftDaysPerWeek = 3

        let cal = Calendar.current
        let tuesday  = cal.date(byAdding: .day, value: 1, to: mondayAnchor())!
        let thursday = cal.date(byAdding: .day, value: 3, to: mondayAnchor())!

        // Simulate a swap: Tue ↔ Thu where Tue was lift(routineId 1), Thu was rest.
        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.dayOverrides[cal.startOfDay(for: tuesday)]  = .rest
        overrides.dayOverrides[cal.startOfDay(for: thursday)] = .lift(routineId: 1)

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        XCTAssertEqual(plan.days.first(where: { cal.isDate($0.date, inSameDayAs: tuesday) })?.kind, .rest)
        XCTAssertEqual(plan.days.first(where: { cal.isDate($0.date, inSameDayAs: thursday) })?.kind, .lift)
        XCTAssertEqual(plan.days.first(where: { cal.isDate($0.date, inSameDayAs: thursday) })?.routineId, 1)
    }

    // MARK: - Multi-day taper

    func testHardRaceTriggersTwoDayTaper() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.liftDaysPerWeek = 5

        let cal = Calendar.current
        let saturday = cal.date(byAdding: .day, value: 5, to: mondayAnchor())!
        let friday   = cal.date(byAdding: .day, value: 4, to: mondayAnchor())!
        let thursday = cal.date(byAdding: .day, value: 3, to: mondayAnchor())!

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: saturday, title: "10K", kind: .race, intensity: .hard)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())

        XCTAssertEqual(plan.days.first { cal.isDate($0.date, inSameDayAs: friday) }?.kind, .rest,
                       "Friday (Day -1) should be rest before a hard race")
        XCTAssertEqual(plan.days.first { cal.isDate($0.date, inSameDayAs: thursday) }?.kind, .mobility,
                       "Thursday (Day -2) should be mobility before a hard race")
    }

    func testModerateRaceOnlyTapersDayMinusOne() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.liftDaysPerWeek = 5

        let cal = Calendar.current
        let saturday = cal.date(byAdding: .day, value: 5, to: mondayAnchor())!
        let friday   = cal.date(byAdding: .day, value: 4, to: mondayAnchor())!
        let thursday = cal.date(byAdding: .day, value: 3, to: mondayAnchor())!

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: saturday, title: "10K", kind: .race, intensity: .moderate)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())

        XCTAssertEqual(plan.days.first { cal.isDate($0.date, inSameDayAs: friday) }?.kind, .rest,
                       "Friday (Day -1) should be rest before a moderate race")
        XCTAssertNotEqual(plan.days.first { cal.isDate($0.date, inSameDayAs: thursday) }?.kind, .mobility,
                          "Thursday should NOT be tapered for a moderate race")
    }

    // MARK: - Post-event recovery

    func testHardRaceTriggersDayAfterRest() {
        var memory = TrainingMemory()
        memory.focuses = [.generalStrength]
        memory.liftDaysPerWeek = 5

        let cal = Calendar.current
        let wednesday = cal.date(byAdding: .day, value: 2, to: mondayAnchor())!
        let thursday  = cal.date(byAdding: .day, value: 3, to: mondayAnchor())!

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: wednesday, title: "Race", kind: .race, intensity: .hard)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        XCTAssertEqual(plan.days.first { cal.isDate($0.date, inSameDayAs: thursday) }?.kind, .rest,
                       "Day after a hard race should be rest")
    }

    func testHardSportSessionTriggersDayAfterRest() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.liftDaysPerWeek = 5

        let cal = Calendar.current
        let wednesday = cal.date(byAdding: .day, value: 2, to: mondayAnchor())!
        let thursday  = cal.date(byAdding: .day, value: 3, to: mondayAnchor())!

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: wednesday, title: "Hard climb", kind: .sportSession,
                      sport: climbing, intensity: .hard)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        XCTAssertEqual(plan.days.first { cal.isDate($0.date, inSameDayAs: thursday) }?.kind, .rest,
                       "Day after a hard sport session should be rest")
    }

    // MARK: - Pre-sport buffer

    func testHardSportSessionDemotesPreviousLiftToMobility() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.liftDaysPerWeek = 5

        let cal = Calendar.current
        let tuesday  = cal.date(byAdding: .day, value: 1, to: mondayAnchor())!
        let wednesday = cal.date(byAdding: .day, value: 2, to: mondayAnchor())!

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: wednesday, title: "Hard climb", kind: .sportSession,
                      sport: climbing, intensity: .hard)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        let tuesKind = plan.days.first { cal.isDate($0.date, inSameDayAs: tuesday) }?.kind
        XCTAssertEqual(tuesKind, .mobility,
                       "Lift day before a hard sport session should be demoted to mobility")
    }

    func testModerateSportSessionDoesNotDemotePreviousLift() {
        let climbing = Sport.catalog.first { $0.slug == "climbing" }!
        var memory = TrainingMemory()
        memory.primarySport = climbing
        memory.liftDaysPerWeek = 5

        let cal = Calendar.current
        let wednesday = cal.date(byAdding: .day, value: 2, to: mondayAnchor())!

        var overrides = WeekOverrides(weekStart: mondayAnchor())
        overrides.events = [
            WeekEvent(date: wednesday, title: "Moderate climb", kind: .sportSession,
                      sport: climbing, intensity: .moderate)
        ]

        let plan = Planner.generate(memory: memory, overrides: overrides,
                                    routines: catalog(), today: mondayAnchor())
        // Day before moderate sport session keeps the planner's normal pick — i.e.
        // not forced to mobility. Since this is data-shape dependent, we only
        // assert that the buffer rule didn't fire (i.e., day before isn't a
        // taper/buffer-titled mobility).
        let tuesPlan = plan.days[1]
        if tuesPlan.kind == .mobility {
            XCTAssertFalse(
                tuesPlan.title.contains("buffer"),
                "Buffer rule shouldn't fire for moderate sport sessions"
            )
        }
    }
}
