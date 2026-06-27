import XCTest
@testable import PhaseTraining

/// PR for build 70: RPE + tempo prescription on every generated exercise.
/// Locks in the focus → default mapping + LLM overrides + decoder shape.
final class RpeTempoPrescriptionTests: XCTestCase {

    // MARK: - Defaults

    func test_strengthPrimary_emitsLowerVolume() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.generalStrength]
        let p = DemographicProfile.from(m)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "s-prim"
        )
        guard let first = workout.exercises.first else { return XCTFail() }
        XCTAssertEqual(first.rpe, "8", "general strength primary should be RPE 8")
    }

    // MARK: - LLM overrides

    func test_strategyOverridesWinOverDefaults() {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        let p = DemographicProfile.from(m)

        // Probe to see what gets picked first.
        let probe = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "ovr"
        )
        guard let picked = probe.exercises.first else { return XCTFail() }

        var s = GeneratorStrategy.auto
        s.rpeOverrides[picked.name.lowercased()] = "5-6"
        s.tempoOverrides[picked.name.lowercased()] = "5-3-1-0"

        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0, totalLifts: 3,
            memory: m, profile: p, hashSeed: "ovr",
            strategy: s
        )
        let match = workout.exercises.first { $0.name == picked.name }
        XCTAssertEqual(match?.rpe, "5-6", "LLM strategy RPE override should win")
        XCTAssertEqual(match?.tempo, "5-3-1-0", "LLM strategy tempo override should win")
    }

    // MARK: - Decoder

    func test_decoder_parsesExercisePrescriptions() {
        let json = """
        {
          "focus": "push",
          "reasoning": "Volume on chest + tight tempo.",
          "exercisePrescriptions": [
            {"exerciseName": "Bench Press", "rpe": "8-9", "tempo": "3-0-1-0"},
            {"exerciseName": "Pull-Up", "rpe": "9"}
          ]
        }
        """.data(using: .utf8)!
        guard let proposal = CoachToolDecoder.decodeBuildWorkout(from: json) else {
            return XCTFail("decoder returned nil")
        }
        XCTAssertEqual(proposal.strategy.rpeOverrides["bench press"], "8-9")
        XCTAssertEqual(proposal.strategy.tempoOverrides["bench press"], "3-0-1-0")
        XCTAssertEqual(proposal.strategy.rpeOverrides["pull-up"], "9")
        XCTAssertNil(proposal.strategy.tempoOverrides["pull-up"],
                     "missing tempo for pull-up should not populate the override map")
    }

    func test_decoder_skipsEmptyStrings() {
        let json = """
        {
          "focus": "push",
          "reasoning": "Test.",
          "exercisePrescriptions": [
            {"exerciseName": "Bench", "rpe": "", "tempo": ""}
          ]
        }
        """.data(using: .utf8)!
        guard let proposal = CoachToolDecoder.decodeBuildWorkout(from: json) else { return XCTFail() }
        XCTAssertNil(proposal.strategy.rpeOverrides["bench"])
        XCTAssertNil(proposal.strategy.tempoOverrides["bench"])
    }
}
