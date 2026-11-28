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
        XCTAssertTrue(SportCatalog.isPlannable("snowboarding"), "snowboarding is plannable")
        XCTAssertTrue(SportCatalog.isPlannable("mountain-biking"), "outdoor authored w/ coverage")
    }

    func testPlannableExcludesUnknownAndUncoveredSports() {
        XCTAssertFalse(SportCatalog.isPlannable("nonexistent-sport-xyz"))
        XCTAssertFalse(SportCatalog.isPlannable("misc-outdoor"), "no family row reaches it")
        // Has a family row (racquet) but no routines of its own until 11e 6.6.
        XCTAssertFalse(SportCatalog.isPlannable("tennis-clay"))
    }

    /// Backlog 11e 1.1: a sport with routines and a family row is plannable.
    /// Golf was held out as "not an outdoor sport" until the 2026-11-18 owner
    /// decision gave every catalog family a row.
    func testFamilySportsWithRoutinesArePlannable() {
        XCTAssertTrue(SportCatalog.isPlannable("golf"), "own family row, 4 routines")
        XCTAssertTrue(SportCatalog.isPlannable("tennis"), "inherits racquet-sports, 5 routines")
    }

    // MARK: - Family profile inheritance (11e 1.1)

    func testChildOfAnEngineSportInheritsAsGeneral() {
        let p = SportProfile.of("freestyle-skiing")
        XCTAssertEqual(p.rules, .general, "the ski engine does not know freestyle")
        XCTAssertEqual(p.signature, .eccentricLeg, "keeps the snow-sports signature")
        XCTAssertFalse(p.supportFeature)
        XCTAssertFalse(SportSeasonGenerator.supports("bouldering-indoor"))
        XCTAssertEqual(SportProfile.of("bouldering-indoor").family, .upperDominant)
    }

    func testVariantInheritsTheFamilyRoot() {
        XCTAssertEqual(SportProfile.familySlug(of: "tennis-clay"), "racquet-sports")
        XCTAssertEqual(SportProfile.of("tennis-clay"), SportProfile.of("racquet-sports"))
        XCTAssertNil(SportProfile.familySlug(of: "golf"), "has its own row")
    }

    func testOwnerOverridesBeatTheCatalogParent() {
        XCTAssertEqual(SportProfile.familySlug(of: "via-ferrata"), "mountaineering",
                       "via scrambling, not the climbing engine")
        XCTAssertEqual(SportProfile.familySlug(of: "geocaching"), "hiking-trekking")
        XCTAssertEqual(SportProfile.familySlug(of: "bikejoring"), "mountain-biking")
    }

    func testRootsWithNoRowStayOut() {
        XCTAssertNil(SportProfile.familySlug(of: "misc-outdoor"))
        XCTAssertNil(SportProfile.familySlug(of: "general-fitness"))
        XCTAssertFalse(SportCatalog.outdoorAuthoredSlugs.contains("misc-outdoor"))
        XCTAssertTrue(SportCatalog.outdoorAuthoredSlugs.contains("fencing"))
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
        // Full gym: this test pins the routine AS AUTHORED. An empty selection
        // reads as bodyweight-only since R2-05 and would swap or drop rows.
        memory.equipment = [.fullGym]
        memory.primarySport = Sport.resolve(slug: "mountain-biking")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 299, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
        // Rewritten from first principles 2026-09-04 (5b): the MTI-distilled
        // circuit with its branded movements is gone; this is leg endurance +
        // trunk from catalog exercises only.
        XCTAssertEqual(workout?.exercises.count, 6)
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false)
        XCTAssertTrue(workout?.exercises.contains { $0.name == "Walking Lunge" } ?? false)
        XCTAssertFalse(workout?.exercises.contains { $0.name.contains("Blaster") || $0.name == "Scotty Bobs" } ?? true,
                       "no MTI-branded movement may remain")
        XCTAssertTrue((workout?.title ?? "").contains("MTB Pre-Season"))
    }

    func testAuthoredRowsServeTheProgramsStatedRPE() {
        // Backlog 2026-11c 3.8: routine #1 says "Keep RPE 6-7 in-season", so
        // every served row carries it the way an engine row carries its RPE.
        var memory = TrainingMemory()
        memory.equipment = [.fullGym]
        memory.primarySport = Sport.resolve(slug: "climbing")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 1, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
        XCTAssertFalse(workout?.exercises.isEmpty ?? true)
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.rpe == "6-7" } ?? false,
                      "\(workout?.exercises.map(\.rpe) ?? [])")

        let mtb = AuthoredRoutine.workout(
            forRoutineId: 299, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
        XCTAssertTrue(mtb?.exercises.allSatisfy { $0.rpe == nil } ?? false,
                      "a routine that states no effort serves none")
    }

    func testMountainBikingHasEveryPhaseCovered() {
        // base / build / maintenance / off_season all resolve for MTB now.
        for phase in [SeasonPhase.offSeason, .preSeason, .inSeason, .maintenance, .eventPrep] {
            XCTAssertNotNil(
                AuthoredRoutineSelector.select(sportSlug: "mountain-biking", phase: phase, sessionIndex: 0),
                "MTB should serve a routine for \(phase)")
        }
    }

    // MARK: - Snowboarding sport days are served as written

    func testSnowboardingIsServedItsWrittenRoutines() {
        XCTAssertTrue(AuthoredRoutineSelector.shouldServeAuthored(sportSlug: "snowboarding"))
        let a = AuthoredRoutineSelector.select(sportSlug: "snowboarding", phase: .preSeason, sessionIndex: 0)
        let b = AuthoredRoutineSelector.select(sportSlug: "snowboarding", phase: .preSeason, sessionIndex: 1)
        XCTAssertEqual(Set([a, b].compactMap { $0 }), [295, 296], "Splitboard Pre-Season Strength A and B")
    }

    /// "As written" is a property: with no injury, full equipment, no
    /// preference and no same-day check-in, the served day is the routine's
    /// own rows, in order, with its own sets and reps. The engine may change a
    /// written day only for the listed reasons (injury, equipment, a sunk or
    /// disliked exercise, an unrecovered muscle, a same-day check-in), and
    /// each of those has its own test in this file and SorenessSelectionTests.
    func testWrittenRoutineIsServedExactlyAsWritten() throws {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "snowboarding")
        memory.defaultSeason = .preSeason
        if let s = memory.primarySport { memory.seasonsBySport = [s: .preSeason] }
        memory.experience = .advanced
        memory.equipment = [.fullGym]
        memory.sessionMinutes = 60
        memory.liftDaysPerWeek = 3
        let profile = DemographicProfile.from(memory)
        for id in [295, 296] {
            let written = CoachDatabase.shared.exercises(forRoutineId: id)
            let served = try XCTUnwrap(AuthoredRoutine.workout(
                forRoutineId: id, memory: memory, context: .empty,
                focus: .fullBodyA, profile: profile))
            XCTAssertEqual(served.exercises.map(\.exerciseId), written.map(\.exerciseId), "routine \(id): order and membership")
            XCTAssertEqual(served.exercises.map(\.sets), written.map { $0.sets ?? 0 }, "routine \(id): sets")
            XCTAssertEqual(served.exercises.map(\.reps), written.map { $0.reps ?? "" }, "routine \(id): reps")
        }
    }

    func testDistilledSnowboardRoutineBuildsRunnableWorkout() {
        var memory = TrainingMemory()
        // Full gym: this test pins the routine AS AUTHORED. An empty selection
        // reads as bodyweight-only since R2-05 and would swap or drop rows.
        memory.equipment = [.fullGym]
        memory.primarySport = Sport.resolve(slug: "snowboarding")
        let workout = AuthoredRoutine.workout(
            forRoutineId: 295, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))
        XCTAssertEqual(workout?.exercises.count, 6)
        // Signature movements resolved to real catalog ids so they log normally.
        XCTAssertTrue(workout?.exercises.allSatisfy { $0.exerciseId > 0 } ?? false)
        XCTAssertTrue((workout?.title ?? "").contains("Splitboard"))
    }

    func testAuthoredOnlyPrimaryGeneratesAuthoredNonEmptyPlan() {
        // Full integration: an unsupported-but-plannable primary sport produces
        // a real plan (default weekly shape) whose lift days are filled from
        // authored routines — never the season engine's empty Rest.
        var m = TrainingMemory()
        let sb = Sport.resolve(slug: "mountain-biking")
        m.primarySport = sb
        m.sports = [sb]
        m.seasonsBySport = [sb: .preSeason]
        m.defaultSeason = .preSeason
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        let plan = Planner.generate(memory: m, routines: [])
        let liftDays = plan.days.filter { $0.kind == .lift }
        XCTAssertFalse(liftDays.isEmpty, "mountain biking should still get lift days (default shape)")
        for d in liftDays where d.isComplementSession {
            XCTAssertFalse(d.generatedWorkout?.exercises.isEmpty ?? true, "complement day must not be empty")
        }
        // Sport sessions come from the authored routines; complement days
        // (SessionMix) come from the general pool.
        for d in liftDays where !d.isComplementSession {
            XCTAssertFalse(d.generatedWorkout?.exercises.isEmpty ?? true,
                           "MTB lift day must not be empty")
            XCTAssertTrue(d.generatedWorkout?.provenance.contains("Authored") ?? false,
                          "MTB lift day should be authored: \(d.generatedWorkout?.provenance ?? "nil")")
        }
    }

    // MARK: - Phase 3b coverage: every served sport has its own routine in every phase

    /// Sports whose days come from written routines: the sport profile table,
    /// filtered by the app's own gates. A season-engine sport with no routine
    /// in any phase (alpine, ice, mixed and trad climbing today) is built by
    /// the engine and never reaches the phase fallback, so it is out of scope;
    /// one with routines in any phase must have them in every phase.
    private var authoredServedPlannableSports: [String] {
        SportProfile.table.keys
            .filter { slug in
                guard SportCatalog.isPlannable(slug),
                      AuthoredRoutineSelector.shouldServeAuthored(sportSlug: slug) else { return false }
                if !SportSeasonGenerator.supports(slug) { return true }
                return !CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).isEmpty
            }
            .sorted()
    }

    func testEveryServedSportHasAServableRoutineInEveryPhase() {
        let sports = authoredServedPlannableSports
        let phases = SeasonPhase.allCases
        XCTAssertFalse(sports.isEmpty)
        XCTAssertFalse(phases.isEmpty)
        XCTAssertTrue(sports.contains("mountaineering"))
        XCTAssertTrue(phases.contains(.inSeason))

        var gapped: Set<String> = []
        for sport in sports {
            for phase in phases {
                let cell = "\(sport)/\(phase.rawValue)"
                let ownPool = CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: sport, phaseLabels: AuthoredRoutineSelector.phaseLabels(for: phase))
                let picked = AuthoredRoutineSelector.select(sportSlug: sport, phase: phase, sessionIndex: 0)
                let served = picked.map(ownPool.contains) ?? false
                if !served { gapped.insert(sport) }
                if Self.knownPhaseGapSports.contains(sport) { continue }
                XCTAssertTrue(served,
                              "\(cell): selector returned \(String(describing: picked)), own pool \(ownPool)")
            }
        }
        XCTAssertEqual(gapped.intersection(Self.knownPhaseGapSports), Self.knownPhaseGapSports,
                       "a known phase-gap sport now covers every phase; remove it from knownPhaseGapSports")
    }

    /// Family roots that got a profile row on 2026-11-18 (backlog 11e #1) with
    /// routines in some phases only. They serve another phase's routine in the
    /// gap. 11e Phases 3 and 4 distill the missing phases; each sport leaves
    /// this set when it covers all of them.
    static let knownPhaseGapSports: Set<String> = [
        "equestrian", "fishing-hunting", "golf", "martial-arts", "multi-sport-endurance", "racquet-sports",
        "skating-wheeled", "strength-fitness-sports", "surf-wave-sports",
        "yoga-movement",
    ]

    /// 11e 4.9: the in-season swim routines (Marques et al. 2020) serve inSeason
    /// for all three swim slugs, rotating between the A and B doses.
    func testInSeasonSwimWeekServesTheMarquesRoutines() {
        for slug in ["swimming", "lap-swimming", "open-water-swimming"] {
            XCTAssertEqual(
                Set(CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.phaseLabels(for: .inSeason))),
                [474, 475], slug)
            XCTAssertEqual(
                Set([0, 1].compactMap {
                    AuthoredRoutineSelector.select(sportSlug: slug, phase: .inSeason, sessionIndex: $0)
                }),
                [474, 475], slug)
        }
    }

    func testInSeasonMountaineeringWeekServesThe3bRoutines() {
        XCTAssertEqual(
            Set([0, 1].compactMap {
                AuthoredRoutineSelector.select(sportSlug: "mountaineering", phase: .inSeason, sessionIndex: $0)
            }),
            [310, 311])

        var m = TrainingMemory()
        let sport = Sport.resolve(slug: "mountaineering")
        m.primarySport = sport
        m.sports = [sport]
        m.seasonsBySport = [sport: .inSeason]
        m.defaultSeason = .inSeason
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.liftDaysPerWeek = 3
        let plan = Planner.generate(memory: m, routines: [])
        let served = plan.days
            .filter { $0.kind == .lift && !$0.isComplementSession }
            .compactMap { $0.generatedWorkout?.authoredRoutineId }
        XCTAssertFalse(served.isEmpty, "in-season mountaineering week has no authored sport day")
        XCTAssertTrue(Set(served).isSubset(of: [310, 311]), "served \(served)")
    }

    // MARK: - Easy Strength: the generic cross-sport base

    func testEasyStrengthIsTheGeneralFitnessBase() {
        let ids = CoachDatabase.shared.authoredRoutineIds(
            sportSlug: "general-fitness", phaseLabels: AuthoredRoutineSelector.allPhaseLabels)
        XCTAssertTrue(ids.contains(298), "Easy Strength (#298) should be the general-fitness base")
    }


    func testEasyStrengthBuildsRunnableWorkout() {
        var memory = TrainingMemory()
        // Full gym: this test pins the routine AS AUTHORED. An empty selection
        // reads as bodyweight-only since R2-05 and would swap or drop rows.
        memory.equipment = [.fullGym]
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
                    // R3-3. This used to `continue` on an empty workout, which
                    // made the test blind to the outcome the 1b injury rows
                    // make possible: filter everything out and return nothing.
                    // An empty day is allowed, but only as one of the two
                    // DECLARED empty states, so a silent one still fails.
                    if w.exercises.isEmpty {
                        XCTAssertTrue(
                            ["authored-no-fit", "no-supported-sport"].contains(w.provenance),
                            "[\(slug)/\(injury)/\(phase.rawValue)/slot \(slot)] served an empty "
                            + "workout with provenance '\(w.provenance)' — an empty day has to be "
                            + "one the app declares and explains, not a filtered-to-nothing session")
                        continue
                    }
                    XCTAssertGreaterThanOrEqual(
                        w.exercises.count, AuthoredRoutineSelector.minimumMovements,
                        "[\(slug)/\(injury)/\(phase.rawValue)/slot \(slot)] served "
                        + "\(w.exercises.count) movements: '\(w.title)'")
                }
            }
        }
    }

    // MARK: - R2-05: equipment on the authored path

    /// Measured before the fix: 69% of the exercises served to a bodyweight-only
    /// user on the authored path needed gear they said they did not have, and
    /// 103 of 113 routines carry a barbell or dumbbell movement, so a plain
    /// filter would have gutted the library. The rule is the season engine's:
    /// required slugs must be a subset of the allowed set.
    func testAuthoredPathNeverServesEquipmentTheUserLacks() {
        for (slug, gear) in [("mountain-biking", [Equipment.bodyweight]),
                             ("mountain-biking", [.dumbbells]),
                             ("snowboarding", [.bodyweight]),
                             ("hiking-trekking", [.dumbbells]),
                             ("climbing", [.bodyweight])] {
            var memory = TrainingMemory()
            memory.primarySport = Sport.resolve(slug: slug)
            memory.equipment = gear
            let profile = DemographicProfile.from(memory)
            let allowed = profile.allowedEquipmentSlugs
            XCTAssertFalse(allowed.isEmpty, "[\(slug)/\(gear)] fixture reads as full gym")

            for phase in SeasonPhase.allCases {
                memory.defaultSeason = phase
                if let sport = memory.primarySport { memory.seasonsBySport = [sport: phase] }
                for slot in 0..<3 {
                    let w = WorkoutGenerator.generateLift(
                        liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                        hashSeed: "gear-\(slug)-\(phase.rawValue)-\(slot)")
                    if w.exercises.isEmpty { continue }
                    XCTAssertGreaterThanOrEqual(
                        w.exercises.count, AuthoredRoutineSelector.minimumMovements,
                        "[\(slug)/\(gear)/\(phase.rawValue)/slot \(slot)] served "
                        + "\(w.exercises.count) movements: '\(w.title)'")
                    let reqs = CoachDatabase.shared.requiredEquipmentSlugs(
                        forExerciseIds: Set(w.exercises.map(\.exerciseId)))
                    for ex in w.exercises {
                        let need = reqs[ex.exerciseId] ?? []
                        XCTAssertTrue(
                            need.isEmpty || need.isSubset(of: allowed),
                            "[\(slug)/\(gear)/\(phase.rawValue)/slot \(slot)] served "
                            + "'\(ex.name)' needing \(need)")
                    }
                }
            }
        }
    }

    /// A gear gap is answered by a curated substitute where one exists (option
    /// A), and the swapped row says so. The row is dropped only when the
    /// substitutions table has nothing the user can equip.
    func testEquipmentGapIsFilledByASubstituteWhereOneExists() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "mountain-biking")
        memory.equipment = [.dumbbells]
        let profile = DemographicProfile.from(memory)

        var swaps: [String] = []
        for phase in SeasonPhase.allCases {
            memory.defaultSeason = phase
            if let sport = memory.primarySport { memory.seasonsBySport = [sport: phase] }
            for slot in 0..<3 {
                let w = WorkoutGenerator.generateLift(
                    liftIndex: slot, totalLifts: 3, memory: memory, profile: profile,
                    hashSeed: "swap-mtb-\(phase.rawValue)-\(slot)")
                swaps += w.exercises.compactMap { ex in
                    ex.notes.flatMap { $0.hasPrefix("Swapped in for") ? "\(ex.name): \($0)" : nil }
                }
                // A substitute never duplicates a movement already in the session.
                XCTAssertEqual(Set(w.exercises.map(\.exerciseId)).count, w.exercises.count,
                               "[\(phase.rawValue)/slot \(slot)] duplicate exercise after substitution")
            }
        }
        XCTAssertFalse(swaps.isEmpty, "no substitution fired for a dumbbells-only MTB user across every phase and slot")
    }

    /// The selector and the builder read the same resolved rows, so a routine
    /// the floor rejects for this user is never the one built.
    func testResolvedRowsDriveBothSelectorAndBuilder() {
        var memory = TrainingMemory()
        memory.primarySport = Sport.resolve(slug: "mountain-biking")
        memory.equipment = [.bodyweight]
        let profile = DemographicProfile.from(memory)
        for phase in SeasonPhase.allCases {
            guard let id = AuthoredRoutineSelector.select(
                sportSlug: "mountain-biking", phase: phase, sessionIndex: 0,
                experience: memory.experience,
                excludedExerciseIds: profile.excludedExerciseIds,
                allowedEquipmentSlugs: profile.allowedEquipmentSlugs) else { continue }
            let resolved = AuthoredRoutine.resolvedRows(forRoutineId: id, profile: profile,
                                                        experience: memory.experience)
            XCTAssertGreaterThanOrEqual(resolved.count, AuthoredRoutineSelector.minimumMovements)
            let built = AuthoredRoutine.workout(
                forRoutineId: id, memory: memory, context: .empty,
                focus: WorkoutFocus.lift(liftIndex: 0, totalLifts: 3), profile: profile)
            XCTAssertEqual(built?.exercises.map(\.exerciseId), resolved.map(\.exerciseId))
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

    // MARK: - Preferences reach authored days (P4 item 1)

    private func mtbMemory() -> TrainingMemory {
        var memory = TrainingMemory()
        memory.equipment = [.fullGym]
        memory.primarySport = Sport.resolve(slug: "mountain-biking")
        return memory
    }

    private func authoredNames(_ memory: TrainingMemory) -> [String] {
        AuthoredRoutine.workout(
            forRoutineId: 299, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory))?.exercises.map(\.name) ?? []
    }

    func testSunkAffinityRemovesRowFromAuthoredDay() {
        var memory = mtbMemory()
        let before = authoredNames(memory)
        guard let target = before.first else { return XCTFail("routine 299 built nothing") }
        memory.exerciseAffinities[target.lowercased()] = AthleteState.affinitySinkThreshold
        let after = authoredNames(memory)
        XCTAssertFalse(after.contains(target), "a sunk exercise must not be served")
        XCTAssertGreaterThanOrEqual(after.count, AuthoredRoutineSelector.minimumMovements)
    }

    func testDislikeKeywordRemovesRowFromAuthoredDay() {
        var memory = mtbMemory()
        guard let target = authoredNames(memory).first(where: { $0.contains("Lunge") }) else {
            return XCTFail("routine 299 has no lunge row")
        }
        memory.dislikes = ["lunge"]
        XCTAssertFalse(authoredNames(memory).contains { $0.lowercased().contains("lunge") },
                       "\(target) matches a dislike and must not be served or substituted in")
    }

    func testMildNegativeAffinityDoesNotRemoveRow() {
        var memory = mtbMemory()
        guard let target = authoredNames(memory).first else { return XCTFail("empty") }
        memory.exerciseAffinities[target.lowercased()] = AthleteState.affinitySinkThreshold + 1
        XCTAssertTrue(authoredNames(memory).contains(target))
    }

    func testPreferencesApplyBeforeTheMinimumMovementFloor() {
        // Rejecting every row with no usable substitute thins a routine below
        // the floor, so the selector must skip it rather than serve it.
        let memory = mtbMemory()
        let profile = DemographicProfile.from(memory)
        let rows = AuthoredRoutine.resolvedRows(forRoutineId: 299, profile: profile)
        var prefs = RoutinePreferences.none
        for r in rows { prefs.affinities[r.name.lowercased()] = AthleteState.affinitySinkThreshold }
        let thinned = AuthoredRoutine.resolvedRows(forRoutineId: 299, profile: profile, preferences: prefs)
        XCTAssertFalse(thinned.contains { prefs.rejects($0.name) })
        if thinned.count < AuthoredRoutineSelector.minimumMovements {
            XCTAssertNotEqual(
                AuthoredRoutineSelector.select(sportSlug: "mountain-biking", phase: .preSeason, sessionIndex: 0,
                                               preferences: prefs), 299)
        }
    }

    // MARK: - Rest values and time trimming (11d 2.1)

    func testParseRestReadsNoRestWordsAsZero() {
        XCTAssertEqual(AuthoredRoutine.parseRest("none"), 0)
        XCTAssertEqual(AuthoredRoutine.parseRest("built-in"), 0)
        XCTAssertEqual(AuthoredRoutine.parseRest("full recovery"), 0)
    }

    func testParseRestReadsTheTopOfARange() {
        XCTAssertEqual(AuthoredRoutine.parseRest("2-3 min"), 180)
        XCTAssertEqual(AuthoredRoutine.parseRest("2 min"), 120)
        XCTAssertEqual(AuthoredRoutine.parseRest("90 sec"), 90)
        XCTAssertEqual(AuthoredRoutine.parseRest("2:00"), 120)
        XCTAssertNil(AuthoredRoutine.parseRest(nil))
    }

    /// Catalog `exercises.default_rest` forms that the swap-in and custom
    /// workout paths read through the same parser (11d 2.7).
    func testParseRestReadsCatalogDefaultRestForms() {
        XCTAssertEqual(AuthoredRoutine.parseRest("60-90s"), 90)
        XCTAssertEqual(AuthoredRoutine.parseRest("45-60s"), 60)
        XCTAssertEqual(AuthoredRoutine.parseRest("90-180s"), 180)
        XCTAssertEqual(AuthoredRoutine.parseRest("3-5 min"), 300)
        XCTAssertEqual(AuthoredRoutine.parseRest("60 sec"), 60)
        XCTAssertEqual(AuthoredRoutine.parseRest("45s"), 45)
        XCTAssertEqual(AuthoredRoutine.parseRest("2 min between rounds"), 120)
        XCTAssertEqual(AuthoredRoutine.parseRest("90 sec seated"), 90)
        XCTAssertNil(AuthoredRoutine.parseRest("equal rest"))
    }

    func testNoRestRowsServeZeroRest() throws {
        let memory = TrainingMemory()
        let w = try XCTUnwrap(AuthoredRoutine.workout(
            forRoutineId: 325, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory)))
        let grind = w.exercises.filter { $0.id == "authored-325-5" || $0.id == "authored-325-6" }
        XCTAssertEqual(grind.count, 2)
        XCTAssertEqual(grind.map(\.restSeconds), [0, 0])
    }

    /// Routine 325's pull-up is written "2 reps in week 1, 5 reps by week 4"
    /// and routine 311's grind "Week 1 sets 30%, Week 3 sets 40%" (11d 2.5).
    /// The plan week picks the reps; weeks past the written ones hold the last.
    func testRepsByWeekFollowThePlanWeek() throws {
        let memory = TrainingMemory()
        func reps(_ routine: Int, _ position: Int, week: Int?) throws -> String {
            let w = try XCTUnwrap(AuthoredRoutine.workout(
                forRoutineId: routine, memory: memory, context: .empty, focus: .fullBodyA,
                profile: DemographicProfile.from(memory), planWeek: week))
            return try XCTUnwrap(w.exercises.first { $0.id == "authored-\(routine)-\(position)" }).reps
        }
        XCTAssertEqual(try reps(325, 4, week: 1), "2")
        XCTAssertEqual(try reps(325, 4, week: 4), "5")
        XCTAssertEqual(try reps(325, 4, week: 9), "5")
        XCTAssertEqual(try reps(325, 4, week: nil), "2-5")
        XCTAssertEqual(try reps(325, 2, week: 4), "4", "a row without weeks serves its reps every week")
        XCTAssertEqual(try reps(311, 1, week: 1), "30% of your 2-minute max")
        XCTAssertEqual(try reps(311, 1, week: 3), "40% of your 2-minute max")
    }

    /// A day that holds routine 325 by routineId (no generatedWorkout) serves
    /// the same per-week reps as the generator path (11d 2.9).
    func testRoutineIdDayServesRepsByPlanWeek() throws {
        let day = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 325)
        func pullUp(week: Int?) throws -> ExerciseTemplate {
            let t = try XCTUnwrap(day.workoutTemplate(planWeek: week))
            return try XCTUnwrap(t.exercises.first { $0.id == "rex-1434" })
        }
        XCTAssertEqual(try pullUp(week: 4).targetReps, 5)
        XCTAssertEqual(try pullUp(week: 1).targetReps, 2)
        XCTAssertEqual(try pullUp(week: nil).targetReps, 2, "no week serves the written \"2-5\"")
    }

    /// Routine 325's finisher (row 1437) rises 10, 15, 20 at sessions 7 and 13,
    /// weeks 4 and 7 at two sessions a week (11d 2.10).
    func testRoutine325FinisherRepsRiseByWeek() throws {
        let day = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 325)
        func finisher(week: Int?) throws -> ExerciseTemplate {
            let t = try XCTUnwrap(day.workoutTemplate(planWeek: week))
            return try XCTUnwrap(t.exercises.first { $0.id == "rex-1437" })
        }
        XCTAssertEqual(try finisher(week: 1).targetReps, 10)
        XCTAssertEqual(try finisher(week: 4).targetReps, 15)
        XCTAssertEqual(try finisher(week: 7).targetReps, 20)
        XCTAssertEqual(try finisher(week: 10).targetReps, 20)
        XCTAssertEqual(try finisher(week: nil).targetReps, 10)
    }

    func testRoutine325FinisherSetsRiseAtWeekFour() throws {
        let day = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 325)
        func finisher(week: Int?) throws -> ExerciseTemplate {
            let t = try XCTUnwrap(day.workoutTemplate(planWeek: week))
            return try XCTUnwrap(t.exercises.first { $0.id == "rex-1437" })
        }
        XCTAssertEqual(try finisher(week: 1).targetSets, 2)
        XCTAssertEqual(try finisher(week: 3).targetSets, 2)
        XCTAssertEqual(try finisher(week: 4).targetSets, 3)
        XCTAssertEqual(try finisher(week: 12).targetSets, 3)
        XCTAssertEqual(try finisher(week: nil).targetSets, 2)

        let memory = TrainingMemory()
        func served(week: Int) throws -> GeneratedExercise {
            let w = try XCTUnwrap(AuthoredRoutine.workout(
                forRoutineId: 325, memory: memory, context: .empty, focus: .fullBodyA,
                profile: DemographicProfile.from(memory), planWeek: week))
            return try XCTUnwrap(w.exercises.first { $0.id == "authored-325-7" })
        }
        XCTAssertEqual(try served(week: 1).sets, 2)
        XCTAssertEqual(try served(week: 4).sets, 3)
    }

    func testRoutine326FinisherRepsRiseByWeek() throws {
        let day = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 326)
        func finisher(week: Int?) throws -> ExerciseTemplate {
            let t = try XCTUnwrap(day.workoutTemplate(planWeek: week))
            return try XCTUnwrap(t.exercises.first { $0.id == "rex-1443" })
        }
        XCTAssertEqual(try finisher(week: 1).targetReps, 10)
        XCTAssertEqual(try finisher(week: 5).targetReps, 15)
        XCTAssertEqual(try finisher(week: 11).targetReps, 20)
        XCTAssertEqual(try finisher(week: 1).targetSets, 3)
    }

    func testSetsForWeekHoldsTheLastEntry() {
        let row = RoutineExercise(id: 1, exerciseId: 1, name: "X", position: 1,
                                  sets: 2, setsByWeek: [2, 3])
        XCTAssertEqual(row.sets(forWeek: nil), 2)
        XCTAssertEqual(row.sets(forWeek: 0), 2)
        XCTAssertEqual(row.sets(forWeek: 2), 3)
        XCTAssertEqual(row.sets(forWeek: 9), 3)
        XCTAssertNil(RoutineExercise(id: 1, exerciseId: 1, name: "X", position: 1)
            .sets(forWeek: 3))
    }

    func testTimeTrimNeverLeavesHalfASuperset() throws {
        let memory = TrainingMemory()
        for id in 325...327 {
            let w = try XCTUnwrap(AuthoredRoutine.workout(
                forRoutineId: id, memory: memory, context: .empty, focus: .fullBodyA,
                profile: DemographicProfile.from(memory), timeBudget: 30), "routine \(id)")
            let groups = Dictionary(grouping: w.exercises.compactMap(\.supersetGroup), by: { $0 })
            for (g, members) in groups {
                XCTAssertGreaterThan(members.count, 1, "routine \(id) serves group \(g) with one member")
            }
            XCTAssertGreaterThanOrEqual(w.exercises.count, AuthoredRoutineSelector.minimumMovements)
        }
    }

    func testPercentOfAMinuteMaxCountsAsSetsTimesNinety() throws {
        let memory = TrainingMemory()
        let w = try XCTUnwrap(AuthoredRoutine.workout(
            forRoutineId: 311, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory)))
        XCTAssertTrue(w.exercises.contains { $0.reps.contains("2-minute max") })
        let expected = max(15, w.exercises.reduce(0) { $0 + $1.sets * 90 } / 60)
        XCTAssertEqual(w.estimatedMinutes, expected)
    }

    /// Every routine served to a beginner, resolved on restricted equipment
    /// with and without an injury, swaps only to substitutes at or below
    /// beginner (11d 2.3). The unceiled pass is the measurement: it must find
    /// above-beginner swaps, or the assertion below could never fail.
    func testBeginnerSubstitutesStayAtOrBelowBeginner() {
        let db = CoachDatabase.shared
        let slugs = Set(Sport.catalog.map(\.slug)).sorted()
        var unceiledAbove = 0
        var swaps = 0
        var served = Set<Int>()
        for equipment in [[Equipment.bodyweight], [.dumbbells], [.bands], [.kettlebell],
                          [.pullUpBar, .bench]] {
            for injuries in [[], [UserInjury(slug: "lumbar-disc-herniation")]] {
                var memory = TrainingMemory()
                memory.experience = .beginner
                memory.equipment = equipment
                memory.userInjuries = injuries
                let profile = DemographicProfile.from(memory)
                // What the selector serves a beginner, before equipment: the
                // routine-level ceiling, which an authored-only sport with no
                // beginner routine skips.
                var beginnerIds = Set<Int>()
                for slug in slugs {
                    for phase in SeasonPhase.allCases {
                        for slot in 0..<4 {
                            if let id = AuthoredRoutineSelector.select(
                                sportSlug: slug, phase: phase, sessionIndex: slot,
                                experience: .beginner) { beginnerIds.insert(id) }
                        }
                    }
                }
                served.formUnion(beginnerIds)
                for id in beginnerIds.sorted() {
                    let unceiled = AuthoredRoutine.resolvedRows(forRoutineId: id, profile: profile)
                    let unceiledDiff = db.exerciseDifficulty(
                        forIds: Set(unceiled.filter { $0.swappedFrom != nil }.map(\.exerciseId)))
                    unceiledAbove += unceiled.filter {
                        $0.swappedFrom != nil && unceiledDiff[$0.exerciseId] != "beginner"
                    }.count

                    let rows = AuthoredRoutine.resolvedRows(forRoutineId: id, profile: profile,
                                                            experience: .beginner)
                    let swapped = rows.filter { $0.swappedFrom != nil }
                    swaps += swapped.count
                    let diff = db.exerciseDifficulty(forIds: Set(swapped.map(\.exerciseId)))
                    for row in swapped {
                        XCTAssertEqual(diff[row.exerciseId], "beginner",
                                       "routine \(id) \(equipment.map(\.rawValue)) injuries=\(injuries.count): "
                                       + "\(row.swappedFrom ?? "") swapped to \(row.name) (\(diff[row.exerciseId] ?? "nil"))")
                    }
                    // Nothing outside the swap changes: unswapped rows match the unceiled pass.
                    XCTAssertEqual(rows.filter { $0.swappedFrom == nil }.map(\.exerciseId),
                                   unceiled.filter { $0.swappedFrom == nil }.map(\.exerciseId))
                }
            }
        }
        print("11d-2.3 measure: beginner-served routines \(served.count), above-beginner swaps without ceiling \(unceiledAbove), beginner swaps with ceiling \(swaps)")
        XCTAssertGreaterThan(unceiledAbove, 0, "fixture is inert: no above-beginner substitute without the ceiling")
        XCTAssertGreaterThan(swaps, 0, "fixture is inert: no substitution fired under the ceiling")
    }

    // MARK: - Rank by duration (11c 3.5)

    func testFittingKeepsRoutinesWithinToleranceOfTheClosest() {
        let minutes = [1: 12, 2: 58, 3: 55, 4: 46]
        // Gaps 33, 13, 10, 1 at 45: the closest is 1, so 10 stays and 13 goes.
        XCTAssertEqual(AuthoredRoutineSelector.fitting([1, 2, 3, 4], budget: 45) { minutes[$0]! }, [3, 4])
        XCTAssertEqual(AuthoredRoutineSelector.fitting([7], budget: 45) { _ in 200 }, [7])
        XCTAssertEqual(AuthoredRoutineSelector.fitting([], budget: 45) { _ in 0 }, [])
    }

    private func cyclingMaintenancePool() -> (ids: [Int], minutes: [Int: Int]) {
        let ids = AuthoredRoutineSelector.candidates(sportSlug: "cycling", phase: .inSeason)
        let minutes = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, AuthoredRoutineSelector.estimatedMinutes(forRoutineId: $0, excluded: [], allowed: []))
        })
        return (ids, minutes)
    }

    func testSelectWithBudgetPicksTheRoutineClosestInLength() throws {
        XCTAssertTrue(AuthoredRoutineSelector.shouldServeAuthored(sportSlug: "cycling"))
        let (ids, minutes) = cyclingMaintenancePool()
        print("11c-3.5 cycling in-season pool minutes: \(ids.map { "\($0):\(minutes[$0]!)" })")
        try XCTSkipIf(ids.count < 2, "fixture: cycling in-season pool has \(ids.count) routine")
        let short = try XCTUnwrap(ids.min { minutes[$0]! < minutes[$1]! })
        // Fixture: one short routine and at least one well past it.
        XCTAssertLessThanOrEqual(minutes[short]!, 20)
        XCTAssertTrue(ids.contains { minutes[$0]! >= 40 }, "\(minutes)")
        for i in 0...3 {
            XCTAssertEqual(AuthoredRoutineSelector.select(sportSlug: "cycling", phase: .inSeason,
                                                          sessionIndex: i, sessionMinutes: 15),
                           short, "slot \(i) at 15 min")
            let long = AuthoredRoutineSelector.select(sportSlug: "cycling", phase: .inSeason,
                                                      sessionIndex: i, sessionMinutes: 60)
            XCTAssertNotNil(long)
            XCTAssertNotEqual(long, short, "slot \(i) at 60 min served the \(minutes[short]!)-minute routine")
        }
    }

    /// 11c 3.10. A coach-set length (`GeneratorStrategy.durationMinutes`)
    /// steers the authored pick the way the declared length does: a 60-minute
    /// user asking the coach for 15 minutes gets the session a 15-minute user
    /// gets, and at least one slot changes from the 60-minute pick.
    func testCoachDurationSteersTheAuthoredPick() throws {
        let (ids, _) = cyclingMaintenancePool()
        try XCTSkipIf(ids.count < 2, "fixture: cycling in-season pool has \(ids.count) routine")
        func cyclist(minutes: Int) -> TrainingMemory {
            var m = TrainingMemory()
            m.primarySport = Sport.resolve(slug: "cycling")
            m.defaultSeason = .inSeason
            if let s = m.primarySport { m.seasonsBySport = [s: .inSeason] }
            m.equipment = [.fullGym]
            m.sessionMinutes = minutes
            m.liftDaysPerWeek = 3
            return m
        }
        let long = cyclist(minutes: 60), short = cyclist(minutes: 15)
        var asked = GeneratorStrategy.auto
        asked.durationMinutes = 15
        var changed = 0
        for slot in 0..<3 {
            func build(_ m: TrainingMemory, _ s: GeneratorStrategy) -> GeneratedWorkout {
                WorkoutGenerator.generateLift(liftIndex: slot, totalLifts: 3, memory: m,
                                              profile: DemographicProfile.from(m),
                                              hashSeed: "11c-3.10-\(slot)", strategy: s)
            }
            let viaCoach = build(long, asked)
            let declared = build(short, .auto)
            XCTAssertEqual(viaCoach.title, declared.title, "slot \(slot)")
            XCTAssertEqual(viaCoach.exercises.map(\.exerciseId), declared.exercises.map(\.exerciseId), "slot \(slot)")
            if viaCoach.title != build(long, .auto).title { changed += 1 }
        }
        XCTAssertGreaterThan(changed, 0, "a 15-minute coach request changed no slot from the 60-minute pick")
    }

    func testSelectWithoutBudgetRotatesOverEveryCandidate() throws {
        let (ids, _) = cyclingMaintenancePool()
        try XCTSkipIf(ids.isEmpty, "fixture: no cycling in-season routines")
        for i in 0..<(ids.count * 2) {
            XCTAssertEqual(AuthoredRoutineSelector.select(sportSlug: "cycling", phase: .inSeason, sessionIndex: i),
                           ids[i % ids.count], "slot \(i)")
        }
        // A one-routine pool is served whatever the budget.
        var singles = 0
        for sport in Sport.catalog { for phase in SeasonPhase.allCases {
            let pool = AuthoredRoutineSelector.candidates(sportSlug: sport.slug, phase: phase)
            guard pool.count == 1 else { continue }
            singles += 1
            for budget in [15, 45, 120] {
                XCTAssertEqual(AuthoredRoutineSelector.select(sportSlug: sport.slug, phase: phase,
                                                              sessionIndex: 1, sessionMinutes: budget),
                               pool[0], "\(sport.slug)/\(phase.rawValue) at \(budget) min")
            }
        } }
        XCTAssertGreaterThan(singles, 0, "fixture: no one-routine pool in the catalog")
    }

    func testEstimatedMinutesMatchesTheServedSession() throws {
        let memory = TrainingMemory()
        let profile = DemographicProfile.from(memory)
        let (ids, _) = cyclingMaintenancePool()
        try XCTSkipIf(ids.isEmpty, "fixture: no cycling in-season routines")
        for id in ids + [311, 325] {
            for week in [1, 4] {
                let w = try XCTUnwrap(AuthoredRoutine.workout(
                    forRoutineId: id, memory: memory, context: .empty, focus: .fullBodyA,
                    profile: profile, planWeek: week), "routine \(id)")
                let served = w.exercises.reduce(0) { $0 + AuthoredRoutine.estimatedSeconds($1) } / 60
                XCTAssertEqual(AuthoredRoutineSelector.estimatedMinutes(
                    forRoutineId: id, excluded: profile.excludedExerciseIds,
                    allowed: profile.allowedEquipmentSlugs, preferences: RoutinePreferences.from(memory),
                    experience: memory.experience, planWeek: week), served, "routine \(id) week \(week)")
            }
        }
    }

    // MARK: - Source credit (11c 6.6)

    func testSourceCreditIsVerbatimSourceName() {
        XCTAssertEqual(AuthoredRoutine.sourceCredit(forRoutineId: 325),
                       "MTI In-Season Strength for Endurance Athletes V3 (distilled)")
        XCTAssertNil(AuthoredRoutine.sourceCredit(forRoutineId: 1), "routine 1 has no source_name")
        XCTAssertNil(AuthoredRoutine.sourceCredit(forRoutineId: -1))
    }

    func testDayCreditCoversAuthoredWorkoutAndRoutineIdDays() throws {
        let memory = TrainingMemory()
        let w = try XCTUnwrap(AuthoredRoutine.workout(
            forRoutineId: 325, memory: memory, context: .empty, focus: .fullBodyA,
            profile: DemographicProfile.from(memory)))
        let authored = DayPlan(date: Date(), kind: .lift, title: "Day", generatedWorkout: w)
        let byId = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 325)
        let credit = "MTI In-Season Strength for Endurance Athletes V3 (distilled)"
        XCTAssertEqual(authored.routineSourceCredit, credit)
        XCTAssertEqual(byId.routineSourceCredit, credit)

        var generated = w
        generated.authoredRoutineId = nil
        let plain = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 325,
                            generatedWorkout: generated)
        XCTAssertNil(plain.routineSourceCredit, "a generated workout outranks the routineId fallback")
    }

    func testCompleteCreditOnlyForTheDaysOwnWorkout() throws {
        let day = DayPlan(date: Date(), kind: .lift, title: "Day", routineId: 325)
        let id = try XCTUnwrap(day.workoutTemplate(planWeek: 1)?.id)
        XCTAssertEqual(day.routineSourceCredit(forSessionTemplateId: id, planWeek: 1),
                       "MTI In-Season Strength for Endurance Athletes V3 (distilled)")
        XCTAssertNil(day.routineSourceCredit(forSessionTemplateId: "freestyle", planWeek: 1))
    }
}
