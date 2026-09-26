// TwinDiagnosisTests.swift — 1a-2: slicing the shadow twin's errors.

import XCTest
@testable import PhaseTraining

final class TwinDiagnosisTests: XCTestCase {

    private func pair(_ ex: String, day: Int, last: Int, pred: Double, base: Double, actual: Double, reps: Int)
        -> TrainingLoadModel.ScoredPair {
        .init(exercise: ex, day: day, lastDay: last, predicted: pred, baseline: base, actual: actual, actualReps: reps)
    }

    func test_slicesByRepsGapAndExercise_andMeasuresDirection() {
        let pairs = [
            pair("squat", day: 10, last: 7, pred: 205, base: 200, actual: 210, reps: 3),   // right direction
            pair("squat", day: 14, last: 10, pred: 205, base: 210, actual: 212, reps: 5),  // wrong direction
            pair("curl", day: 40, last: 10, pred: 50, base: 50, actual: 45, reps: 12),     // no predicted move
        ]
        let d = TwinDiagnosis.make(pairs, trainingDays: [7, 10, 14, 40])
        XCTAssertEqual(d.overall.n, 3)
        XCTAssertEqual(d.byReps.map(\.n), [2, 0, 1])
        XCTAssertEqual(d.byGap.map(\.n), [2, 0, 1])
        XCTAssertEqual(d.byExercise.first?.label, "squat")
        XCTAssertEqual(d.directionPairs, 2, "a pair the twin did not move is not a direction call")
        XCTAssertEqual(d.directionAgreement, 0.5, accuracy: 1e-9)
        // Days 7 and 10 share block 1 (days 7-13), so both are dense; 14 and 40 are alone.
        XCTAssertEqual(d.dense.n, 1)
        XCTAssertEqual(d.sparse.n, 2)
        XCTAssertEqual(d.overall.maeBaseline, (10 + 2 + 5) / 3.0, accuracy: 1e-9)
    }

    /// Opt-in: the real export, default parameters (no fitting), walk-forward
    /// over every day after a 16-week warm-up, plus the 8-week holdout.
    func test_diagnose_realFitbodHistory() throws {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["TWIN_FITBOD_CSV"], env["TEST_RUNNER_TWIN_FITBOD_CSV"],
                          "/Users/wilburpyn/repos/workout-plan/data/fitbod-history.csv"].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw XCTSkip("No Fitbod export found; set TWIN_FITBOD_CSV to run the diagnosis.")
        }
        let parsed = FitbodCSVParser.parse(try String(contentsOfFile: path, encoding: .utf8),
                                           nameResolver: { ExerciseLookupCache.shared.exerciseID(forName: $0) })
        let effort = parsed.sets.filter { $0.rpe != nil || $0.rir != nil }.count
        let sets = TwinInputs.sets(from: parsed.sets)
        let model = TrainingLoadModel(sets: sets, patternFor: TwinInputs.pattern(for:))
        let days = model.trainingDays
        let first = try XCTUnwrap(days.first), last = try XCTUnwrap(days.last)
        let full = TwinDiagnosis.make(model.scoredPairs(days: (first + 112)...last), trainingDays: days)
        let holdout = TwinDiagnosis.make(model.scoredPairs(days: (last - 55)...last), trainingDays: days)
        print("TWIN-DIAG sets=\(sets.count) days=\(days.count) setsWithRPEorRIR=\(effort)")
        print("TWIN-DIAG FULL\n" + full.report)
        print("TWIN-DIAG HOLDOUT\n" + holdout.report)
        XCTAssertGreaterThan(full.overall.n, 200, "too few pairs to slice")
    }
}
