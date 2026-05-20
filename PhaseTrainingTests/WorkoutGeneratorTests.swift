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

    func test_generatedMobility_usesMobilityModalityExercises() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 30
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateMobility(
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        XCTAssertFalse(workout.exercises.isEmpty)
        for ex in workout.exercises {
            let underlying = CoachDatabase.shared.exercise(id: ex.exerciseId)
            let modality = underlying?.modality ?? ""
            XCTAssertTrue(
                ["mobility", "recovery", "prehab", "breathing"].contains(modality),
                "Mobility flow picked a non-mobility exercise: \(ex.name) (\(modality))"
            )
        }
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

    func test_focusBias_generalStrength_keepsCoachDbDefaults() {
        // No bias = nil → coach.db/formula path drives reps + rest.
        XCTAssertNil(WorkoutGenerator.focusBias(.generalStrength, isPrimary: true))
        XCTAssertNil(WorkoutGenerator.focusBias(.generalStrength, isPrimary: false))
    }

    func test_focusBias_hypertrophy_runsHighRepShortRest() {
        let primary = WorkoutGenerator.focusBias(.hypertrophy, isPrimary: true)
        XCTAssertEqual(primary?.reps, "6-10")
        XCTAssertEqual(primary?.restSec, 90)

        let accessory = WorkoutGenerator.focusBias(.hypertrophy, isPrimary: false)
        XCTAssertEqual(accessory?.reps, "8-12")
        XCTAssertEqual(accessory?.restSec, 60)
    }

    func test_focusBias_sportPerformance_runsLowRepLongRest() {
        // Power scheme — heavy and rested.
        let primary = WorkoutGenerator.focusBias(.sportPerformance, isPrimary: true)
        XCTAssertEqual(primary?.reps, "3-5")
        XCTAssertEqual(primary?.restSec, 180)
    }

    func test_focusBias_endurance_runsVeryHighRepShortRest() {
        let primary = WorkoutGenerator.focusBias(.endurance, isPrimary: true)
        XCTAssertEqual(primary?.reps, "10-15")
        let accessory = WorkoutGenerator.focusBias(.endurance, isPrimary: false)
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

        // Use the first exercise the planner can find for a primary slot.
        // Any picked exercise will do — we only care that the bias is applied.
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "test-hypertrophy"
        )
        guard let first = workout.exercises.first else {
            return XCTFail("planner returned no exercises")
        }
        XCTAssertEqual(first.reps, "6-10",
                       "Primary lift under hypertrophy should run 6-10, not coach.db default")
        XCTAssertEqual(first.restSeconds, 90,
                       "Primary rest under hypertrophy should be 90s")
    }

    /// Mobility WORKOUT (vs mobility FOCUS) still uses hold-style defaults.
    /// Confirms the bias only kicks in for lift days.
    func test_prescription_mobilityWorkout_ignoresFocusBias() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]  // bias active
        let p = DemographicProfile.from(m)

        let mob = WorkoutGenerator.generateMobility(
            memory: m, profile: p, hashSeed: "test-mob"
        )
        guard let first = mob.exercises.first else {
            return XCTFail("mobility flow returned no exercises")
        }
        // Mobility reps should NOT be 6-10 (the hypertrophy primary bias) —
        // mobility flows keep their hold-style defaults.
        XCTAssertNotEqual(first.reps, "6-10")
    }

    // MARK: - Prehab injection on mobility days (build 87)

    func test_mobilityDay_withInjury_includesPrehabExercise() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.userInjuries = [UserInjury(slug: "patellar-tendinopathy")]
        let p = DemographicProfile.from(m)
        XCTAssertFalse(p.prehabSuggestions.isEmpty,
                       "Precondition: coach.db should have prehab moves tagged for patellar tendinopathy")

        let mob = WorkoutGenerator.generateMobility(
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        let prehabPicks = mob.exercises.filter {
            if case .prehab = $0.source { return true } else { return false }
        }
        XCTAssertEqual(prehabPicks.count, 1,
                       "Mobility day with one injury should include exactly one prehab pick")
        if case .prehab(let slug) = prehabPicks.first?.source {
            XCTAssertEqual(slug, "patellar-tendinopathy")
        } else {
            XCTFail("First prehab pick should tag the user's injury")
        }
    }

    func test_mobilityDay_noInjury_skipsPrehab() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        let p = DemographicProfile.from(m)
        XCTAssertTrue(p.prehabSuggestions.isEmpty)

        let mob = WorkoutGenerator.generateMobility(
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        for ex in mob.exercises {
            if case .prehab = ex.source {
                XCTFail("Expected no prehab picks for a user with no injuries; got \(ex.name)")
            }
        }
    }

    func test_liftDay_withInjury_doesNotInjectPrehab() {
        // Lift days stay subtractive — contraindication filter only. Prehab
        // belongs on mobility days where it can crowd out hold work, not on
        // a primary lift where it'd steal from main compound time.
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.userInjuries = [UserInjury(slug: "acl-injury")]
        let p = DemographicProfile.from(m)

        let lift = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 1,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        for ex in lift.exercises {
            if case .prehab = ex.source {
                XCTFail("Lift day should not inject prehab picks; got \(ex.name)")
            }
        }
    }
}
