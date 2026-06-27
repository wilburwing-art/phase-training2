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

    // MARK: - Consolidated (merged) day generation (D3)

    func test_generateConsolidated_mergedDay_includesBothFocuses() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
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

    // MARK: - T1.2 time/distance prescriptions survive the focus-bias band

    /// Wall Sit is stored as "30-60 sec" in coach.db. A hypertrophy user's
    /// 8-15 accessory band (and the era nudge) must NOT overwrite it — an
    /// isometric prescribed in reps is the global "isometrics in reps" smell.
    func test_prescription_preservesTimeBasedRepsOverFocusBias() throws {
        let wallSit = CoachDatabase.shared.listExercises(search: "Wall Sit").first { $0.name == "Wall Sit" }
        try XCTSkipIf(wallSit == nil, "Wall Sit not in coach.db")
        var m = TrainingMemory()
        m.experience = .intermediate
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

    /// Find a catalog exercise with NO same-pattern curated substitute (the
    /// ~70% uncovered case) whose pattern pool still contains another
    /// exercise sharing a primary muscle — the fixture for the fallback
    /// tests. Scans for data presence per the test-by-coverage skill.
    private func fallbackFixture() throws -> (orig: Exercise, pattern: String, pool: [Exercise]) {
        for p in ["horizontal-push", "squat", "horizontal-pull", "hip-hinge", "vertical-push", "vertical-pull", "elbow-flexion", "elbow-extension"] {
            let pool = CoachDatabase.shared.exercises(matchingPattern: p)
            for e in pool {
                let hasSamePatternSub = CoachDatabase.shared.substitutes(forExerciseId: e.id).contains { s in
                    s.exercise.id != e.id
                        && Set(CoachDatabase.shared.patternsForExercise(s.exercise.id)).contains(p)
                }
                if hasSamePatternSub { continue }
                let primaries = Set(CoachDatabase.shared.musclesForExercise(e.id)
                    .filter { $0.role == "primary" }.map(\.slug))
                guard !primaries.isEmpty else { continue }
                let hasOverlapPeer = pool.contains { c in
                    c.id != e.id && !Set(CoachDatabase.shared.musclesForExercise(c.id)
                        .filter { $0.role == "primary" }.map(\.slug)).isDisjoint(with: primaries)
                }
                if hasOverlapPeer { return (e, p, pool) }
            }
        }
        throw XCTSkip("no catalog exercise without a curated same-pattern substitute has a muscle-overlap peer")
    }

    /// The pattern-pool fallback: an uncovered stagnant exercise still gets
    /// swapped — to a same-pattern candidate sharing a primary muscle —
    /// instead of silently keeping the stagnant pick.
    func test_stagnationSwap_fallbackFiresWhenNoCuratedSubstitute() throws {
        let (orig, pattern, pool) = try fallbackFixture()
        var ctx = GeneratorContext.empty
        ctx.stagnantExercises = [orig.name.lowercased()]
        let slot = PatternSlot(alternatives: [pattern], optional: false)
        let result = WorkoutGenerator.applyStagnationSwap(
            original: orig, context: ctx, envs: [], allowedEquipmentSlugs: [],
            excludeKws: [], excludeIds: [], slot: slot,
            fallbackPool: { pool })

        XCTAssertNotEqual(result.id, orig.id,
            "fallback should swap uncovered stagnant '\(orig.name)' (pattern \(pattern))")
        let op = Set(CoachDatabase.shared.musclesForExercise(orig.id)
            .filter { $0.role == "primary" }.map(\.slug))
        let np = Set(CoachDatabase.shared.musclesForExercise(result.id)
            .filter { $0.role == "primary" }.map(\.slug))
        XCTAssertFalse(op.isDisjoint(with: np),
            "fallback swap '\(orig.name)' → '\(result.name)' must share a primary muscle")
    }

    /// Hysteresis: candidates in `recentlyPicked` are hard-excluded from
    /// BOTH the curated and fallback paths — when everything viable is
    /// recent, the swap conservatively keeps the original (blocks the
    /// A↔B oscillation the generator audit flagged).
    func test_stagnationSwap_hysteresis_skipsRecentlyPicked() throws {
        let (orig, pattern, pool) = try fallbackFixture()
        var ctx = GeneratorContext.empty
        ctx.stagnantExercises = [orig.name.lowercased()]
        let slot = PatternSlot(alternatives: [pattern], optional: false)
        // Every possible candidate — curated subs AND the whole fallback
        // pool — is "recently picked".
        let allRecent = Set(pool.map(\.id))
            .union(CoachDatabase.shared.substitutes(forExerciseId: orig.id).map(\.exercise.id))
        let result = WorkoutGenerator.applyStagnationSwap(
            original: orig, context: ctx, envs: [], allowedEquipmentSlugs: [],
            excludeKws: [], excludeIds: [], recentlyPicked: allRecent,
            slot: slot, fallbackPool: { pool })
        XCTAssertEqual(result.id, orig.id,
            "all candidates recent → keep the original rather than oscillate")
    }

    /// The fallback rank (muscle-overlap desc, id asc) has no RNG — same
    /// inputs must produce the same swap.
    func test_stagnationSwap_fallback_deterministic() throws {
        let (orig, pattern, pool) = try fallbackFixture()
        var ctx = GeneratorContext.empty
        ctx.stagnantExercises = [orig.name.lowercased()]
        let slot = PatternSlot(alternatives: [pattern], optional: false)
        let run: () -> Exercise = {
            WorkoutGenerator.applyStagnationSwap(
                original: orig, context: ctx, envs: [], allowedEquipmentSlugs: [],
                excludeKws: [], excludeIds: [], slot: slot,
                fallbackPool: { pool })
        }
        XCTAssertEqual(run().id, run().id, "fallback pick must be deterministic")
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
