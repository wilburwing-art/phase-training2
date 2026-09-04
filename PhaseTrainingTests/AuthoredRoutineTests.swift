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
        // Off-season climbing has two qualifying full-session routines; a
        // second lift slot should resolve to the other one.
        //
        // This used to test pre-season climbing, which had "two full-session
        // routines (#2, #10)". #2 is `Climbing Finger Strength Protocol
        // (Repeaters)` — ONE exercise, 35 declared minutes. A hangboard
        // protocol is not a session, and serving it as a lift day is the
        // defect T1-9 closed by gating the selector at 3 exercises. Pre-season
        // now has exactly one qualifying routine, so it can no longer show
        // rotation.
        let first = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .offSeason, sessionIndex: 0)
        let second = AuthoredRoutineSelector.select(sportSlug: "climbing", phase: .offSeason, sessionIndex: 1)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
    }

    /// T1-9. A routine is served VERBATIM as a day's workout, so a one- or
    /// two-movement protocol must never be selectable as one. Five routines
    /// cleared every other filter (goal, duration >= 25) with fewer than three
    /// exercises.
    func testSelectorRejectsRoutinesTooThinToBeASession() {
        let db = CoachDatabase.shared
        for phase in SeasonPhase.allCases {
            for slug in ["climbing", "mountain-biking", "snowboarding",
                         "trail-running", "hiking-trekking", "thru-hiking",
                         "mountaineering", "general-fitness"] {
                let labels = AuthoredRoutineSelector.phaseLabels(for: phase)
                for id in db.authoredRoutineIds(sportSlug: slug, phaseLabels: labels) {
                    XCTAssertGreaterThanOrEqual(
                        db.exercises(forRoutineId: id).count, 3,
                        "[\(slug)/\(phase.rawValue)] routine \(id) is too thin to serve as a session")
                }
            }
        }
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
            forRoutineId: 299, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
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
            forRoutineId: 295, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
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
            forRoutineId: 298, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
        XCTAssertEqual(workout?.exercises.count, 6)
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false)
        XCTAssertTrue((workout?.title ?? "").contains("Easy Strength"))
    }

    func testWorkoutBuildsFromAuthoredRoutinePreservingSetsReps() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "climbing")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 1, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
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

    // MARK: - Injury-contraindication safety invariant
    //
    // The one invariant `GeneratorInvariantTest.swift` carried that has no
    // successor since 449bd8d deleted it with the legacy engine. It exists
    // because InjuriesEditorSheet:117 makes a promise to the user: "We'll
    // filter out exercises that aren't safe for the injuries you pick."
    //
    // Asserted through `WorkoutGenerator.generateLift` rather than against one
    // path, so it holds whichever way the request routes — authored routine for
    // the pilot/outdoor sports, season engine for ski. The authored path had NO
    // filter at all until this was fixed alongside this test.

    /// Every generated session, for every phase and session slot, must be free
    /// of exercises the user's declared injuries contraindicate.
    private func assertNoContraindicated(
        sportSlug: String, injurySlug: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: sportSlug)
        memory.userInjuries = [UserInjury(slug: injurySlug)]
        memory.equipment = [.fullGym]
        let profile = DemographicProfile.from(memory)

        XCTAssertFalse(
            profile.excludedExerciseIds.isEmpty,
            "[\(sportSlug)/\(injurySlug)] fixture is inert — this injury contraindicates "
            + "nothing in coach.db, so the assertion below could never fail",
            file: file, line: line)

        for phase in SeasonPhase.allCases {
            memory.defaultSeason = phase
            if let sport = memory.primarySport { memory.seasonsBySport = [sport: phase] }
            for slot in 0..<3 {
                let workout = WorkoutGenerator.generateLift(
                    liftIndex: slot, totalLifts: 3,
                    memory: memory, profile: profile,
                    hashSeed: "invariant-\(sportSlug)-\(phase.rawValue)-\(slot)")
                for ex in workout.exercises where ex.exerciseId > 0 {
                    XCTAssertFalse(
                        profile.excludedExerciseIds.contains(ex.exerciseId),
                        "[\(sportSlug)/\(injurySlug)/\(phase.rawValue)/slot \(slot)] "
                        + "served contraindicated exercise '\(ex.name)' (id \(ex.exerciseId))",
                        file: file, line: line)
                }
            }
        }
    }

    /// R2-01. The injury filter runs AFTER selection, so a 3-movement routine
    /// with one contraindicated lift became a 2-movement session and slipped
    /// under the floor T1-9 established. Measured against the shipped db, four
    /// selectable routines drop below 3 for some injury and one of them is
    /// reachable from a plannable sport: `Cyclist In-Season Maintenance`
    /// (3 movements) via mountain-biking, for lumbar-disc-herniation.
    func testInjuryFilterNeverLeavesASessionUnderTheMovementFloor() {
        for (slug, injury) in [("mountain-biking", "lumbar-disc-herniation"),
                               ("climbing", "finger-pulley"),
                               ("snowboarding", "acl-injury"),
                               ("trail-running", "acl-injury"),
                               // 1b (2026-09-04) added ~3,000 sourced-unreviewed
                               // rows; these are the broadest of them.
                               ("alpine-skiing", "pfps"),
                               ("climbing", "biceps-tendinopathy"),
                               ("mountain-biking", "hamstring-strain"),
                               ("hiking-trekking", "meniscus-tear")] {
            var memory = TrainingMemory()
            memory.primarySport = Sport.resolve(slug: slug)
            memory.userInjuries = [UserInjury(slug: injury)]
            memory.equipment = [.fullGym]
            let profile = DemographicProfile.from(memory)

            for phase in SeasonPhase.allCases {
                memory.defaultSeason = phase
                if let sport = memory.primarySport { memory.seasonsBySport = [sport: phase] }
                for slot in 0..<3 {
                    let w = WorkoutGenerator.generateLift(
                        liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                        hashSeed: "floor-\(slug)-\(phase.rawValue)-\(slot)")
                    // An empty workout is the "no supported sport" safety net and
                    // is a separate concern; what must not happen is a SHORT one.
                    if w.exercises.isEmpty { continue }
                    XCTAssertGreaterThanOrEqual(
                        w.exercises.count, AuthoredRoutineSelector.minimumMovements,
                        "[\(slug)/\(injury)/\(phase.rawValue)/slot \(slot)] served "
                        + "\(w.exercises.count) movements: '\(w.title)'")
                }
            }
        }
    }

    /// Climbing routes to the AUTHORED path (it is the declared pilot sport),
    /// and `Climbing Finger Strength Protocol (Repeaters)` is built entirely
    /// from a movement that finger-pulley contraindicates.
    func testAuthoredPathNeverServesContraindicatedExercise() {
        assertNoContraindicated(sportSlug: "climbing", injurySlug: "finger-pulley")
    }

    /// Mountain biking is authored-only — no season-engine backstop — so it
    /// exercises the broadened-phase and generic-base fallbacks too.
    func testAuthoredOnlySportNeverServesContraindicatedExercise() {
        assertNoContraindicated(sportSlug: "mountain-biking", injurySlug: "lumbar-disc-herniation")
    }

    /// Ski routes to the season engine, which has filtered at
    /// `SportSeasonGenerator.filteredPool` all along. Pins that it stays true.
    func testSeasonEnginePathNeverServesContraindicatedExercise() {
        assertNoContraindicated(sportSlug: "alpine-skiing", injurySlug: "acl-injury")
    }
}
