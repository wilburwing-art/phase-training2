import XCTest
@testable import PhaseTraining

/// PR 2 of the option-D arc. Tests the LLM-strategist half — strategy
/// application inside WorkoutGenerator + the build_workout tool decoder.
final class GeneratorStrategyTests: XCTestCase {

    // MARK: - Strategy application: focus override

    // MARK: - Strategy application: intensity bias

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

    func test_decoder_clampsImplausiblePrescriptions() {
        // Type-valid but semantically implausible RPE / tempo: clamp into
        // the sane range, don't drop the prescription or the payload.
        let json = """
        {
          "focus": "push",
          "exercisePrescriptions": [
            {"exerciseName": "Bench Press", "rpe": "15", "tempo": "99-99-99-99"},
            {"exerciseName": "Squat", "rpe": "8-12"},
            {"exerciseName": "Pull-Up", "rpe": "AMRAP", "tempo": "2-0-X-0"}
          ],
          "reasoning": "overcooked llm output."
        }
        """.data(using: .utf8)!
        guard let proposal = CoachToolDecoder.decodeBuildWorkout(from: json) else {
            return XCTFail()
        }
        XCTAssertEqual(proposal.strategy.rpeOverrides["bench press"], "10",
                       "RPE 15 capped to the scale's ceiling")
        XCTAssertEqual(proposal.strategy.tempoOverrides["bench press"], "10-10-10-10",
                       "tempo components capped at 10 s")
        XCTAssertEqual(proposal.strategy.rpeOverrides["squat"], "8-10",
                       "range max capped, min preserved")
        XCTAssertEqual(proposal.strategy.rpeOverrides["pull-up"], "AMRAP",
                       "unparseable RPE passes through unchanged")
        XCTAssertEqual(proposal.strategy.tempoOverrides["pull-up"], "2-0-X-0",
                       "explosive 'X' tempo passes through unchanged")
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
