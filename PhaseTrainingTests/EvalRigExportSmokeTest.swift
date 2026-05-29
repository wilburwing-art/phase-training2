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

        // Embed chest + front-delt soreness so the eval-rig Q9 has the same
        // signal real users have on an upper-push day post-bench. "high" is a
        // valid SorenessEntry.soreness value (vocabulary is none|mild|high) —
        // it reliably trips the generator's sore-muscle RPE-7 cap below.
        var soreness = SorenessEntry(date: Date())
        soreness.areas = ["chest", "shoulders"]
        soreness.soreness = "high"
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

        // Rubric gates — guard the score-bearing invariants so a generator
        // change can't silently regress the eval-rig 9/9.
        assertSetSchemeSane(workout)
        assertRestBandsRespected(workout, memory: m)
        assertSoreMuscleRPECapApplied(workout, memory: m,
                                      soreAreas: ["chest", "shoulders"])

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

    /// Lower-body day variant — (liftIndex=1, totalLifts=4) → focus.lower.
    /// Used to demo the multi-archetype rubric (eval-rig's
    /// intermediate-male-hypertrophy-lower-body snap-questions file).
    func test_export_lower_body_emits() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.liftDaysPerWeek = 4
        m.sessionMinutes = 60
        m.age = 32

        let profile = DemographicProfile.from(m)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 1,
            totalLifts: 4,
            memory: m,
            profile: profile,
            hashSeed: "eval-rig-smoke-lower"
        )

        let outDir = URL(fileURLWithPath: "/tmp/eval-rig-export-lower")
        let url = try EvalRigExporter.exportToFile(
            workout: workout,
            memory: m,
            archetype: "intermediate-male-hypertrophy-lower-body",
            timeBudgetMinutes: 60,
            to: outDir
        )
        print("[EvalRigExportSmokeTest] Wrote \(url.path) (lower-body)")
        print("[EvalRigExportSmokeTest] Exercises:")
        for ex in workout.exercises {
            print("  - \(ex.name) (\(ex.sets) sets, \(ex.warmUpSets?.count ?? 0) warm-ups)")
        }
    }

    /// Pull-day variant — (liftIndex=1, totalLifts=3) → focus.pull (the PPL
    /// pull day). Used to demo the multi-archetype rubric's third archetype
    /// (intermediate-male-hypertrophy-pull) after upper-push + lower-body.
    func test_export_pull_emits() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.liftDaysPerWeek = 3
        m.sessionMinutes = 60
        m.age = 32

        let profile = DemographicProfile.from(m)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 1,
            totalLifts: 3,
            memory: m,
            profile: profile,
            hashSeed: "eval-rig-smoke-pull"
        )

        let outDir = URL(fileURLWithPath: "/tmp/eval-rig-export-pull")
        let url = try EvalRigExporter.exportToFile(
            workout: workout,
            memory: m,
            archetype: "intermediate-male-hypertrophy-pull",
            timeBudgetMinutes: 60,
            to: outDir
        )
        print("[EvalRigExportSmokeTest] Wrote \(url.path) (pull)")
        print("[EvalRigExportSmokeTest] Exercises:")
        for ex in workout.exercises {
            print("  - \(ex.name) (\(ex.sets) sets, \(ex.warmUpSets?.count ?? 0) warm-ups)")
        }
    }

    /// Full-body day A — (liftIndex=0, totalLifts=2) → focus.fullBodyA.
    /// Fourth archetype in the multi-archetype demo (after push, lower, pull).
    /// Tests the "compound + compound + compound" recipe shape against a
    /// rubric whose Q2 enforces multi-pattern coverage rather than isolation
    /// pairing.
    func test_export_full_body_a_emits() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.liftDaysPerWeek = 2
        m.sessionMinutes = 60
        m.age = 32

        let profile = DemographicProfile.from(m)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0,
            totalLifts: 2,
            memory: m,
            profile: profile,
            hashSeed: "eval-rig-smoke-full-body-a"
        )

        let outDir = URL(fileURLWithPath: "/tmp/eval-rig-export-full-body-a")
        let url = try EvalRigExporter.exportToFile(
            workout: workout,
            memory: m,
            archetype: "intermediate-male-hypertrophy-full-body-a",
            timeBudgetMinutes: 60,
            to: outDir
        )
        print("[EvalRigExportSmokeTest] Wrote \(url.path) (full-body-A)")
        print("[EvalRigExportSmokeTest] Exercises:")
        for ex in workout.exercises {
            print("  - \(ex.name) (\(ex.sets) sets, \(ex.warmUpSets?.count ?? 0) warm-ups)")
        }
    }

    // MARK: - Phase 1 era-affinity batches
    //
    // Cohort-specific 20-workout batches the eval-rig ship gate consumes
    // for Phase 1. Both archetypes use the same equipment + soreness
    // context as the canonical intermediate-male-hypertrophy-upper-push
    // archetype documented in /Users/wilburpyn/Downloads/eval-rig-handoff.md.
    // The only thing that changes is the demographic + eraOverride —
    // letting the rubric measure whether the affinity axis produces a
    // visibly different style for older-male-bodybuilding vs gen-z-
    // science-based, while keeping the ship gate (total >= 7 AND no
    // 'no' on Q3 / Q6 / Q9) the same for both.

    /// 20 workouts for the older-male-bodybuilding cohort. Age 58 with
    /// explicit magazineBodybuilding override. Same chest+front-delt
    /// soreness as the anchor archetype.
    func test_export_batch_older_male_bodybuilding_upper_push() throws {
        try emitCohortBatch(
            archetype: "older-male-bodybuilding-cohort-upper-push",
            batchDir: "batch-007-older-male-bodybuilding",
            age: 58,
            eraOverrideRaw: EraCohort.magazineBodybuilding.rawValue,
            count: 20
        )
    }

    /// 20 workouts for the gen-z-science-based cohort. Age 22 with
    /// explicit scienceBased override.
    func test_export_batch_gen_z_science_based_upper_push() throws {
        try emitCohortBatch(
            archetype: "gen-z-science-based-upper-push",
            batchDir: "batch-008-gen-z-science",
            age: 22,
            eraOverrideRaw: EraCohort.scienceBased.rawValue,
            count: 20
        )
    }

    /// Shared batch emitter. Builds a TrainingMemory matching the
    /// anchor archetype (intermediate male, full gym, hypertrophy,
    /// 4-day split, 60-min cap, high chest/front-delt soreness)
    /// and varies hashSeed across `count` workouts so the generator's
    /// variety + tiebreak surfaces span the batch.
    private func emitCohortBatch(
        archetype: String,
        batchDir: String,
        age: Int,
        eraOverrideRaw: String,
        count: Int
    ) throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.liftDaysPerWeek = 4
        m.sessionMinutes = 60
        m.age = age
        m.gender = .male
        m.eraOverride = eraOverrideRaw

        // Chest + front-delt soreness, matching the v1 anchor. "high" is a
        // valid SorenessEntry value (none|mild|high); "moderate" is not.
        var soreness = SorenessEntry(date: Date())
        soreness.areas = ["chest", "shoulders"]
        soreness.soreness = "high"
        soreness.energy = "normal"
        m.soreness.append(soreness)

        let profile = DemographicProfile.from(m)

        // Write directly into the eval-rig workouts folder so the grader
        // can `npm run eval -- grade <batch-id>` immediately.
        let outDir = URL(fileURLWithPath: "/Users/wilburpyn/repos/eval-rig/workouts/\(batchDir)")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // exportToFile derives its filename from (planInputsHash, time)
        // and the seconds-precision timestamp would collide across the
        // batch run. Bypass it: call `encode` directly and write each
        // workout to an indexed filename ourselves.
        var workoutPaths: [String] = []
        for i in 0..<count {
            let workout = WorkoutGenerator.generateLift(
                liftIndex: 0,                       // upper-push slot
                totalLifts: 4,
                memory: m,
                profile: profile,
                // Vary the seed so the deterministic-pick + variety + era
                // aesthetic tiebreaker land on different candidates across
                // the 20 workouts. Each integer maps to a distinct stable
                // pick — same code path the real per-week generator runs.
                hashSeed: "phase1-era-batch-\(batchDir)-\(String(format: "%02d", i + 1))"
            )
            XCTAssertFalse(workout.exercises.isEmpty,
                           "Empty workout at i=\(i) for \(archetype)")
            let data = try EvalRigExporter.encode(
                workout: workout,
                memory: m,
                archetype: archetype,
                timeBudgetMinutes: 60
            )
            let fileName = "\(archetype)-\(String(format: "%02d", i + 1)).json"
            let url = outDir.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            workoutPaths.append(url.path)
        }

        print("[EvalRigBatch] \(archetype) → \(workoutPaths.count) workouts in \(outDir.path)")
        for p in workoutPaths {
            print("[EvalRigBatch]   - \(p)")
        }
    }

    /// Non-sore variant — same archetype, no SorenessEntry. Exercises the
    /// warm-up-synthesis path that the sore variant intentionally skips
    /// (synthesizeWarmups returns nil on sore prime movers). Used to show
    /// that the rubric's Q1 (ramp-set check) fires for a normal-day export.
    func test_export_nosoreness_emits_warmups() throws {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.liftDaysPerWeek = 4
        m.sessionMinutes = 60
        m.age = 32

        let profile = DemographicProfile.from(m)
        let workout = WorkoutGenerator.generateLift(
            liftIndex: 0,
            totalLifts: 4,
            memory: m,
            profile: profile,
            hashSeed: "eval-rig-smoke-nosore"
        )

        // No soreness → set scheme + rest bands still hold, and the slot-0
        // compound prime mover gets synthesized warm-up ramp sets (the path
        // the sore variant intentionally skips). Rubric Q1 depends on these.
        assertSetSchemeSane(workout)
        assertRestBandsRespected(workout, memory: m)
        assertWarmupRampPresentOnPrimaryCompound(workout)

        let outDir = URL(fileURLWithPath: "/tmp/eval-rig-export")
        let url = try EvalRigExporter.exportToFile(
            workout: workout,
            memory: m,
            archetype: "intermediate-male-hypertrophy-upper-push",
            timeBudgetMinutes: 60,
            to: outDir
        )
        print("[EvalRigExportSmokeTest] Wrote \(url.path) (non-sore variant)")
    }

    // MARK: - Rubric assertions
    //
    // These guard the gates the eval-rig rubric scores (set scheme, rest
    // bands, sore-muscle RPE cap, warm-up ramp). Kept tolerant of legitimate
    // generator variety (exact exercise picks, rep strings) while pinning the
    // invariants a regression would break.

    /// Every prescribed exercise must have a real set count and a non-empty
    /// reps target. Catches a generator that drops sets/reps on a slot.
    private func assertSetSchemeSane(_ workout: GeneratedWorkout) {
        XCTAssertFalse(workout.exercises.isEmpty, "Workout must have exercises")
        for ex in workout.exercises {
            XCTAssertGreaterThanOrEqual(ex.sets, 1, "\(ex.name): sets must be >= 1")
            XCTAssertLessThanOrEqual(ex.sets, 6, "\(ex.name): sets unexpectedly high (\(ex.sets))")
            XCTAssertFalse(ex.reps.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(ex.name): reps target must be non-empty")
        }
    }

    /// Rest bands the rubric's Q7 enforces: every slot has a positive rest;
    /// hypertrophy primary-compound lower/full-body lead lift rests >= 180s,
    /// compound pull primary >= 120s.
    private func assertRestBandsRespected(_ workout: GeneratedWorkout, memory: TrainingMemory) {
        for ex in workout.exercises {
            XCTAssertGreaterThanOrEqual(ex.restSeconds, 45,
                                        "\(ex.name): rest must be a sane positive band")
            XCTAssertLessThanOrEqual(ex.restSeconds, 300,
                                     "\(ex.name): rest unexpectedly long (\(ex.restSeconds)s)")
        }
        // The heavy lower/full-body compound lead lift must respect the 3-min
        // floor. Only assert when such a slot exists (upper-push won't have one).
        if let lead = workout.exercises.first, lead.isCompound,
           memory.primaryFocus == .hypertrophy,
           let pattern = lead.pattern,
           pattern.contains("squat") || pattern.contains("hinge") || pattern.contains("deadlift") {
            XCTAssertGreaterThanOrEqual(lead.restSeconds, 180,
                "Heavy compound lead lift \(lead.name) must rest >= 180s")
        }
    }

    /// With the given muscle areas sore, every exercise whose primary muscle
    /// buckets into a sore area must be capped to RPE 7 (3 RIR). This is the
    /// down-regulation Item 2 makes reachable for "mild"/"high" reports.
    private func assertSoreMuscleRPECapApplied(_ workout: GeneratedWorkout,
                                               memory: TrainingMemory,
                                               soreAreas: Set<String>) {
        var sawCappedExercise = false
        for ex in workout.exercises {
            let muscles = CoachDatabase.shared.musclesForExercise(ex.exerciseId)
            let primary = muscles.first(where: { $0.role == "primary" })
            guard let slug = primary?.slug,
                  let bucket = MuscleBucket.bucket(forSlug: slug)?.rawValue,
                  soreAreas.contains(bucket) else { continue }
            sawCappedExercise = true
            XCTAssertEqual(ex.rpe, "7",
                "\(ex.name) loads sore \(bucket) as primary — RPE must be capped to 7, got \(ex.rpe ?? "nil")")
        }
        XCTAssertTrue(sawCappedExercise,
            "Expected at least one exercise primary-loading a sore area to exercise the RPE cap")
    }

    /// The slot-0 compound prime mover on a non-sore day must carry warm-up
    /// ramp sets (5/5/3 at 40/60/80 %TM). Rubric Q1 (ramp-set check).
    private func assertWarmupRampPresentOnPrimaryCompound(_ workout: GeneratedWorkout) {
        guard let lead = workout.exercises.first(where: { $0.isCompound }) else {
            return XCTFail("Expected at least one compound exercise")
        }
        let warmups = lead.warmUpSets ?? []
        XCTAssertFalse(warmups.isEmpty,
            "Non-sore compound prime mover \(lead.name) must have synthesized warm-up sets")
        for w in warmups {
            XCTAssertGreaterThan(w.reps, 0, "warm-up reps must be positive")
            XCTAssertGreaterThan(w.loadPctOfWorking, 0, "warm-up load %% must be positive")
            XCTAssertLessThan(w.loadPctOfWorking, 100, "warm-up load %% must be below working load")
        }
    }
}
