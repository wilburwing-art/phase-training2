import XCTest
@testable import PhaseTraining

/// `WorkoutGenerator.represcribe` branches the store-level tests in
/// `PlanStoreSeamsTests` do not reach: a row whose exercise id is missing
/// from coach.db, and the summary and time estimate a full refresh rewrites.
final class WorkoutGeneratorRepresribeTests: XCTestCase {

    private let danglingId = 9_999_999

    private func memory() -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        return m
    }

    private func row(id: String, exerciseId: Int, name: String,
                     sets: Int = 3, reps: String = "8", rest: Int = 90,
                     notes: String? = nil, superset: Int? = nil) -> GeneratedExercise {
        GeneratedExercise(id: id, exerciseId: exerciseId, name: name,
                          pattern: "horizontal-push", isCompound: false,
                          sets: sets, reps: reps, restSeconds: rest,
                          notes: notes, supersetGroup: superset)
    }

    private func workout(_ rows: [GeneratedExercise]) -> GeneratedWorkout {
        GeneratedWorkout(title: "Mine", summary: "stored summary", exercises: rows,
                         estimatedMinutes: 999, provenance: "custom")
    }

    private func run(_ w: GeneratedWorkout, _ mode: PrescriptionRefreshMode) -> GeneratedWorkout {
        let m = memory()
        return WorkoutGenerator.represcribe(
            workout: w, mode: mode, focus: .push, memory: m,
            context: .empty)
    }

    private func realExercise() throws -> Exercise {
        let pool = CoachDatabase.shared.exercises(matchingPattern: "horizontal-push")
        return try XCTUnwrap(pool.first, "coach.db must have horizontal-push exercises")
    }

    // MARK: - Dangling id

    func testDanglingIdRowIsKeptUntouchedInBothModes() {
        XCTAssertNil(CoachDatabase.shared.exercise(id: danglingId))
        let stored = row(id: "cex-x", exerciseId: danglingId, name: "Gone Lift",
                         sets: 5, reps: "3", rest: 180, notes: "my cue", superset: 2)
        for mode in [PrescriptionRefreshMode.fullRefresh, .weightsOnly] {
            let out = run(workout([stored]), mode)
            XCTAssertEqual(out.exercises, [stored], "\(mode)")
        }
    }

    func testDanglingRowNextToRealRowKeepsItsPlace() throws {
        let ex = try realExercise()
        let gone = row(id: "cex-0", exerciseId: danglingId, name: "Gone Lift")
        let real = row(id: "cex-1", exerciseId: ex.id, name: "My Name For It",
                       notes: "elbows in", superset: 1)
        let out = run(workout([gone, real]), .fullRefresh)
        XCTAssertEqual(out.exercises.map(\.id), ["cex-0", "cex-1"])
        XCTAssertEqual(out.exercises[0], gone)
        XCTAssertEqual(out.exercises[1].name, "My Name For It")
        XCTAssertEqual(out.exercises[1].supersetGroup, 1)
        XCTAssertEqual(out.exercises[1].exerciseId, ex.id)
        XCTAssertTrue(out.exercises[1].notes?.hasPrefix("elbows in") == true,
                      "user note must lead: \(out.exercises[1].notes ?? "nil")")
    }

    // MARK: - Summary recompute

    /// A dangling row counts sets × (45 s + rest) + 30 s toward the estimate.
    /// 10 × (45 + 300) + 30 = 3480 s = 58 min.
    func testFullRefreshRecomputesSummaryFromDanglingRowTime() {
        let stored = row(id: "cex-x", exerciseId: danglingId, name: "Gone Lift",
                         sets: 10, rest: 300)
        let out = run(workout([stored]), .fullRefresh)
        XCTAssertEqual(out.estimatedMinutes, 58)
        XCTAssertEqual(out.summary, "1 movement · ~58 min")
    }

    func testFullRefreshEstimateHasFifteenMinuteFloor() {
        // 3 × (45 + 90) + 30 = 435 s = 7 min, floored to 15.
        let stored = row(id: "cex-x", exerciseId: danglingId, name: "Gone Lift")
        let out = run(workout([stored]), .fullRefresh)
        XCTAssertEqual(out.estimatedMinutes, 15)
        XCTAssertEqual(out.summary, "1 movement · ~15 min")
    }

    func testFullRefreshSummaryPluralisesMovements() throws {
        let ex = try realExercise()
        let out = run(workout([row(id: "a", exerciseId: ex.id, name: "A"),
                               row(id: "b", exerciseId: danglingId, name: "B")]),
                      .fullRefresh)
        XCTAssertNotEqual(out.estimatedMinutes, 999)
        XCTAssertGreaterThanOrEqual(out.estimatedMinutes, 15)
        XCTAssertEqual(out.summary, "2 movements · ~\(out.estimatedMinutes) min")
    }

    func testWeightsOnlyLeavesSummaryAndEstimateAlone() throws {
        let ex = try realExercise()
        let stored = row(id: "a", exerciseId: ex.id, name: "A", sets: 4, reps: "8-12", rest: 75)
        let out = run(workout([stored]), .weightsOnly)
        XCTAssertEqual(out.summary, "stored summary")
        XCTAssertEqual(out.estimatedMinutes, 999)
        XCTAssertEqual(out.exercises[0].sets, 4)
        XCTAssertEqual(out.exercises[0].reps, "8-12")
        XCTAssertEqual(out.exercises[0].restSeconds, 75)
    }

    // MARK: - Season-engine prescription

    private let mainLifts: Set<Demand> = [.maxStrength, .upperStrength, .pullStrength, .legStrength]

    /// A skier in off-season, a progressive-overload phase, so the advanced
    /// main-lift set is in play.
    private func skier(experience: ExperienceLevel = .intermediate, age: Int? = nil) -> TrainingMemory {
        var m = memory()
        m.primarySport = Sport.resolve(slug: "alpine-skiing")
        m.defaultSeason = .offSeason
        m.experience = experience
        m.age = age
        return m
    }

    private func refresh(_ exercises: [Exercise], focus: WorkoutFocus = .push,
                         memory m: TrainingMemory,
                         context: GeneratorContext = .empty) -> GeneratedWorkout {
        let rows = exercises.enumerated().map { i, ex in
            row(id: "cex-\(i)", exerciseId: ex.id, name: ex.name, sets: 9, reps: "1", rest: 1)
        }
        return WorkoutGenerator.represcribe(
            workout: workout(rows), mode: .fullRefresh, focus: focus, memory: m,
            context: context)
    }

    private struct Rx: Equatable {
        let sets: Int, reps: String, rest: Int, rpe: String?
    }

    private func rx(_ e: GeneratedExercise) -> Rx {
        Rx(sets: e.sets, reps: e.reps, rest: e.restSeconds, rpe: e.rpe)
    }

    /// What `SportSeasonGenerator.prescribe` emits for `m` under `demand` and
    /// the athlete's rule, read from the same scheme table it reads.
    private func seasonRx(_ m: SportMovement, demand: Demand, memory mem: TrainingMemory) -> Rx {
        let athlete = AthleteState.from(mem, variant: mem.primaryVariant)
        let rule = PhaseRule.resolve(sportSlug: athlete.sportSlug, variant: athlete.variant,
                                     season: athlete.season)
        let scheme = DemandScheme.scheme(for: demand, progression: rule.progression, goal: athlete.goal)
            .adjusted(experience: athlete.experience, age: athlete.age,
                      mainLift: mainLifts.contains(demand) && rule.progression == .progressiveOverload)
        return Rx(sets: m.protocolSets ?? scheme.setsMid,
                  reps: m.protocolReps ?? scheme.reps(forCatalog: m.catalogReps),
                  rest: m.protocolRestSeconds ?? scheme.restSeconds,
                  rpe: scheme.rpeString)
    }

    private func pool(_ m: TrainingMemory) -> [SportMovement] {
        CoachDatabase.shared.sportMovements(
            sport: SportSeasonGenerator.poolSlug(for: AthleteState.from(m).sportSlug))
    }

    /// A movement with a `sport_movements` row in the skier's pool, a demand
    /// and no cited protocol.
    private func seededMovement() throws -> (SportMovement, Exercise) {
        for m in pool(skier()) where m.protocolSets == nil && m.primaryDemand != nil {
            if let ex = CoachDatabase.shared.exercise(id: m.exerciseId) { return (m, ex) }
        }
        throw XCTSkip("no seeded skier movement without a protocol")
    }

    /// Compound pressing exercises with no `sport_movements` row in either
    /// pool the refresh reads, and no leg pattern (so they read as Push).
    private func unseededPushCompounds() -> [Exercise] {
        let seeded = Set((pool(skier()) + CoachDatabase.shared.sportMovements(sport: "general-fitness"))
            .map(\.exerciseId))
        let legs = Set(MovementCategory.legs.memberPatternSlugs)
        return CoachDatabase.shared.exercises(matchingPattern: "horizontal-push").filter {
            $0.isCompound && !seeded.contains($0.id)
                && Set(CoachDatabase.shared.patternsForExercise($0.id)).isDisjoint(with: legs)
        }
    }

    private func buildMovement(_ ex: Exercise, demand: Demand) -> SportMovement {
        SportMovement(exerciseId: ex.id, name: ex.name, catalogSlug: ex.slug, demands: [demand],
                      allowedPhases: [], allowedVariants: nil, fatigueCost: 0,
                      minExperienceRank: 0, injuryCaution: nil,
                      isCompound: ex.isCompound, isUnilateral: ex.isUnilateral,
                      catalogReps: ex.defaultReps)
    }

    /// The age cases the backlog item names: 55 is below the master age and
    /// prescribes the no-age dose; 60 and 70 carry the master-age 30 s of
    /// extra rest. Every case equals the season engine's prescription.
    private func assertAgeCases(_ ex: Exercise, movement: SportMovement, demand: Demand,
                                file: StaticString = #filePath, line: UInt = #line) {
        func refreshed(_ age: Int?) -> Rx { rx(refresh([ex], memory: skier(age: age)).exercises[0]) }
        let noAge = refreshed(nil)
        XCTAssertEqual(noAge, seasonRx(movement, demand: demand, memory: skier()), file: file, line: line)
        for age in [55, 60, 70] {
            XCTAssertEqual(refreshed(age), seasonRx(movement, demand: demand, memory: skier(age: age)),
                           "age \(age)", file: file, line: line)
        }
        XCTAssertEqual(refreshed(55), noAge, "55 is below the master age", file: file, line: line)
        for age in [60, 70] {
            XCTAssertEqual(refreshed(age).rest, noAge.rest + 30, "age \(age) rest", file: file, line: line)
        }
    }

    func testSeededMovementRefreshEqualsSeasonPrescriptionAcrossAges() throws {
        let (movement, ex) = try seededMovement()
        assertAgeCases(ex, movement: movement, demand: try XCTUnwrap(movement.primaryDemand))
    }

    func testUnseededSlotZeroCompoundRefreshEqualsSeasonPrescriptionAcrossAges() throws {
        let ex = try XCTUnwrap(unseededPushCompounds().first, "need an unseeded pressing compound")
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(ex, slotIdx: 0, focus: .push), .upperStrength)
        assertAgeCases(ex, movement: buildMovement(ex, demand: .upperStrength), demand: .upperStrength)
    }

    /// Advanced earns its extra set on a main-lift demand only: the slot-0
    /// compound (upperStrength) gains one, a pressing accessory (upperPush)
    /// does not.
    func testAdvancedAddsASetToTheLeadCompoundOnly() throws {
        let pushes = unseededPushCompounds()
        guard pushes.count >= 2 else { throw XCTSkip("need two unseeded pressing compounds") }
        let pair = Array(pushes.prefix(2))
        let inter = refresh(pair, memory: skier(experience: .intermediate)).exercises
        let adv = refresh(pair, memory: skier(experience: .advanced)).exercises
        XCTAssertEqual(adv[0].sets, inter[0].sets + 1, "lead compound")
        XCTAssertEqual(adv[1].sets, inter[1].sets, "accessory")
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(pair[1], slotIdx: 1, focus: .push), .upperPush)
    }

    /// Legs read as legStrength on every row, a main-lift demand, so the
    /// refresh withholds the advanced set from a leg row past the lead
    /// compound itself (11d 2.8).
    func testAdvancedNonLeadLegAccessoryGetsTheIntermediateSets() throws {
        let seeded = Set((pool(skier()) + CoachDatabase.shared.sportMovements(sport: "general-fitness"))
            .map(\.exerciseId))
        let legs = Set(MovementCategory.legs.memberPatternSlugs)
        let unseededLegs = legs.sorted()
            .flatMap { CoachDatabase.shared.exercises(matchingPattern: $0) }
            .filter { $0.isCompound && !seeded.contains($0.id) }
        var seen = Set<Int>()
        let pair = Array(unseededLegs.filter { seen.insert($0.id).inserted }.prefix(2))
        guard pair.count == 2 else { throw XCTSkip("need two unseeded leg compounds") }
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(pair[1], slotIdx: 1, focus: .legs), .legStrength)
        let inter = refresh(pair, focus: .legs, memory: skier(experience: .intermediate)).exercises
        let adv = refresh(pair, focus: .legs, memory: skier(experience: .advanced)).exercises
        XCTAssertEqual(adv[0].sets, inter[0].sets + 1, "lead compound")
        XCTAssertEqual(adv[1].sets, inter[1].sets, "leg accessory")
        XCTAssertEqual(adv[1].reps, inter[1].reps, "keeps the legStrength band")
    }

    /// A movement seeded only in the general-fitness pool keeps that row's
    /// demand for a skier, even where the category table would pick another.
    func testGeneralFitnessSeedSuppliesTheDemandWhenTheSportHasNone() throws {
        let m = skier()
        let sportIds = Set(pool(m).map(\.exerciseId))
        let gf = CoachDatabase.shared.sportMovements(sport: "general-fitness")
            .filter { !sportIds.contains($0.exerciseId) && $0.protocolSets == nil && $0.primaryDemand != nil }
        guard let (movement, ex) = gf.lazy.compactMap({ g in
            CoachDatabase.shared.exercise(id: g.exerciseId).map { (g, $0) }
        }).first else { throw XCTSkip("no general-fitness-only movement") }
        let out = SportSeasonGenerator.prescribeRefresh(
            ex, slotIdx: 0, focus: .legs, athlete: .from(m, variant: m.primaryVariant), strategy: .auto)
        XCTAssertEqual(rx(out), seasonRx(movement, demand: movement.primaryDemand!, memory: m))
    }

    // MARK: - Demand table

    /// An exercise carrying a pattern from `need` and no pattern outside
    /// `need` and `also`.
    private func exercise(patterns need: Set<String>, also: Set<String> = [],
                          compound: Bool? = nil) -> Exercise? {
        let allowed = need.union(also)
        for slug in need.sorted() {
            for ex in CoachDatabase.shared.exercises(matchingPattern: slug) {
                let have = Set(CoachDatabase.shared.patternsForExercise(ex.id))
                guard have.isSubset(of: allowed) else { continue }
                if let compound, ex.isCompound != compound { continue }
                return ex
            }
        }
        return nil
    }

    func testDemandTableByCategory() throws {
        let push = Set(MovementCategory.push.memberPatternSlugs)
        let pull = Set(MovementCategory.pull.memberPatternSlugs).subtracting(["elbow-flexion"])
        let legs = Set(MovementCategory.legs.memberPatternSlugs)
        let core = Set(MovementCategory.core.memberPatternSlugs)
        let arms: Set<String> = ["elbow-flexion", "elbow-extension"]
        func demand(_ ex: Exercise?, slot: Int, focus: WorkoutFocus = .fullBodyA) throws -> Demand {
            SportSeasonGenerator.refreshDemand(try XCTUnwrap(ex), slotIdx: slot, focus: focus)
        }
        let pushC = exercise(patterns: push, compound: true)
        XCTAssertEqual(try demand(pushC, slot: 0), .upperStrength)
        XCTAssertEqual(try demand(pushC, slot: 1), .upperPush)
        let pullC = exercise(patterns: pull, also: arms, compound: true)
        XCTAssertEqual(try demand(pullC, slot: 0), .pullStrength)
        XCTAssertEqual(try demand(pullC, slot: 2), .upperPull)
        let legC = exercise(patterns: legs, compound: true)
        XCTAssertEqual(try demand(legC, slot: 0), .legStrength)
        XCTAssertEqual(try demand(legC, slot: 3), .legStrength)
        XCTAssertEqual(try demand(exercise(patterns: core), slot: 0), .core)
        XCTAssertEqual(try demand(exercise(patterns: arms), slot: 1), .arms)
        // A slot-0 isolation keeps the accessory demand.
        if let pushIso = exercise(patterns: push, compound: false) {
            XCTAssertEqual(try demand(pushIso, slot: 0), .upperPush)
        }
    }

    /// No pattern maps to a category: the day's focus decides, slot-0
    /// compounds get the main-lift demand, and any other focus means core.
    func testDemandFallsBackToFocusThenCore() throws {
        let conditioning = Set(MovementCategory.conditioning.memberPatternSlugs)
        guard let ex = exercise(patterns: conditioning) else {
            throw XCTSkip("no conditioning-only exercise")
        }
        let lead = ex.isCompound
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(ex, slotIdx: 1, focus: .push), .upperPush)
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(ex, slotIdx: 1, focus: .pull), .upperPull)
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(ex, slotIdx: 0, focus: .legs), .legStrength)
        XCTAssertEqual(SportSeasonGenerator.refreshDemand(ex, slotIdx: 0, focus: .push),
                       lead ? .upperStrength : .upperPush)
        for focus in [WorkoutFocus.fullBodyA, .fullBodyB, .upper, .lower] {
            XCTAssertEqual(SportSeasonGenerator.refreshDemand(ex, slotIdx: 0, focus: focus), .core, "\(focus)")
        }
    }

    // MARK: - After prescribe

    /// Readiness scales sets the way a planned session does (60% at 0, the
    /// full dose at 1, untouched without data), and the coach's intensity
    /// bias rounds away from one.
    func testReadinessAndStrategyScaleSets() throws {
        let ex = try XCTUnwrap(unseededPushCompounds().first)
        let m = skier()
        func sets(readiness: Double?, bias: GeneratorStrategy.IntensityBias = .normal) -> Int {
            var athlete = AthleteState.from(m, variant: m.primaryVariant)
            athlete.readinessScore = readiness
            var strategy = GeneratorStrategy.auto
            strategy.intensityBias = bias
            return SportSeasonGenerator.prescribeRefresh(
                ex, slotIdx: 0, focus: .push, athlete: athlete, strategy: strategy).sets
        }
        let base = sets(readiness: nil)
        XCTAssertEqual(base, seasonRx(buildMovement(ex, demand: .upperStrength),
                                      demand: .upperStrength, memory: m).sets)
        XCTAssertEqual(sets(readiness: 1.0), base)
        XCTAssertEqual(sets(readiness: 0.0), max(1, Int((Double(base) * 0.6).rounded())))
        XCTAssertLessThan(sets(readiness: 0.0), base)
        XCTAssertEqual(sets(readiness: nil, bias: .push), Int((Double(base) * 1.15).rounded(.up)))
        XCTAssertEqual(sets(readiness: nil, bias: .deload), max(1, Int((Double(base) * 0.7).rounded(.down))))
    }

    /// The refreshed custom day reads readiness from the context only when it
    /// holds real data.
    func testRefreshReadsReadinessFromContext() throws {
        let ex = try XCTUnwrap(unseededPushCompounds().first)
        let m = skier()
        var low = GeneratorContext.empty
        low.readinessScore = 0.0
        low.hasReadinessData = true
        var noData = GeneratorContext.empty
        noData.readinessScore = 0.0
        noData.hasReadinessData = false
        let base = refresh([ex], memory: m).exercises[0].sets
        XCTAssertLessThan(refresh([ex], memory: m, context: low).exercises[0].sets, base)
        XCTAssertEqual(refresh([ex], memory: m, context: noData).exercises[0].sets, base)
    }

    /// Slot-0 compound gets the warm-up ramp; a later row does not.
    func testWarmUpRampOnLeadCompoundOnly() throws {
        let pushes = unseededPushCompounds()
        guard pushes.count >= 2 else { throw XCTSkip("need two unseeded pressing compounds") }
        let out = refresh(Array(pushes.prefix(2)), memory: skier()).exercises
        XCTAssertEqual(out[0].warmUpSets, WarmUpSet.standardRamp)
        XCTAssertNil(out[1].warmUpSets)
    }

    /// Time estimate is sets x (45 s + rest) + 30 s per refreshed row.
    func testEstimateUsesRefreshedSetsAndRest() throws {
        let pushes = unseededPushCompounds()
        guard pushes.count >= 2 else { throw XCTSkip("need two unseeded pressing compounds") }
        let out = refresh(Array(pushes.prefix(2)), memory: skier())
        let sec = out.exercises.reduce(0) { $0 + $1.sets * (45 + $1.restSeconds) + 30 }
        XCTAssertEqual(out.estimatedMinutes, max(15, sec / 60))
    }
}
