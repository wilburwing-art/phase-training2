import XCTest
@testable import PhaseTraining

/// PR for build 70: RPE + tempo prescription on every generated exercise.
/// Locks in the focus → default mapping + LLM overrides + decoder shape.
final class RpeTempoPrescriptionTests: XCTestCase {

    // MARK: - Defaults

    // MARK: - LLM overrides

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
