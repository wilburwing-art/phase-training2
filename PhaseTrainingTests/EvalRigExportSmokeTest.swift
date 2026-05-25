// EvalRigExportSmokeTest — exercises EvalRigExporter end-to-end so the
// DEBUG-only export path can be validated headlessly. NOT a proper unit test
// — runs the full generator + writes a file to /tmp/ so the eval-rig pipeline
// can consume it. Skip in CI; this is a development-time tool.

import XCTest
@testable import PhaseTraining

final class EvalRigExportSmokeTest: XCTestCase {
    /// Build a realistic intermediate-male-hypertrophy TrainingMemory, run
    /// generateLift via the same code path the app's "Export eval-rig JSON"
    /// button uses, write the JSON to a deterministic /tmp/ path the grader
    /// can read back. Output is whatever the current generator produces —
    /// the test doesn't assert content, it just dumps for grading.
    func test_export_emits_intermediate_hypertrophy_upper_push() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.liftDaysPerWeek = 4
        m.sessionMinutes = 60
        m.age = 32

        // Embed moderate chest + front-delt soreness so the eval-rig Q9 has
        // the same signal real users have on an upper-push day post-bench.
        var soreness = SorenessEntry(date: Date())
        soreness.areas = ["chest", "shoulders"]
        soreness.soreness = "moderate"
        soreness.energy = "normal"
        m.soreness.append(soreness)

        let profile = DemographicProfile.from(m)

        // Upper-push day = totalLifts=4, liftIndex=0 → upper-push focus.
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0,
            totalLifts: 4,
            memory: m,
            profile: profile,
            hashSeed: "eval-rig-smoke-test"
        )

        XCTAssertFalse(workout.exercises.isEmpty, "Generator should produce a non-empty upper-push workout")

        let outDir = URL(fileURLWithPath: "/tmp/eval-rig-export")
        let url = try EvalRigExporter.exportToFile(
            workout: workout,
            memory: m,
            archetype: "intermediate-male-hypertrophy-upper-push",
            timeBudgetMinutes: 60,
            to: outDir
        )

        print("[EvalRigExportSmokeTest] Wrote \(url.path)")
        print("[EvalRigExportSmokeTest] Exercises: \(workout.exercises.count)")
        for ex in workout.exercises {
            print("[EvalRigExportSmokeTest]   - \(ex.name) — \(ex.sets)×\(ex.reps) @ \(ex.rpe ?? "-")")
        }

        // Print the JSON to stdout so the grader can extract it from the
        // xcresult bundle without needing the simulator's data container.
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) {
            print("[EvalRigExportSmokeTest] JSON BEGIN")
            print(s)
            print("[EvalRigExportSmokeTest] JSON END")
        }
    }
}
