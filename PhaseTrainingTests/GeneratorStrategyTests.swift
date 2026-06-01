import XCTest
@testable import PhaseTraining

/// PR 2 of the option-D arc. Tests the LLM-strategist half — strategy
/// application inside WorkoutGenerator + the build_workout tool decoder.
final class GeneratorStrategyTests: XCTestCase {

    // MARK: - Strategy application: focus override

    func test_focusOverride_overridesLiftIndexDerivation() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        let p = DemographicProfile.from(m)
        // liftIndex 1 of 3 = pull. Strategy says push.
        var s = GeneratorStrategy.auto
        s.focus = .push
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 1, totalLifts: 3,
            memory: m, profile: p, hashSeed: "focus-test",
            strategy: s
        )
        XCTAssertEqual(workout.title, WorkoutFocus.push.title,
                       "strategy.focus = .push should win over liftIndex-derived pull")
    }

    // MARK: - Strategy application: intensity bias

    func test_intensityBias_deload_dropsSetCounts() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        let p = DemographicProfile.from(m)

        let normal = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "intensity",
            strategy: .auto
        )

        var deload = GeneratorStrategy.auto
        deload.intensityBias = .deload
        let deloaded = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "intensity",
            strategy: deload
        )

        let normalTotal = normal.exercises.reduce(0) { $0 + $1.sets }
        let deloadTotal = deloaded.exercises.reduce(0) { $0 + $1.sets }
        XCTAssertLessThan(deloadTotal, normalTotal,
                          "deload should drop total sets (normal=\(normalTotal), deload=\(deloadTotal))")
    }

    // MARK: - Strategy application: deprioritize patterns

    func test_deprioritizePatterns_removesAlternativesFromSlotPick() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        let p = DemographicProfile.from(m)

        // Deprioritize every common squat / hinge / lunge pattern. The
        // legs-day slots all anchor on these — workout should end up
        // mostly empty (every slot's alternatives wiped).
        var strat = GeneratorStrategy.auto
        strat.deprioritizePatterns = [
            "squat", "hip-hinge", "lunge", "single-leg-squat", "calf-raise"
        ]
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 2, totalLifts: 3,  // legs day
            memory: m, profile: p, hashSeed: "deprio",
            strategy: strat
        )
        // No assertion on exact count — the slots' alternatives lists vary —
        // but the deprioritized patterns must not appear as `pattern` on
        // any picked exercise.
        let chosenPatterns = workout.exercises.compactMap(\.pattern)
        for pattern in strat.deprioritizePatterns {
            XCTAssertFalse(chosenPatterns.contains(pattern),
                           "deprioritized pattern \(pattern) leaked into picks: \(chosenPatterns)")
        }
    }

    // MARK: - Strategy application: targetWeightOverrides

    func test_targetWeightOverride_winsOverPriorBest() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.usesImperial = true
        let p = DemographicProfile.from(m)

        // Probe to learn what the generator picks first under this config.
        let probe = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "override-probe"
        )
        guard let picked = probe.exercises.first else { return XCTFail() }

        var ctx = GeneratorContext.empty
        ctx.priorBest[picked.name.lowercased()] = PriorBest(
            weight: 200, reps: 5, date: Date()
        )

        var strat = GeneratorStrategy.auto
        strat.targetWeightOverrides[picked.name.lowercased()] = 175  // explicit deload

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "override-probe",
            context: ctx, strategy: strat
        )
        let match = workout.exercises.first { $0.name == picked.name }
        XCTAssertEqual(match?.notes, "target: 175 lb",
                       "override should win over priorBest-derived target (load only, no rep count). Got: \(String(describing: match?.notes))")
    }

    // MARK: - Decoder

    func test_decoder_parsesValidPayload() {
        let json = """
        {
          "focus": "pull",
          "durationMinutes": 50,
          "emphasizePatterns": ["horizontal-pull", "vertical-pull"],
          "deprioritizePatterns": ["squat"],
          "intensityBias": "deload",
          "targetWeightOverrides": [
            {"exerciseName": "Bench Press", "weightLb": 180}
          ],
          "reasoning": "Pull side is undertrained, easing volume because of yesterday."
        }
        """.data(using: .utf8)!
        guard let proposal = CoachToolDecoder.decodeBuildWorkout(from: json) else {
            return XCTFail("decoder returned nil")
        }
        XCTAssertEqual(proposal.strategy.focus, .pull)
        XCTAssertEqual(proposal.strategy.durationMinutes, 50)
        XCTAssertEqual(proposal.strategy.emphasizePatterns, ["horizontal-pull", "vertical-pull"])
        XCTAssertEqual(proposal.strategy.deprioritizePatterns, ["squat"])
        XCTAssertEqual(proposal.strategy.intensityBias, .deload)
        XCTAssertEqual(proposal.strategy.targetWeightOverrides["bench press"], 180)
        XCTAssertEqual(proposal.reasoning, "Pull side is undertrained, easing volume because of yesterday.")
    }

    func test_decoder_handlesMissingOptionalFields() {
        // Minimum-valid payload — schema only requires focus + reasoning.
        let json = """
        {
          "focus": "push",
          "reasoning": "Default."
        }
        """.data(using: .utf8)!
        guard let proposal = CoachToolDecoder.decodeBuildWorkout(from: json) else {
            return XCTFail("decoder returned nil")
        }
        XCTAssertEqual(proposal.strategy.focus, .push)
        XCTAssertNil(proposal.strategy.durationMinutes)
        XCTAssertTrue(proposal.strategy.emphasizePatterns.isEmpty)
        XCTAssertEqual(proposal.strategy.intensityBias, .normal,
                       "missing intensityBias should default to normal, not crash")
    }

    func test_decoder_clampsAndSanitizes() {
        // Hallucinated values: huge duration, invalid focus, negative weight.
        let json = """
        {
          "focus": "leg_day_blast",
          "durationMinutes": 9999,
          "intensityBias": "ULTRA",
          "targetWeightOverrides": [
            {"exerciseName": "Bench", "weightLb": -50},
            {"exerciseName": "Squat", "weightLb": 9999}
          ],
          "reasoning": "bad llm output."
        }
        """.data(using: .utf8)!
        guard let proposal = CoachToolDecoder.decodeBuildWorkout(from: json) else {
            return XCTFail()
        }
        XCTAssertNil(proposal.strategy.focus, "unknown focus = nil, fall through to default")
        XCTAssertEqual(proposal.strategy.durationMinutes, 180, "duration clamped to 180")
        XCTAssertEqual(proposal.strategy.intensityBias, .normal, "unknown intensity = normal default")
        XCTAssertNil(proposal.strategy.targetWeightOverrides["bench"], "negative weight rejected")
        XCTAssertNil(proposal.strategy.targetWeightOverrides["squat"], "weight > 1000 rejected")
    }

    func test_decoder_returnsNilForGarbage() {
        let json = "{ not even json".data(using: .utf8)!
        XCTAssertNil(CoachToolDecoder.decodeBuildWorkout(from: json))
    }

    // MARK: - .auto is identity

    func test_autoStrategy_isNoOp() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        let p = DemographicProfile.from(m)
        let withAuto = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "auto",
            strategy: .auto
        )
        let withoutStrategy = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "auto"
        )
        XCTAssertEqual(withAuto.exercises.map(\.exerciseId),
                       withoutStrategy.exercises.map(\.exerciseId),
                       ".auto strategy should leave generator behavior identical to no strategy")
    }
}
