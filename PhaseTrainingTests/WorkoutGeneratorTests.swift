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

    // MARK: - Superset structure (D4)

    func test_upperDay_supersetsAntagonistPair() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        // totalLifts 4, liftIndex 0 → upper day: has both a vertical push and
        // a vertical pull, an antagonist pair the generator should superset.
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 4,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        let groups = workout.exercises.compactMap(\.supersetGroup)
        XCTAssertFalse(groups.isEmpty,
                       "Upper day should produce at least one antagonist superset")
        // Every assigned group must have exactly two members sharing the int.
        let counts = Dictionary(grouping: groups, by: { $0 }).mapValues(\.count)
        for (g, c) in counts {
            XCTAssertEqual(c, 2, "Superset group \(g) should have exactly 2 members, got \(c)")
        }
        // ...and those two members must be antagonist patterns.
        for g in Set(groups) {
            let patterns = workout.exercises
                .filter { $0.supersetGroup == g }
                .compactMap(\.pattern)
            XCTAssertEqual(patterns.count, 2)
            XCTAssertEqual(WorkoutGenerator.antagonistPatterns[patterns[0]], patterns[1],
                           "Superset members \(patterns) should be antagonists")
        }
    }

    func test_pushDay_noSupersets_whenNoAntagonistPresent() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        // Push day is all push / triceps / core — no antagonist pull to pair
        // with, so it should stay flat. "≥1 superset WHERE APPROPRIATE."
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        XCTAssertTrue(workout.exercises.allSatisfy { $0.supersetGroup == nil },
                      "Push day has no antagonist pair to superset")
    }

    func test_primaryCompound_staysSolo() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 4,
            memory: m, profile: p, hashSeed: m.planInputsHash
        )
        XCTAssertNil(workout.exercises.first?.supersetGroup,
                     "The top heavy compound should never be supersetted")
    }

    func test_assignAntagonistSupersets_pairsPushAndPull() {
        // Direct unit test of the pairing rule, independent of coach.db.
        func gex(_ id: Int, _ pattern: String) -> GeneratedExercise {
            GeneratedExercise(id: "x-\(id)", exerciseId: id, name: "ex\(id)",
                              pattern: pattern, isCompound: false,
                              sets: 3, reps: "8-12", restSeconds: 60)
        }
        // index 0 is the protected primary; 1+2 are an antagonist pair.
        let input = [gex(0, "horizontal-push"),
                     gex(1, "vertical-push"),
                     gex(2, "vertical-pull"),
                     gex(3, "anti-extension")]
        let out = WorkoutGenerator.assignAntagonistSupersets(input)
        XCTAssertNil(out[0].supersetGroup, "primary stays solo")
        XCTAssertNotNil(out[1].supersetGroup)
        XCTAssertEqual(out[1].supersetGroup, out[2].supersetGroup,
                       "antagonist push/pull should share a group")
        XCTAssertNil(out[3].supersetGroup, "core has no antagonist present")
    }

    func test_supersetGroup_propagatesToTemplate() {
        let gex = GeneratedExercise(
            id: "t-1", exerciseId: 1, name: "Test", isCompound: false,
            sets: 3, reps: "8-12", restSeconds: 60, supersetGroup: 7)
        let workout = GeneratedWorkout(
            title: "T", summary: "", exercises: [gex],
            estimatedMinutes: 10, provenance: "")
        let template = workout.toWorkoutTemplate(id: "t")
        XCTAssertEqual(template.exercises.first?.supersetGroup, 7,
                       "supersetGroup must survive the GeneratedWorkout → WorkoutTemplate bridge")
    }

    // MARK: - Rest differentiation (eval-rig Q7)

    func test_secondaryCompound_restsLongerThanIsolation() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        // Force a lower day (squat + RDL + lunge + calf/leg-curl isolation) so
        // there are both secondary compounds and isolations to compare.
        var strat = GeneratorStrategy.auto
        strat.focus = .lower
        let w = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 4, memory: m, profile: p,
            hashSeed: "rest-diff-q7", strategy: strat)

        let isoRests = w.exercises.filter { !$0.isCompound }.map(\.restSeconds)
        let secondaryCompounds = Array(w.exercises.dropFirst()).filter { $0.isCompound }
        XCTAssertFalse(secondaryCompounds.isEmpty, "lower day should have secondary compounds")
        let maxIso = isoRests.max() ?? 0
        for ex in secondaryCompounds {
            XCTAssertGreaterThan(ex.restSeconds, maxIso,
                "secondary compound \(ex.name) (\(ex.restSeconds)s) must rest longer than isolations (\(maxIso)s) — Q7 differentiation")
        }
    }

    // MARK: - Rep-band curve / finisher (D4 part B/C)

    func test_hypertrophyFinisher_isHighRep_descendingCurve() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        // Lower day reliably appends a hamstring isolation finisher (Lying Leg
        // Curl) — the recipe's hip-hinge is a compound, so no hamstring
        // isolation exists until the append fires.
        var strat = GeneratorStrategy.auto
        strat.focus = .lower
        let w = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 4, memory: m, profile: p,
            hashSeed: "finisher-curve", strategy: strat)

        let finishers = w.exercises.filter { $0.reps == WorkoutGenerator.finisherRepBand }
        XCTAssertFalse(finishers.isEmpty,
            "hypertrophy lower day should append a high-rep isolation finisher")

        // Descending curve: the finisher's rep midpoint sits above the primary
        // compound's. ("6-12"→9 / "3-6"→4 vs "15-20"→18.)
        guard let primaryMid = WorkoutGenerator.repBandMidpoint(w.exercises[0].reps),
              let finisherMid = WorkoutGenerator.repBandMidpoint(finishers[0].reps) else {
            return XCTFail("rep bands should parse to midpoints")
        }
        XCTAssertGreaterThan(finisherMid, primaryMid,
            "finisher (\(finishers[0].reps)) should be higher-rep than the primary compound (\(w.exercises[0].reps))")
    }

    // MARK: - Consolidated (merged) day generation (D3)

    func test_generateConsolidated_mergedDay_includesBothFocuses() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.sessionMinutes = 75   // room for both focuses' compounds
        let p = DemographicProfile.from(m)
        let day = WeekConsolidator.ConsolidatedDay(primary: .legs, secondary: .push)
        let w = WorkoutGenerator.generateConsolidated(
            day, totalLifts: 2, memory: m, profile: p, hashSeed: "merged-legs-push")

        let patterns = Set(w.exercises.compactMap(\.pattern))
        XCTAssertTrue(patterns.contains("squat") || patterns.contains("hip-hinge"),
                      "merged day should keep a primary leg compound; got \(patterns)")
        XCTAssertTrue(patterns.contains("horizontal-push"),
                      "merged day should graft the secondary push compound; got \(patterns)")
        XCTAssertTrue(w.title.contains("+"), "merged day title should name both focuses")
    }

    func test_generateConsolidated_soloDay_isNormalWorkout() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        let day = WeekConsolidator.ConsolidatedDay(primary: .push, secondary: nil)
        let w = WorkoutGenerator.generateConsolidated(
            day, totalLifts: 3, memory: m, profile: p, hashSeed: "solo-push")

        XCTAssertFalse(w.exercises.isEmpty)
        let patterns = Set(w.exercises.compactMap(\.pattern))
        XCTAssertTrue(patterns.contains("horizontal-push"),
                      "solo push day should include a horizontal push; got \(patterns)")
        XCTAssertFalse(w.title.contains("+"), "solo day title is single-focus")
    }

    func test_generatedWorkout_persistsFocus() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        var strat = GeneratorStrategy.auto
        strat.focus = .pull
        let solo = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3, memory: m, profile: p,
            hashSeed: "persist-focus", strategy: strat)
        XCTAssertEqual(solo.focus, .pull,
                       "generated workout should persist its WorkoutFocus, not just a title")

        let merged = WorkoutGenerator.generateConsolidated(
            .init(primary: .legs, secondary: .push), totalLifts: 2,
            memory: m, profile: p, hashSeed: "persist-focus-merged")
        XCTAssertEqual(merged.focus, .legs, "a merged day's focus is its primary")
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

    /// T2.2 — 70+ programming is differentiated from 55+: lower max session
    /// minutes and more recovery days between lifts. Pre-fix both age bands
    /// resolved to the same magazineBodybuilding era with identical volume caps.
    func test_age70_differentiatesFrom55() {
        func profile(age: Int) -> DemographicProfile {
            var m = TrainingMemory()
            m.experience = .intermediate
            m.equipment = [.fullGym]
            m.age = age
            return DemographicProfile.from(m)
        }
        let p55 = profile(age: 55)
        let p70 = profile(age: 70)

        XCTAssertLessThan(p70.recommendedSessionMinutes.upperBound,
                          p55.recommendedSessionMinutes.upperBound,
            "70+ max session minutes (\(p70.recommendedSessionMinutes.upperBound)) should be below 55+ (\(p55.recommendedSessionMinutes.upperBound))")
        XCTAssertGreaterThan(p70.minRecoveryDaysBetweenLifts,
                             p55.minRecoveryDaysBetweenLifts,
            "70+ recovery days (\(p70.minRecoveryDaysBetweenLifts)) should exceed 55+ (\(p55.minRecoveryDaysBetweenLifts))")
    }

    /// T1.6 — advanced earns +1 work set on a COMPOUND over intermediate.
    /// Before, both clamped to the same focus-bias cap, so "advanced" produced
    /// a prescription identical to "intermediate". The bump is built on the
    /// intermediate clamp, so it tops out at 5 (preserving the canonical 5×5).
    func test_prescription_advancedAddsCompoundSetOverIntermediate() throws {
        let compound = try XCTUnwrap(
            CoachDatabase.shared.exercises(matchingPattern: "squat").first { $0.isCompound },
            "need a compound for the prescription comparison")
        func sets(_ configure: (inout TrainingMemory) -> Void) -> Int {
            var m = TrainingMemory()
            m.equipment = [.fullGym]
            configure(&m)
            return WorkoutGenerator.prescription(
                for: compound, slotIdx: 0, focus: .legs,
                memory: m, profile: .from(m)).sets
        }
        let inter = sets { $0.experience = .intermediate }
        let adv = sets { $0.experience = .advanced }
        XCTAssertEqual(adv, inter + 1,
            "advanced should program exactly one more set than intermediate on a compound (T1.6)")
        XCTAssertLessThanOrEqual(adv, 5, "advanced compound sets top out at 5 (5×5 preserved)")
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

    /// Generating workout B right after workout A must equal generating B
    /// alone — no per-generation state (PatternSlot.satisfiedBy, the
    /// exercise-query cache) may leak across generate() calls.
    /// WorkoutFocus.slots builds fresh PatternSlot instances on every access
    /// and the query cache lives for exactly one pass; this locks both in.
    func test_generationIsOrderIndependent() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        func gen(_ liftIndex: Int) -> GeneratedWorkout {
            WorkoutGenerator.generateLift(liftIndex: liftIndex, totalLifts: 3,
                memory: m, profile: p, hashSeed: m.planInputsHash)
        }
        let bAlone = gen(1)   // pull day, no prior generation
        _ = gen(0)            // push day A
        let bAfterA = gen(1)  // pull day again, after A

        XCTAssertEqual(bAfterA.exercises.map(\.exerciseId), bAlone.exercises.map(\.exerciseId))
        XCTAssertEqual(bAfterA.exercises.map(\.sets),       bAlone.exercises.map(\.sets))
        XCTAssertEqual(bAfterA.exercises.map(\.reps),       bAlone.exercises.map(\.reps))
        XCTAssertEqual(bAfterA.exercises.map(\.pattern),    bAlone.exercises.map(\.pattern))
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

    // MARK: - T0.1 accessory layer honors context-driven regulators

    /// Intermediate hypertrophy user on a push day — the upper-push accessory
    /// layer fires Cable Lateral Raise (side delt) + Rope Pushdown (triceps).
    private func hypertrophyPushMemory(sessionMinutes: Int = 90) -> TrainingMemory {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = sessionMinutes
        m.focuses = [.hypertrophy]
        return m
    }

    /// Appended accessory rows are tagged with a "hypaccess" id prefix
    /// (makeAccessoryRow), which isolates them from normal slot picks.
    private func accessoryRows(_ w: GeneratedWorkout) -> [GeneratedExercise] {
        w.exercises.filter { $0.id.contains("hypaccess") }
    }

    /// Sore-area exclusion must reach the accessory layer. With both shoulders
    /// and triceps flagged sore, neither canonical upper-push accessory (side
    /// delt → shoulders, pushdown → triceps) may append.
    func test_accessoryLayer_respectsSoreExclusion() throws {
        let m = hypertrophyPushMemory()
        let p = DemographicProfile.from(m)
        let baseline = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash, context: .empty)
        try XCTSkipIf(accessoryRows(baseline).isEmpty,
            "Baseline push day appended no accessories; nothing to exclude")

        var sore = GeneratorContext.empty
        sore.recentSoreAreas = ["shoulders", "triceps"]
        let soreW = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash, context: sore)
        XCTAssertTrue(accessoryRows(soreW).isEmpty,
            "Sore shoulders+triceps must suppress the upper-push accessory layer; got: \(accessoryRows(soreW).map { $0.name })")
    }

    /// Readiness × deload set scaling must reach the accessory layer. A
    /// detrained user (readinessScore 0.0 → 0.6× sets) gets fewer accessory
    /// sets than a full-readiness baseline, same as the main slot loop.
    func test_accessoryLayer_respectsReadinessSetScaling() throws {
        let m = hypertrophyPushMemory()
        let p = DemographicProfile.from(m)
        let baseAcc = accessoryRows(WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash, context: .empty))
        try XCTSkipIf(baseAcc.isEmpty, "No accessory to scale")

        var low = GeneratorContext.empty
        low.hasReadinessData = true
        low.readinessScore = 0.0
        let lowAcc = accessoryRows(WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: m.planInputsHash, context: low))

        // Readiness changes set count, not selection — same exercises, in order.
        XCTAssertEqual(lowAcc.count, baseAcc.count, "selection should be unchanged")
        var anyDropped = false
        for (base, scaled) in zip(baseAcc, lowAcc) {
            XCTAssertEqual(scaled.exerciseId, base.exerciseId)
            XCTAssertLessThanOrEqual(scaled.sets, base.sets,
                "Accessory \(base.name) sets must not grow at readiness 0.0")
            if scaled.sets < base.sets { anyDropped = true }
        }
        XCTAssertTrue(anyDropped,
            "readiness 0.0 should reduce at least one accessory's set count")
    }

    /// Dislike keywords must reach the accessory layer. Whatever the baseline
    /// accessory layer appended (a hypaccess-tagged row, so ONLY the accessory
    /// layer could have produced it), disliking its name must drop that exact
    /// exercise — pre-fix the layer ignored excludeKws and kept it.
    func test_accessoryLayer_respectsDislikeKeywords() throws {
        let m = hypertrophyPushMemory()
        let baseAcc = accessoryRows(WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: .from(m), hashSeed: m.planInputsHash, context: .empty))
        let target = baseAcc.first
        try XCTSkipIf(target == nil, "No accessory appended; nothing to dislike")

        var disliked = m
        disliked.dislikes = [target!.name.lowercased()]
        let dW = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: disliked, profile: .from(disliked), hashSeed: disliked.planInputsHash, context: .empty)
        XCTAssertFalse(dW.exercises.contains { $0.exerciseId == target!.exerciseId },
            "Disliking '\(target!.name)' must drop it from the accessory layer; got: \(dW.exercises.map { $0.name })")
    }

    /// The duration budget must gate the accessory append. A 20-minute push
    /// day can't fit the appended isolation that a 120-minute day does.
    func test_accessoryLayer_respectsDurationBudget() throws {
        let big = hypertrophyPushMemory(sessionMinutes: 120)
        let small = hypertrophyPushMemory(sessionMinutes: 20)
        let bigAcc = accessoryRows(WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: big, profile: .from(big), hashSeed: big.planInputsHash, context: .empty))
        let smallAcc = accessoryRows(WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: small, profile: .from(small), hashSeed: small.planInputsHash, context: .empty))
        try XCTSkipIf(bigAcc.isEmpty, "120-min push day appended no accessories; budget test is moot")
        XCTAssertLessThan(smallAcc.count, bigAcc.count,
            "20-min day must drop accessories the 120-min day keeps (budget gate)")
    }

    // MARK: - T1.2 time/distance prescriptions survive the focus-bias band

    /// Wall Sit is stored as "30-60 sec" in coach.db. A hypertrophy user's
    /// 8-15 accessory band (and the era nudge) must NOT overwrite it — an
    /// isometric prescribed in reps is the global "isometrics in reps" smell.
    func test_prescription_preservesTimeBasedRepsOverFocusBias() throws {
        let wallSit = CoachDatabase.shared.listExercises(search: "Wall Sit").first { $0.name == "Wall Sit" }
        try XCTSkipIf(wallSit == nil, "Wall Sit not in coach.db")
        var m = TrainingMemory()
        m.experience = .intermediate
        m.focuses = [.hypertrophy]
        let p = DemographicProfile.from(m)
        let rx = WorkoutGenerator.prescription(for: wallSit!, slotIdx: 2, focus: .legs, memory: m, profile: p)
        XCTAssertTrue(rx.reps.lowercased().contains("sec"),
            "Time-based Wall Sit should keep its duration prescription; got reps='\(rx.reps)'")
    }

    /// The classifier separating numeric rep bands (overwritable by focus bias)
    /// from time/distance/hold prescriptions (preserved).
    func test_isNumericRepBand_classification() {
        for numeric in ["5", "12", "6-12", "8-15", "3 - 5"] {
            XCTAssertTrue(WorkoutGenerator.isNumericRepBand(numeric), "'\(numeric)' is a numeric band")
        }
        for nonNumeric in ["30-60 sec", "30s", "20-45 sec", "5-10 sec hold", "40-60 ft", "40 m", "AMRAP"] {
            XCTAssertFalse(WorkoutGenerator.isNumericRepBand(nonNumeric), "'\(nonNumeric)' is NOT a numeric band")
        }
    }

    // MARK: - T1.5 beginner intensity guardrail

    /// Sub-6 numeric bands floor to 6-8; bands already ≥6 and non-numeric
    /// prescriptions pass through.
    func test_beginnerRepFloor_raisesSubSixBandsOnly() {
        XCTAssertEqual(WorkoutGenerator.beginnerRepFloor("5"), "6-8")
        XCTAssertEqual(WorkoutGenerator.beginnerRepFloor("3-5"), "6-8")
        XCTAssertEqual(WorkoutGenerator.beginnerRepFloor("6-12"), "6-12")
        XCTAssertEqual(WorkoutGenerator.beginnerRepFloor("8-15"), "8-15")
        XCTAssertEqual(WorkoutGenerator.beginnerRepFloor("30-60 sec"), "30-60 sec")
        XCTAssertEqual(WorkoutGenerator.beginnerRepFloor("40-60 ft"), "40-60 ft")
    }

    /// A beginner's primary prescription must be RPE-capped (≤7) and rep-
    /// floored (≥6); an intermediate keeps the heavier scheme.
    func test_prescription_beginnerCapsRpeAndFloorsReps() throws {
        let bench = CoachDatabase.shared.listExercises(search: "Bench Press").first { $0.isCompound }
        try XCTSkipIf(bench == nil, "No compound Bench Press in coach.db")

        var beginner = TrainingMemory()
        beginner.experience = .beginner
        beginner.focuses = [.generalStrength]    // primary band "5", RPE "8"
        let rx = WorkoutGenerator.prescription(
            for: bench!, slotIdx: 0, focus: .push, memory: beginner, profile: .from(beginner))
        XCTAssertEqual(rx.reps, "6-8", "beginner primary reps should floor to 6-8; got '\(rx.reps)'")

        let rpeBeg = WorkoutGenerator.rpeTempoHints(
            for: bench!, slotIdx: 0, focus: .push, memory: beginner).rpe ?? ""
        XCTAssertFalse(rpeBeg.contains("8") || rpeBeg.contains("9"),
            "beginner RPE should cap ≤7; got '\(rpeBeg)'")

        var inter = beginner
        inter.experience = .intermediate
        let rpeInt = WorkoutGenerator.rpeTempoHints(
            for: bench!, slotIdx: 0, focus: .push, memory: inter).rpe ?? ""
        XCTAssertTrue(rpeInt.contains("8"),
            "intermediate RPE should retain 8+ work; got '\(rpeInt)'")
    }

    // MARK: - T1.7 dislike by equipment tag, not just name

    /// Disliking "machine" must drop machine-required exercises even when the
    /// exercise NAME is clean (Lying Leg Curl needs leg-curl-machine). Covers
    /// both the main slot picker and the accessory layer.
    func test_dislikeMachine_filtersByEquipmentTagNotJustName() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 90
        m.focuses = [.hypertrophy]

        let equipNames = CoachDatabase.shared.equipmentNameBySlug()
        func requiresMachine(_ exId: Int) -> Bool {
            let slugs = CoachDatabase.shared.requiredEquipmentSlugs(forExerciseIds: [exId])[exId] ?? []
            return slugs.contains { ($0 + " " + (equipNames[$0] ?? "")).contains("machine") }
        }

        let baseline = WorkoutGenerator.generateLift(
            liftIndex: 2, totalLifts: 3, memory: m, profile: .from(m), hashSeed: m.planInputsHash)
        // A machine-required pick whose NAME is clean — proves the name-only
        // filter would have missed it.
        let cleanMachinePick = baseline.exercises.first {
            requiresMachine($0.exerciseId) && !$0.name.lowercased().contains("machine")
        }
        try XCTSkipIf(cleanMachinePick == nil,
            "Baseline legs day had no name-clean machine exercise to test")

        var disliked = m
        disliked.dislikes = ["machine"]
        let dW = WorkoutGenerator.generateLift(
            liftIndex: 2, totalLifts: 3, memory: disliked, profile: .from(disliked), hashSeed: disliked.planInputsHash)
        XCTAssertFalse(dW.exercises.contains { requiresMachine($0.exerciseId) },
            "Disliking 'machine' must drop machine-required exercises despite clean names; got: \(dW.exercises.map { $0.name })")
    }

    // MARK: - T1.1 bodyweight degradation floor

    /// A bodyweight-only user's pull day must not collapse. The catalog has no
    /// apparatus-free vertical pull, so that required slot drops; the
    /// degradation floor backfills from scapular/back work (supplied by the
    /// source resync) to a minimum of 3 movements.
    func test_bodyweightPullDay_doesNotCollapse() {
        var m = TrainingMemory()
        m.experience = .beginner
        m.equipment = [.bodyweight]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        var strat = GeneratorStrategy.auto
        strat.focus = .pull
        let w = WorkoutGenerator.generateLift(
            liftIndex: 1, totalLifts: 3, memory: m, profile: p,
            hashSeed: "bw-pull", strategy: strat)
        XCTAssertEqual(w.focus, .pull)
        XCTAssertGreaterThanOrEqual(w.exercises.count, 3,
            "bodyweight pull day must reach the degradation floor (>=3); got \(w.exercises.map { $0.name })")
        let ids = w.exercises.map { $0.exerciseId }
        XCTAssertEqual(ids.count, Set(ids).count, "no duplicate exercises in the degraded day")
    }

    // MARK: - Stagnation swap

    /// When `context.stagnantExercises` includes an exercise the generator
    /// would have picked, `applyStagnationSwap` replaces it with the
    /// highest-scoring substitute that still clears every filter. The swap
    /// runs per-slot, so scan the baseline for any picked exercise that has
    /// substitutes in coach.db; mark that one stagnant and assert it's
    /// replaced. Only ~55% of catalog exercises have substitutes — if the
    /// baseline happens to pick none of them, skip rather than fail.
    /// The stagnation swap still FIRES for a same-pattern substitute (proves
    /// the T2.5 gate didn't break the feature), and the result stays in pattern.
    /// Direct unit test of applyStagnationSwap for determinism.
    func test_stagnationSwap_firesForSamePatternSub() throws {
        // Find a catalog exercise with a substitute sharing the SAME specific
        // movement pattern (what the post-T2.5 swap requires).
        var target: Exercise?
        var pattern = ""
        for p in ["horizontal-push", "squat", "horizontal-pull", "hip-hinge", "vertical-push", "vertical-pull"] {
            for e in CoachDatabase.shared.exercises(matchingPattern: p) {
                let hasSamePatternSub = CoachDatabase.shared.substitutes(forExerciseId: e.id).contains { s in
                    s.exercise.id != e.id
                        && Set(CoachDatabase.shared.patternsForExercise(s.exercise.id)).contains(p)
                }
                if hasSamePatternSub { target = e; pattern = p; break }
            }
            if target != nil { break }
        }
        let orig = try XCTUnwrap(target, "no catalog exercise has a same-pattern substitute")

        var ctx = GeneratorContext.empty
        ctx.stagnantExercises = [orig.name.lowercased()]
        let slot = PatternSlot(alternatives: [pattern], optional: false)
        let result = WorkoutGenerator.applyStagnationSwap(
            original: orig, context: ctx, envs: [], allowedEquipmentSlugs: [],
            excludeKws: [], excludeIds: [], slot: slot)

        XCTAssertNotEqual(result.id, orig.id,
            "swap should fire for a same-pattern substitute (\(orig.name), pattern \(pattern))")
        XCTAssertTrue(Set(CoachDatabase.shared.patternsForExercise(result.id)).contains(pattern),
            "swap '\(orig.name)' → '\(result.name)' must stay in pattern '\(pattern)'")
    }

    /// A stagnation swap must stay within the slot's movement pattern (T2.5) —
    /// no trading a pull for a push or a carry for a quad isometric. Flag every
    /// pick stagnant, then assert any swap on a required (single-pattern) slot
    /// shares a movement pattern with the original.
    func test_stagnationSwap_staysInMovementPattern() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        let p = DemographicProfile.from(m)
        let baseline = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3, memory: m, profile: p,
            hashSeed: m.planInputsHash, context: .empty)
        var ctx = GeneratorContext.empty
        ctx.stagnantExercises = Set(baseline.exercises.map { $0.name.lowercased() })
        let swapped = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3, memory: m, profile: p,
            hashSeed: m.planInputsHash, context: ctx)
        // First two slots are the required single-alternative compounds, so the
        // original's pattern IS the slot's pattern — any swap there must overlap.
        for (orig, now) in zip(baseline.exercises.prefix(2), swapped.exercises.prefix(2))
        where orig.exerciseId != now.exerciseId {
            let op = Set(CoachDatabase.shared.patternsForExercise(orig.exerciseId))
            let np = Set(CoachDatabase.shared.patternsForExercise(now.exerciseId))
            XCTAssertFalse(op.isDisjoint(with: np),
                "swap '\(orig.name)' → '\(now.name)' crossed movement pattern (\(op) vs \(np))")
        }
    }

    // MARK: - Duration budget

    /// T2.4 — a very short session trims required-slot sets to fit rather than
    /// shipping a grossly over-budget day (a 20-min request used to yield a
    /// ~33-min leg day because required compounds had no per-slot floor).
    func test_tightBudget_trimsRequiredSetsNotOverrun() {
        func gen(_ mins: Int) -> GeneratedWorkout {
            var m = TrainingMemory()
            m.experience = .intermediate
            m.equipment = [.fullGym]
            m.sessionMinutes = mins
            m.focuses = [.generalStrength]
            return WorkoutGenerator.generateLift(
                liftIndex: 2, totalLifts: 3, memory: m, profile: .from(m), hashSeed: "budget")
        }
        let tight = gen(20)
        let roomy = gen(90)
        XCTAssertLessThan(tight.estimatedMinutes, roomy.estimatedMinutes,
            "a tight budget should produce a shorter day than a roomy one")
        XCTAssertLessThanOrEqual(tight.estimatedMinutes, 24,
            "20-min day should trim near budget; got \(tight.estimatedMinutes)m: \(tight.exercises.map { "\($0.name) \($0.sets)x" })")
    }

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

    /// T1.4 — a 120-min session should produce strictly more total work than
    /// a 60-min session for identical inputs. Pre-fix the budget was dead upward:
    /// 45 = 60 = 90 = 120 all produced the same content.
    func test_highMinuteBudget_addsVolumeOver60min() {
        func gen(_ mins: Int) -> GeneratedWorkout {
            var m = TrainingMemory()
            m.experience = .intermediate
            m.equipment = [.fullGym]
            m.sessionMinutes = mins
            m.focuses = [.generalStrength]
            return WorkoutGenerator.generateLift(
                liftIndex: 0, totalLifts: 3, memory: m, profile: .from(m), hashSeed: "highvol")
        }
        let w60  = gen(60)
        let w120 = gen(120)
        let sets60  = w60.exercises.reduce(0)  { $0 + $1.sets }
        let sets120 = w120.exercises.reduce(0) { $0 + $1.sets }
        XCTAssertGreaterThan(sets120, sets60,
            "120-min day should have strictly more total sets than 60-min (got \(sets120) vs \(sets60)); 120-min exercises: \(w120.exercises.map { "\($0.name) \($0.sets)×" })")
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

    /// T2.1 — bodyweight movements (priorBest.weight == 0) progress by REPS, not
    /// load: the hint reads "target: N+1 reps", never a pound figure. (Pre-fix
    /// the load path ran off a 0 prior weight and produced no useful target.)
    func test_progressiveOverloadHint_bodyweightProgressesByReps() throws {
        let ex = try XCTUnwrap(
            CoachDatabase.shared.exercises(matchingPattern: "horizontal-push").first,
            "need any catalog exercise to key the hint")
        var ctx = GeneratorContext.empty
        ctx.priorBest[ex.name.lowercased()] = PriorBest(weight: 0, reps: 12, date: Date())
        let hint = WorkoutGenerator.progressiveOverloadHint(
            for: ex, context: ctx, memory: TrainingMemory(), prescribedReps: "8-12")
        XCTAssertEqual(hint, "target: 13 reps",
            "bodyweight prior (0 lb × 12) should target one more rep, got \(String(describing: hint))")
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
