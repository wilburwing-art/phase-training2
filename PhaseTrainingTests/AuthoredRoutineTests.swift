// AuthoredRoutineTests.swift — Phase 2 authored-routine selection + build.
//
// Exercises the real bundled coach.db: climbing has curated authored routines
// per season phase (in-season antagonist #1, pre-season #2/#10, off-season
// #3/#80). These prove the selector resolves them deterministically and the
// builder turns one into a runnable GeneratedWorkout with authored sets/reps.

import XCTest
@testable import PhaseTraining

final class AuthoredRoutineTests: XCTestCase {

    func testSelectClimbingInSeasonReturnsAntagonistRoutine() {
        // In-season climbing has exactly one full-session authored routine:
        // id 1, "Climber Antagonist & Push (In-Season)".
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .inSeason, sessionIndex: 0),
            1)
    }

    func testSelectIsDeterministic() {
        let a = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .preSeason, sessionIndex: 0)
        let b = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .preSeason, sessionIndex: 0)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testSelectRotatesAcrossMultipleLiftDays() {
        // Pre-season climbing has two full-session routines (#2, #10); a second
        // lift slot should resolve to the other one.
        let first = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .preSeason, sessionIndex: 0)
        let second = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .preSeason, sessionIndex: 1)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
    }

    func testSelectUnknownSportReturnsNil() {
        // A sport with no authored routines at all falls through to the season
        // engine (nil).
        XCTAssertNil(
            AuthoredRoutineSelector.select(sportSlug: "nonexistent-sport-xyz", phase: .inSeason, sessionIndex: 0))
    }

    func testSkiStaysOnSeasonEngine() {
        // Alpine skiing is season-engine supported and NOT a pilot sport, so
        // authored selection must fall through (nil) — the flagship season
        // experience is unchanged even though coach.db has some ski routines.
        XCTAssertNil(
            AuthoredRoutineSelector.select(sportSlug: "alpine-skiing", phase: .inSeason, sessionIndex: 0))
    }

    func testMountainBikingInSeasonIsServedAuthored() {
        // The season engine doesn't support MTB, but coach.db curates a
        // dryland session for it (id 24, "Cyclist In-Season Maintenance") — so
        // authored selection now serves MTB where the engine returned an empty
        // Rest. This is the original-request win.
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "mountain-biking", phase: .inSeason, sessionIndex: 0),
            24)
    }

    func testDisabledFlagFallsThrough() {
        UserDefaults.standard.set(false, forKey: AuthoredRoutineSelector.enabledKey)
        defer { UserDefaults.standard.removeObject(forKey: AuthoredRoutineSelector.enabledKey) }
        XCTAssertNil(
            AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .inSeason, sessionIndex: 0))
    }

    // MARK: - Onboarding gate: plannable sports

    func testPlannableIncludesEngineAndOutdoorAuthoredSports() {
        XCTAssertTrue(SportCatalog.isPlannable("alpine-skiing"), "ski = engine-supported")
        XCTAssertTrue(SportCatalog.isPlannable("climbing"), "climbing = engine-supported")
        XCTAssertTrue(SportCatalog.isPlannable("snowboarding"), "outdoor authored w/ coverage")
        XCTAssertTrue(SportCatalog.isPlannable("mountain-biking"), "outdoor authored w/ coverage")
    }

    func testPlannableExcludesNonOutdoorAndUnknownSports() {
        XCTAssertFalse(SportCatalog.isPlannable("golf"), "has routines but not an outdoor sport")
        XCTAssertFalse(SportCatalog.isPlannable("pickleball"))
        XCTAssertFalse(SportCatalog.isPlannable("nonexistent-sport-xyz"))
    }

    func testMountainBikingPreSeasonServesDistilledRoutines() {
        // MTB now has real pre-season (build) content — #299 / #300 — so lift
        // days rotate through them instead of falling back to off-season.
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "mountain-biking", phase: .preSeason, sessionIndex: 0), 299)
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "mountain-biking", phase: .preSeason, sessionIndex: 1), 300)
    }

    func testMTBPreSeasonRoutineBuildsRunnableWorkout() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "mountain-biking")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 299, memory: memory, context: .empty, focus: .fullBodyA)
        XCTAssertEqual(workout?.exercises.count, 7)
        // Signature MTI movements resolved to real catalog ids so they log.
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false)
        XCTAssertTrue(workout?.exercises.contains { $0.name == "Scotty Bobs" } ?? false)
        XCTAssertTrue((workout?.title ?? "").contains("MTB Pre-Season"))
    }

    func testMountainBikingHasEveryPhaseCovered() {
        // base / build / maintenance / off_season all resolve for MTB now.
        for phase in [SeasonPhase.offSeason, .preSeason, .inSeason, .maintenance, .eventPrep] {
            XCTAssertNotNil(
                AuthoredRoutineSelector.select(sportSlug: "mountain-biking", phase: phase, sessionIndex: 0),
                "MTB should serve a routine for \(phase)")
        }
    }

    // MARK: - Phase 3: distilled snowboarding routines are served

    func testSnowboardingPreSeasonServesDistilledRoutines() {
        // Phase 3 landed splitboard pre-season Strength A (#295) + B (#296);
        // two lift slots rotate through them.
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "snowboarding", phase: .preSeason, sessionIndex: 0), 295)
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "snowboarding", phase: .preSeason, sessionIndex: 1), 296)
    }

    func testSnowboardingInSeasonServesMaintenance() {
        XCTAssertEqual(
            AuthoredRoutineSelector.select(sportSlug: "snowboarding", phase: .inSeason, sessionIndex: 0), 297)
    }

    func testDistilledSnowboardRoutineBuildsRunnableWorkout() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "snowboarding")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 295, memory: memory, context: .empty, focus: .fullBodyA)
        XCTAssertEqual(workout?.exercises.count, 6)
        // Signature movements resolved to real catalog ids so they log normally.
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false)
        XCTAssertTrue((workout?.title ?? "").contains("Splitboard"))
    }

    func testSnowboardingPrimaryGeneratesAuthoredNonEmptyPlan() {
        // Full integration: an unsupported-but-plannable primary sport produces
        // a real plan (default weekly shape) whose lift days are filled from
        // authored routines — never the season engine's empty Rest.
        var m = TrainingMemory()
        let sb = Sport.resolve(slug: "snowboarding")
        m.primarySport = sb
        m.sports = [sb]
        m.seasonsBySport = [sb: .preSeason]
        m.defaultSeason = .preSeason
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        let plan = Planner.generate(memory: m, routines: [])
        let liftDays = plan.days.filter { $0.kind == .lift }
        XCTAssertFalse(liftDays.isEmpty, "snowboarding should still get lift days (default shape)")
        for d in liftDays {
            XCTAssertFalse(d.generatedWorkout?.exercises.isEmpty ?? true,
                           "snowboard lift day must not be empty")
            XCTAssertTrue(d.generatedWorkout?.provenance.contains("Authored") ?? false,
                          "snowboard lift day should be authored: \(d.generatedWorkout?.provenance ?? "nil")")
        }
    }

    // MARK: - Easy Strength: the generic cross-sport base

    func testEasyStrengthIsTheGeneralFitnessBase() {
        let ids = CoachDatabase.shared.authoredRoutineIds(
            sportSlug: "general-fitness", phaseLabels: AuthoredRoutineSelector.allPhaseLabels)
        XCTAssertTrue(ids.contains(298), "Easy Strength (#298) should be the general-fitness base")
    }

    func testSnowboardingOffSeasonRotationIncludesEasyStrength() {
        // Off-season maps to [off_season, base]; snowboarding now carries its
        // splitboard off-season (#70) + the Easy Strength base (#298).
        let served = (0..<4).compactMap {
            AuthoredRoutineSelector.select(sportSlug: "snowboarding", phase: .offSeason, sessionIndex: $0)
        }
        XCTAssertTrue(served.contains(298), "Easy Strength should rotate into snowboarding off-season")
    }

    func testEasyStrengthBuildsRunnableWorkout() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "snowboarding")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 298, memory: memory, context: .empty, focus: .fullBodyA)
        XCTAssertEqual(workout?.exercises.count, 6)
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false)
        XCTAssertTrue((workout?.title ?? "").contains("Easy Strength"))
    }

    func testWorkoutBuildsFromAuthoredRoutinePreservingSetsReps() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "climbing")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 1, memory: memory, context: .empty, focus: .fullBodyA)
        XCTAssertNotNil(workout)
        XCTAssertFalse(workout?.exercises.isEmpty ?? true)
        // Named + attributed so Today shows a recognizable authored session.
        XCTAssertTrue((workout?.provenance ?? "").lowercased().contains("authored"))
        XCTAssertFalse((workout?.title ?? "").isEmpty)
        // Sets/reps come straight from the authored routine.
        if let first = workout?.exercises.first {
            XCTAssertGreaterThan(first.sets, 0)
            XCTAssertFalse(first.reps.isEmpty)
        }
    }
}
