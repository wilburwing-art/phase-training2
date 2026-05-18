// WorkoutDiffBuilderTests.swift — Phase 13d/13f workout-edit shaping.
//
// WorkoutDiffBuilder.diff(for:workout:) takes a CoachWorkoutProposal and a
// snapshot of today's GeneratedWorkout and returns a WorkoutDiff (before +
// after). Swap preserves slot id and per-exercise targets; adjust clamps
// numeric inputs; unknown names are skipped silently.

import XCTest
@testable import PhaseTraining

final class WorkoutDiffBuilderTests: XCTestCase {

    // MARK: - Fixture

    private func fixtureWorkout() -> GeneratedWorkout {
        GeneratedWorkout(
            title: "Push Day",
            summary: "5 movements · ~45 min",
            exercises: [
                GeneratedExercise(id: "ex-0", exerciseId: 11, name: "Bench Press",
                                  pattern: "horizontal_push", isCompound: true,
                                  sets: 5, reps: "5", restSeconds: 180, notes: nil),
                GeneratedExercise(id: "ex-1", exerciseId: 12, name: "Overhead Press",
                                  pattern: "vertical_push", isCompound: true,
                                  sets: 4, reps: "8", restSeconds: 120, notes: nil),
                GeneratedExercise(id: "ex-2", exerciseId: 13, name: "Dips",
                                  pattern: "vertical_push", isCompound: false,
                                  sets: 3, reps: "8-10", restSeconds: 90, notes: nil),
            ],
            estimatedMinutes: 45,
            provenance: "test"
        )
    }

    private func proposal(_ changes: [WorkoutChange]) -> CoachWorkoutProposal {
        CoachWorkoutProposal(dateString: "2026-05-18", changes: changes, reasoning: "test")
    }

    // MARK: - swap

    func testSwapReplacesByNameCaseInsensitive() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([WorkoutChange(op: "swap", fromName: "bench press", toName: "Floor Press")]),
            workout: workout
        )
        XCTAssertFalse(diff.isNoop)
        XCTAssertEqual(diff.after.exercises[0].name, "Floor Press")
    }

    func testSwapPreservesSlotIdAndTargets() {
        let workout = fixtureWorkout()
        let priorBench = workout.exercises[0]
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([WorkoutChange(op: "swap", fromName: "Bench Press", toName: "DB Bench")]),
            workout: workout
        )
        let after = diff.after.exercises[0]
        XCTAssertEqual(after.id, priorBench.id, "Slot id should survive swap (session pairing relies on it)")
        XCTAssertEqual(after.sets, priorBench.sets)
        XCTAssertEqual(after.reps, priorBench.reps)
        XCTAssertEqual(after.restSeconds, priorBench.restSeconds)
        XCTAssertEqual(after.exerciseId, 0, "exerciseId=0 sentinel marks 'no coach.db ref'")
    }

    func testSwapWithUnknownFromNameIsNoop() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([WorkoutChange(op: "swap", fromName: "Goblet Squat", toName: "Front Squat")]),
            workout: workout
        )
        XCTAssertTrue(diff.isNoop)
    }

    // MARK: - adjust

    func testAdjustClampsSetsToRange() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([
                WorkoutChange(op: "adjust", exerciseName: "Bench Press", sets: 0),     // → 1
                WorkoutChange(op: "adjust", exerciseName: "Overhead Press", sets: 99), // → 20
            ]),
            workout: workout
        )
        XCTAssertEqual(diff.after.exercises[0].sets, 1)
        XCTAssertEqual(diff.after.exercises[1].sets, 20)
    }

    func testAdjustClampsRestSecondsToRange() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([
                WorkoutChange(op: "adjust", exerciseName: "Bench Press", restSeconds: 5),     // → 15
                WorkoutChange(op: "adjust", exerciseName: "Dips", restSeconds: 9999),         // → 600
            ]),
            workout: workout
        )
        XCTAssertEqual(diff.after.exercises[0].restSeconds, 15)
        XCTAssertEqual(diff.after.exercises[2].restSeconds, 600)
    }

    func testAdjustRepsIsFreeText() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([
                WorkoutChange(op: "adjust", exerciseName: "Dips", reps: "AMRAP")
            ]),
            workout: workout
        )
        XCTAssertEqual(diff.after.exercises[2].reps, "AMRAP")
    }

    func testAdjustUnknownNameIsNoop() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([WorkoutChange(op: "adjust", exerciseName: "Squat", sets: 3)]),
            workout: workout
        )
        XCTAssertTrue(diff.isNoop)
    }

    // MARK: - mixed batch

    func testMultipleChangesApplyIndependently() {
        let workout = fixtureWorkout()
        let diff = WorkoutDiffBuilder.diff(
            for: proposal([
                WorkoutChange(op: "swap", fromName: "Bench Press", toName: "DB Bench"),
                WorkoutChange(op: "adjust", exerciseName: "Dips", sets: 5),
            ]),
            workout: workout
        )
        XCTAssertEqual(diff.after.exercises[0].name, "DB Bench")
        XCTAssertEqual(diff.after.exercises[2].sets, 5)
        XCTAssertEqual(diff.after.exercises[1].name, "Overhead Press", "Untouched exercise unchanged")
    }
}
