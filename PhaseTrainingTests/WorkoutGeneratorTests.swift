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
        m.constraints = ["acl-injury"]   // structured slug from coach.db
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
}
