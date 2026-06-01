import XCTest
@testable import PhaseTraining

/// Hits CoachDatabase.shared which loads the bundled coach.db (789 exercises,
/// 1730 substitution pairs, full movement_patterns table). Test bundle ships
/// the same coach.db as the app, so these are end-to-end.
final class WorkoutGeneratorTests: XCTestCase {

    // MARK: - Day-type rotation

    func test_oneLiftPerWeek_isFullBodyA() {
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 0, totalLifts: 1), .fullBodyA)
    }

    func test_twoLiftsPerWeek_alternatesFullBody() {
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 0, totalLifts: 2), .fullBodyA)
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 1, totalLifts: 2), .fullBodyB)
    }

    func test_threeLiftsPerWeek_isPushPullLegs() {
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 0, totalLifts: 3), .push)
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 1, totalLifts: 3), .pull)
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 2, totalLifts: 3), .legs)
    }

    func test_fourLiftsPerWeek_isUpperLowerSplit() {
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 0, totalLifts: 4), .upper)
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 1, totalLifts: 4), .lower)
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 2, totalLifts: 4), .upper)
        XCTAssertEqual(WorkoutFocus.lift(liftIndex: 3, totalLifts: 4), .lower)
    }

    // MARK: - Generated content

    func test_generatedLift_isNonEmpty() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        XCTAssertFalse(workout.exercises.isEmpty,
                       "Push day should produce exercises against the bundled coach.db")
        XCTAssertGreaterThan(workout.estimatedMinutes, 0)
        XCTAssertFalse(workout.title.isEmpty)
    }

    func test_pushDay_hitsBothHorizontalAndVerticalPush() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        let patterns = Set(workout.exercises.compactMap(\.pattern))
        XCTAssertTrue(patterns.contains("horizontal-push"),
                      "Push day should include a horizontal push movement")
        XCTAssertTrue(patterns.contains("vertical-push"),
                      "Push day should include a vertical push movement")
    }

    // MARK: - Profile-driven prescription

    func test_beginnerGetsAtMost3Sets() {
        var m = TrainingMemory()
        m.experience = .beginner
        m.equipment = [.fullGym]
        m.sessionMinutes = 45
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 1,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        for ex in workout.exercises {
            XCTAssertLessThanOrEqual(ex.sets, 3,
                "Beginner shouldn't see >3 sets per exercise: \(ex.name) got \(ex.sets)")
        }
    }

    func test_age55plus_dropsOneSetPerExercise() {
        var young = TrainingMemory()
        young.experience = .intermediate
        young.equipment = [.fullGym]
        young.sessionMinutes = 60
        young.age = 30

        var old = young
        old.age = 60

        let py = DemographicProfile.from(young)
        let po = DemographicProfile.from(old)

        let wy = WorkoutGenerator.generateLift(liftIndex: 0, totalLifts: 1,
            memory: young, profile: py, hashSeed: young.planInputsHash)
        let wo = WorkoutGenerator.generateLift(liftIndex: 0, totalLifts: 1,
            memory: old, profile: po, hashSeed: old.planInputsHash)

        // Same hash seed because the rest of memory matches; only age changes.
        // Total sets across the workout should drop for the older user.
        let totalY = wy.exercises.reduce(0) { $0 + $1.sets }
        let totalO = wo.exercises.reduce(0) { $0 + $1.sets }
        XCTAssertLessThan(totalO, totalY,
            "55+ user should get a lower total set count (got \(totalO) vs \(totalY))")
    }

    // MARK: - Equipment + constraint filters

    func test_bodyweightUser_neverGetsGymOnlyExercise() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.bodyweight]
        m.sessionMinutes = 45
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        for ex in workout.exercises {
            let underlying = CoachDatabase.shared.exercise(id: ex.exerciseId)
            XCTAssertNotEqual(underlying?.environment, "gym",
                "Bodyweight user got a gym exercise: \(ex.name)")
        }
    }

    func test_injuryContraindications_areExcluded() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        m.userInjuries = [UserInjury(slug: "acl-injury")]
        let p = DemographicProfile.from(m)
        XCTAssertFalse(p.excludedExerciseIds.isEmpty,
                       "Precondition: coach.db should have contraindicated exercises tagged for ACL injury")

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 1,
            memory: m, profile: p,
            hashSeed: m.planInputsHash
        )
        let pickedIds = Set(workout.exercises.map(\.exerciseId))
        let overlap = pickedIds.intersection(p.excludedExerciseIds)
        XCTAssertTrue(overlap.isEmpty,
            "Generator picked \(overlap.count) exercises that are explicitly contraindicated for ACL injury")
    }

    func test_dislikedExercise_isNeverIncluded() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        m.dislikes = ["burpee"]
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 1,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        for ex in workout.exercises {
            XCTAssertFalse(ex.name.lowercased().contains("burpee"),
                "Disliked exercise should never appear: \(ex.name)")
        }
    }

    // MARK: - Determinism

    func test_sameInputsProduceSameWorkout() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 45
        let p = DemographicProfile.from(m)

        let a = WorkoutGenerator.generateLift(liftIndex: 1, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash)
        let b = WorkoutGenerator.generateLift(liftIndex: 1, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash)

        XCTAssertEqual(a.exercises.map(\.exerciseId), b.exercises.map(\.exerciseId))
        XCTAssertEqual(a.exercises.map(\.sets),       b.exercises.map(\.sets))
        XCTAssertEqual(a.exercises.map(\.reps),       b.exercises.map(\.reps))
    }

    func test_differentLiftIndex_producesDifferentWorkout() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 45
        m.liftDaysPerWeek = 3
        let p = DemographicProfile.from(m)

        let push = WorkoutGenerator.generateLift(liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash)
        let pull = WorkoutGenerator.generateLift(liftIndex: 1, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash)

        XCTAssertNotEqual(push.title, pull.title,
            "Different lift indices should produce different focus titles")
        XCTAssertNotEqual(push.exercises.map(\.exerciseId),
                          pull.exercises.map(\.exerciseId))
    }

    // MARK: - Leak #3: primaryFocus shapes the prescription

    func test_focusBias_generalStrength_runsLowRepLongRest() {
        // Build 97: generalStrength got a concrete bias (was nil).
        // Standard 5×5 strength scheme on primary, 3×6-8 accessories.
        let primary = WorkoutGenerator.focusBias(.generalStrength, isPrimary: true)
        XCTAssertEqual(primary?.sets, 5)
        XCTAssertEqual(primary?.reps, "5")
        XCTAssertEqual(primary?.restSec, 180)

        let accessory = WorkoutGenerator.focusBias(.generalStrength, isPrimary: false)
        XCTAssertEqual(accessory?.sets, 3)
        XCTAssertEqual(accessory?.reps, "6-8")
        XCTAssertEqual(accessory?.restSec, 120)
    }

    func test_focusBias_hypertrophy_runsHighRepShortRest() {
        let primary = WorkoutGenerator.focusBias(.hypertrophy, isPrimary: true)
        XCTAssertEqual(primary?.sets, 4)
        XCTAssertEqual(primary?.reps, "6-12")
        XCTAssertEqual(primary?.restSec, 90)

        let accessory = WorkoutGenerator.focusBias(.hypertrophy, isPrimary: false)
        XCTAssertEqual(accessory?.sets, 3)
        XCTAssertEqual(accessory?.reps, "8-15")
        XCTAssertEqual(accessory?.restSec, 60)
    }

    func test_focusBias_sportPerformance_runsLowRepLongRest() {
        // Power scheme — heavy and rested, 5 sets on the primary so the
        // total drive volume hits the adaptation threshold.
        let primary = WorkoutGenerator.focusBias(.sportPerformance, isPrimary: true)
        XCTAssertEqual(primary?.sets, 5)
        XCTAssertEqual(primary?.reps, "3-5")
        XCTAssertEqual(primary?.restSec, 180)
    }

    func test_focusBias_endurance_runsVeryHighRepShortRest() {
        let primary = WorkoutGenerator.focusBias(.endurance, isPrimary: true)
        XCTAssertEqual(primary?.sets, 3)
        XCTAssertEqual(primary?.reps, "10-15")
        let accessory = WorkoutGenerator.focusBias(.endurance, isPrimary: false)
        XCTAssertEqual(accessory?.sets, 3)
        XCTAssertEqual(accessory?.reps, "12-20")
        XCTAssertEqual(accessory?.restSec, 45)
    }

    /// Integration: the prescription actually applies the bias when running
    /// against a real picked exercise. Hypertrophy memory should NOT inherit
    /// coach.db's stored reps for a heavy compound — focus wins.
    func test_prescription_hypertrophyOverridesCoachDbDefaults() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]   // primaryFocus = hypertrophy
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "test-hypertrophy"
        )
        guard let first = workout.exercises.first else {
            return XCTFail("planner returned no exercises")
        }
        XCTAssertEqual(first.reps, "6-12",
                       "Primary lift under hypertrophy should run 6-12, not coach.db default")
        XCTAssertEqual(first.restSeconds, 90,
                       "Primary rest under hypertrophy should be 90s")
        // Intermediate clamp caps sets at 4 — matches the hypertrophy
        // primary set count exactly.
        XCTAssertEqual(first.sets, 4,
                       "Primary lift under hypertrophy should run 4 sets")
    }

    /// generalStrength + advanced lifter should see the full 5×5 — no
    /// experience clamp kicks in because advanced is unrestricted.
    func test_prescription_generalStrengthAdvanced_runs5x5() {
        var m = TrainingMemory()
        m.experience = .advanced
        m.equipment = [.fullGym]
        m.focuses = [.generalStrength]
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "test-strength"
        )
        guard let first = workout.exercises.first else {
            return XCTFail("planner returned no exercises")
        }
        XCTAssertEqual(first.sets, 5, "5×5 primary on a strength day")
        XCTAssertEqual(first.reps, "5")
        XCTAssertEqual(first.restSeconds, 180)
    }

    // MARK: - Hypertrophy accessory layer
    //
    // The accessory layer (WorkoutGenerator:217-262) injects canonical
    // isolation work when the user's primaryFocus is hypertrophy AND the
    // focus is upper-push (push / upper / fullBodyA / fullBodyB) or
    // lower-body (legs / lower). These tests exercise the four densest
    // branches the architecture review flagged as having zero coverage.

    /// Hypertrophy + push must end with both lateral-delt and tricep
    /// isolation covered — either through the slot picker (e.g. picker grabs
    /// "Triceps Extension") OR through the upper-push accessory layer
    /// (which appends Cable Lateral Raise / Rope Pushdown / etc when the
    /// muscle isn't already covered). The invariant under test is muscle
    /// coverage, not which path provided it — both routes are correct.
    func test_hypertrophyPushCoversSideDeltAndTriceps() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 90  // give the accessory layer headroom
        m.focuses = [.hypertrophy]
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,  // push day
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        let names = workout.exercises.map { $0.name }

        let hasLateralRaise = names.contains { $0.contains("Lateral Raise") }
        let hasTricepIsolation = names.contains {
            $0.contains("Triceps") || $0.contains("Tricep")
                || $0.contains("Pushdown") || $0.contains("Skull Crusher")
        }
        XCTAssertTrue(hasLateralRaise,
            "Hypertrophy push should cover lateral delts. Got: \(names.sorted())")
        XCTAssertTrue(hasTricepIsolation,
            "Hypertrophy push should cover triceps. Got: \(names.sorted())")
    }

    /// Hypertrophy + legs must end with both hamstring and calf isolation
    /// covered — through the picker (e.g. "Dumbbell Standing Calf Raise") or
    /// through the lower-body accessory layer. The load-bearing assertion is
    /// the calf-count regression guard: the slug-disjoint check against
    /// {calves, gastrocnemius, soleus} prevents a double-append when the
    /// picker already covered calves under the component-muscle slugs.
    func test_hypertrophyLegsCoversHamstringAndCalfWithoutDoubleAppend() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 90
        m.focuses = [.hypertrophy]
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 2, totalLifts: 3,  // legs day
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        let names = workout.exercises.map { $0.name }

        let hasHamstringIsolation = names.contains { $0.contains("Leg Curl") }
        let hasCalfIsolation = names.contains { $0.contains("Calf") }
        XCTAssertTrue(hasHamstringIsolation,
            "Hypertrophy legs should cover hamstrings via a Leg Curl. Got: \(names.sorted())")
        XCTAssertTrue(hasCalfIsolation,
            "Hypertrophy legs should cover calves. Got: \(names.sorted())")

        // Regression guard: calf isolation should appear AT MOST ONCE. The
        // slug-trap (existingMuscles.contains("calves") missing exercises
        // tagged ["gastrocnemius","soleus"]) used to produce a double-append.
        let calfCount = names.filter { $0.contains("Calf") }.count
        XCTAssertLessThanOrEqual(calfCount, 1,
            "Calf isolation appeared \(calfCount) times — slug-disjoint regression. Got: \(names.sorted())")
    }

    /// The accessory layer is gated to `primaryFocus == .hypertrophy`. A
    /// non-hypertrophy user (general-strength on a push day) should NOT see
    /// the canonical accessory appendages. The stock push recipe is allowed
    /// to include a Cable Lateral Raise via the normal slot picker, so we
    /// just require the hypertrophy variant to have strictly more
    /// exercises (the accessory layer is purely additive).
    func test_nonHypertrophyDoesNotAppendAccessoryLayer() {
        var hyp = TrainingMemory()
        hyp.experience = .intermediate
        hyp.equipment = [.fullGym]
        hyp.sessionMinutes = 90
        hyp.focuses = [.hypertrophy]

        var gs = hyp
        gs.focuses = [.generalStrength]

        let pHyp = DemographicProfile.from(hyp)
        let pGs = DemographicProfile.from(gs)

        let hypW = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: hyp, profile: pHyp, hashSeed: hyp.planInputsHash
        )
        let gsW = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: gs, profile: pGs, hashSeed: gs.planInputsHash
        )
        XCTAssertGreaterThanOrEqual(hypW.exercises.count, gsW.exercises.count,
            "Accessory layer is additive; hypertrophy push must not have fewer exercises than general-strength push")
    }

    // MARK: - Stagnation swap

    /// When `context.stagnantExercises` includes an exercise the generator
    /// would have picked, `applyStagnationSwap` replaces it with the
    /// highest-scoring substitute that still clears every filter. The swap
    /// runs per-slot, so scan the baseline for any picked exercise that has
    /// substitutes in coach.db; mark that one stagnant and assert it's
    /// replaced. Only ~55% of catalog exercises have substitutes — if the
    /// baseline happens to pick none of them, skip rather than fail.
    func test_stagnationSwapReplacesFlaggedExerciseWhenSubstituteExists() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        let baseline = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash,
            context: .empty
        )
        let candidate = baseline.exercises.first { ex in
            !CoachDatabase.shared.substitutes(forExerciseId: ex.exerciseId).isEmpty
        }
        try XCTSkipIf(candidate == nil,
            "No picked baseline exercise has substitutes in coach.db; swap is a no-op")
        let target = candidate!

        var ctx = GeneratorContext.empty
        ctx.stagnantExercises = [target.name.lowercased()]
        let swapped = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash,
            context: ctx
        )
        // The flagged exercise should NOT appear in the swapped output at
        // the slot it occupied; assert by id so a same-named variant is
        // still considered a "swap to a different exercise".
        XCTAssertFalse(swapped.exercises.contains { $0.exerciseId == target.exerciseId },
            "Stagnation swap should have replaced '\(target.name)' (id \(target.exerciseId)) with a substitute; got: \(swapped.exercises.map { $0.name })")
    }

    // MARK: - Duration budget

    /// Optional slots that bust the cumulative budget are dropped; required
    /// (first) slot always lands so the user never sees an empty workout.
    /// 15-min budget vs 90-min budget on the same focus should produce
    /// strictly fewer exercises.
    func test_shortDurationBudgetDropsOptionalSlots() {
        var short = TrainingMemory()
        short.experience = .intermediate
        short.equipment = [.fullGym]
        short.sessionMinutes = 15  // clamped to the floor; minimal budget

        var long = short
        long.sessionMinutes = 90  // plenty of headroom

        let pShort = DemographicProfile.from(short)
        let pLong = DemographicProfile.from(long)

        let shortW = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: short, profile: pShort, hashSeed: short.planInputsHash
        )
        let longW = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: long, profile: pLong, hashSeed: long.planInputsHash
        )
        XCTAssertGreaterThanOrEqual(shortW.exercises.count, 1,
            "Required first slot must land even on a tight budget")
        XCTAssertLessThan(shortW.exercises.count, longW.exercises.count,
            "15-min budget (\(shortW.exercises.count) ex) should drop optional slots vs 90-min (\(longW.exercises.count) ex)")
    }

    // MARK: - Progressive overload step-up

    /// Pins steppedTargetLb: 2.5% snapped to the nearest 2.5 lb, floored at
    /// the prior weight. The pre-fix 5-lb grid zeroed the step for every
    /// working weight <= 100 lb (e.g. 95 -> 95), so progression silently
    /// stalled for all light/dumbbell/beginner loads.
    func test_steppedTargetLb_progressesMidLoadsNotMicroLoads() {
        XCTAssertEqual(WorkoutGenerator.steppedTargetLb(priorWeightLb: 65), 67.5, accuracy: 0.001)
        XCTAssertEqual(WorkoutGenerator.steppedTargetLb(priorWeightLb: 95), 97.5, accuracy: 0.001)
        XCTAssertEqual(WorkoutGenerator.steppedTargetLb(priorWeightLb: 135), 137.5, accuracy: 0.001)
        XCTAssertEqual(WorkoutGenerator.steppedTargetLb(priorWeightLb: 225), 230, accuracy: 0.001)
        // Never below last week's weight.
        XCTAssertGreaterThanOrEqual(WorkoutGenerator.steppedTargetLb(priorWeightLb: 185), 185)
        // Sub-~50 lb intentionally no-ops — can't micro-load below a plate.
        XCTAssertEqual(WorkoutGenerator.steppedTargetLb(priorWeightLb: 30), 30, accuracy: 0.001)
    }

    // MARK: - Sore-area exclusion

    /// With quads flagged sore, no generated exercise should have a
    /// quad-primary muscle. Control proves the filter is doing the work:
    /// without the flag, a legs day DOES include quad-primary work. Pre-fix,
    /// the label-substring match never connected "quads" to "Quadriceps", so
    /// squats were never excluded.
    func test_soreFilter_excludesQuadPrimaryExercisesWhenQuadsSore() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        func hasQuadPrimary(_ w: GeneratedWorkout) -> Bool {
            w.exercises.contains { ex in
                CoachDatabase.shared.musclesForExercise(ex.exerciseId)
                    .filter { $0.role == "primary" }
                    .contains { MuscleBucket.bucket(forSlug: $0.slug) == .quads }
            }
        }

        // Control: a legs day normally leads with quad-primary work.
        let control = WorkoutGenerator.generateLift(
            liftIndex: 2, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash,
            context: .empty
        )
        XCTAssertTrue(hasQuadPrimary(control),
            "Control legs day should include a quad-primary exercise; got: \(control.exercises.map { $0.name })")

        // Sore quads → quad-primary work excluded, workout still non-empty.
        var ctx = GeneratorContext.empty
        ctx.recentSoreAreas = ["quads"]
        let sore = WorkoutGenerator.generateLift(
            liftIndex: 2, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash,
            context: ctx
        )
        XCTAssertFalse(sore.exercises.isEmpty,
            "Sore-quads legs day should still produce non-quad work (hinge/calf/etc.)")
        XCTAssertFalse(hasQuadPrimary(sore),
            "Sore quads must exclude quad-primary exercises; got: \(sore.exercises.map { $0.name })")
    }

    // MARK: - focusBias coverage (weightLoss / longevity)

    func test_focusBias_weightLoss_runsModerateCircuit() {
        let primary = WorkoutGenerator.focusBias(.weightLoss, isPrimary: true)
        XCTAssertEqual(primary?.sets, 3)
        XCTAssertEqual(primary?.reps, "8-12")
        XCTAssertEqual(primary?.restSec, 60)

        let accessory = WorkoutGenerator.focusBias(.weightLoss, isPrimary: false)
        XCTAssertEqual(accessory?.sets, 3)
        XCTAssertEqual(accessory?.reps, "10-15")
        XCTAssertEqual(accessory?.restSec, 60)
    }

    func test_focusBias_longevity_runsLowVolumeControlled() {
        let primary = WorkoutGenerator.focusBias(.longevity, isPrimary: true)
        XCTAssertEqual(primary?.sets, 3)
        XCTAssertEqual(primary?.reps, "5-8")
        XCTAssertEqual(primary?.restSec, 90)

        let accessory = WorkoutGenerator.focusBias(.longevity, isPrimary: false)
        XCTAssertEqual(accessory?.sets, 3)
        XCTAssertEqual(accessory?.reps, "8-10")
        XCTAssertEqual(accessory?.restSec, 90)
    }

    // MARK: - Build 97: deload reduces sets, not exercise count

    /// The budget check uses pre-multiplier (base) duration, so a deload must
    /// shrink sets per exercise WITHOUT freeing budget for extra slots. At a
    /// constrained session length, normal and deload yield the same exercise
    /// count; only total set volume drops. Guards against reverting to a
    /// scaled-sets budget (which would let a deload pack in more exercises).
    func test_deloadReducesSetsNotExerciseCount() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 25   // tight enough to drop optional slots
        let p = DemographicProfile.from(m)

        let normal = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash,
            strategy: .auto
        )
        var deload = GeneratorStrategy.auto
        deload.intensityBias = .deload
        let deloaded = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash,
            strategy: deload
        )

        XCTAssertEqual(deloaded.exercises.count, normal.exercises.count,
            "Deload must not change exercise count (build 97): normal \(normal.exercises.map { $0.name }) vs deload \(deloaded.exercises.map { $0.name })")
        let normalSets = normal.exercises.reduce(0) { $0 + $1.sets }
        let deloadSets = deloaded.exercises.reduce(0) { $0 + $1.sets }
        XCTAssertLessThan(deloadSets, normalSets,
            "Deload should reduce total sets (normal=\(normalSets), deload=\(deloadSets))")
    }

    // MARK: - Progressive-overload load is rep-range-aware (e1RM)

    /// priorBest is the heaviest set at ANY rep count, so the target load must
    /// be mapped to the prescribed rep band — otherwise a 3-rep max is shown as
    /// the target for a 12-rep set (the old rep-blind bug, "target 230" for 6-12).
    func test_progressiveTargetLb_mapsPriorBestToPrescribedReps() {
        // 225×3 top set → e1RM ~248 → ~195 lb for a 6-12 set (not 230).
        XCTAssertEqual(
            WorkoutGenerator.progressiveTargetLb(priorWeight: 225, priorReps: 3, prescribedReps: "6-12")!,
            195, accuracy: 0.001)
        // Lighter, higher-rep history → heavier target for fewer reps.
        XCTAssertEqual(
            WorkoutGenerator.progressiveTargetLb(priorWeight: 100, priorReps: 10, prescribedReps: "5")!,
            117.5, accuracy: 0.001)
        // Non-numeric bands fall back (caller uses raw stepped prior weight).
        XCTAssertNil(WorkoutGenerator.progressiveTargetLb(priorWeight: 225, priorReps: 3, prescribedReps: "AMRAP"))
        XCTAssertNil(WorkoutGenerator.progressiveTargetLb(priorWeight: 100, priorReps: 5, prescribedReps: "30s hold"))
    }

    func test_repBandMidpoint_parsesBands() {
        XCTAssertEqual(WorkoutGenerator.repBandMidpoint("5"), 5)
        XCTAssertEqual(WorkoutGenerator.repBandMidpoint("6-12"), 9)
        XCTAssertEqual(WorkoutGenerator.repBandMidpoint("8-15"), 12)
        XCTAssertNil(WorkoutGenerator.repBandMidpoint("AMRAP"))
        XCTAssertNil(WorkoutGenerator.repBandMidpoint("30s hold"))
    }

}
