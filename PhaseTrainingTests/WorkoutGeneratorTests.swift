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

    // MARK: - Superset structure (D4)

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

    // MARK: - Consolidated (merged) day generation (D3)

    // MARK: - Profile-driven prescription

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

    // MARK: - Determinism

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

    // MARK: - T1.1 bodyweight degradation floor

    // MARK: - Stagnation swap

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

    // MARK: - Duration budget

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

    // MARK: - Build 97: deload reduces sets, not exercise count

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
