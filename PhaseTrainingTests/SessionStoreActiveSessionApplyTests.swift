// SessionStoreActiveSessionApplyTests.swift — Phase 13f loss-prevention.
//
// SessionStore.applyWorkoutDiffToActiveSession must mutate the live exercise
// list to reflect a coach swap/adjust WITHOUT losing user-entered logged sets.
// These tests pin the contract because regressing it would silently delete
// logged work mid-session.

import XCTest
@testable import PhaseTraining

final class SessionStoreActiveSessionApplyTests: XCTestCase {

    // MARK: - Fixture helpers

    private func defaults() -> UserDefaults {
        let suite = "SessionStoreActiveSessionApplyTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func gex(_ id: String, _ exerciseId: Int, _ name: String, sets: Int, reps: String, rest: Int) -> GeneratedExercise {
        GeneratedExercise(id: id, exerciseId: exerciseId, name: name,
                          pattern: nil, isCompound: true,
                          sets: sets, reps: reps, restSeconds: rest, notes: nil)
    }

    private func workout(_ exs: [GeneratedExercise], title: String = "Push") -> GeneratedWorkout {
        GeneratedWorkout(title: title, summary: "test", exercises: exs, estimatedMinutes: 45, provenance: "test")
    }

    private func loggedExercise(_ id: String, _ name: String, target: Int, doneCount: Int) -> LoggedExercise {
        let sets = (0..<target).map { i in
            LoggedSet(num: i + 1,
                      weight: i < doneCount ? "135" : "",
                      reps: i < doneCount ? "5" : "",
                      rpe: i < doneCount ? "8" : "",
                      done: i < doneCount)
        }
        return LoggedExercise(id: id, name: name, type: nil, unit: "lbs",
                              targetSets: target, targetReps: 5, rest: 180,
                              sets: sets, prevSets: [])
    }

    // MARK: - Preserve done=true on surviving exercises

    func testAdjustPreservesAllDoneSetsOnSurvivingExercise() {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(
            templateId: "gen-test",
            name: "Push Day",
            category: "Generated",
            startTime: Date(),
            exercises: [loggedExercise("gex-ex-0", "Bench Press", target: 5, doneCount: 4)],
            feel: nil, note: nil
        ))

        let before = workout([gex("ex-0", 11, "Bench Press", sets: 5, reps: "5", rest: 180)])
        var after = before
        after.exercises[0].sets = 3   // user "lighter today, only 3 sets"
        let diff = WorkoutDiff(before: before, after: after,
                               changes: [WorkoutChange(op: "adjust", exerciseName: "Bench Press", sets: 3)],
                               reasoning: nil)

        XCTAssertTrue(store.applyWorkoutDiffToActiveSession(diff))
        let updated = store.active!.exercises[0]

        XCTAssertEqual(updated.targetSets, 3, "Target updated")
        XCTAssertEqual(updated.sets.filter(\.done).count, 4, "All 4 logged sets are preserved")
        XCTAssertEqual(updated.sets.first?.weight, "135")
    }

    func testAdjustPadsEmptySetsWhenTargetGrows() {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(
            templateId: "gen-test", name: "Push Day", category: "Generated", startTime: Date(),
            exercises: [loggedExercise("gex-ex-0", "Bench Press", target: 3, doneCount: 0)],
            feel: nil, note: nil
        ))

        let before = workout([gex("ex-0", 11, "Bench Press", sets: 3, reps: "5", rest: 180)])
        var after = before
        after.exercises[0].sets = 5
        let diff = WorkoutDiff(before: before, after: after, changes: [], reasoning: nil)

        store.applyWorkoutDiffToActiveSession(diff)
        let updated = store.active!.exercises[0]
        XCTAssertEqual(updated.sets.count, 5)
        XCTAssertTrue(updated.sets.allSatisfy { !$0.done }, "New rows are empty + undone")
    }

    // MARK: - Swap: new exercise gets fresh empty sets

    func testSwapInsertsFreshLoggedExerciseForNewName() {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(
            templateId: "gen-test", name: "Push Day", category: "Generated", startTime: Date(),
            exercises: [
                loggedExercise("gex-ex-0", "Bench Press", target: 5, doneCount: 0),
                loggedExercise("gex-ex-1", "Overhead Press", target: 4, doneCount: 0),
            ],
            feel: nil, note: nil
        ))

        let before = workout([
            gex("ex-0", 11, "Bench Press", sets: 5, reps: "5", rest: 180),
            gex("ex-1", 12, "Overhead Press", sets: 4, reps: "8", rest: 120),
        ])
        var after = before
        after.exercises[0] = gex("ex-0", 0, "Floor Press", sets: 5, reps: "5", rest: 180)
        let diff = WorkoutDiff(before: before, after: after, changes: [], reasoning: nil)

        store.applyWorkoutDiffToActiveSession(diff)
        let exs = store.active!.exercises
        XCTAssertEqual(exs.count, 2)
        XCTAssertEqual(exs[0].name, "Floor Press")
        XCTAssertEqual(exs[0].sets.count, 5)
        XCTAssertTrue(exs[0].sets.allSatisfy { !$0.done })
    }

    // MARK: - Removed exercise with done work is carried forward (lossless)

    func testRemovedExerciseWithLoggedWorkIsCarriedForward() {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(
            templateId: "gen-test", name: "Push Day", category: "Generated", startTime: Date(),
            exercises: [
                loggedExercise("gex-ex-0", "Bench Press", target: 5, doneCount: 3),  // user logged work
                loggedExercise("gex-ex-1", "Overhead Press", target: 4, doneCount: 0)
            ],
            feel: nil, note: nil
        ))

        let before = workout([
            gex("ex-0", 11, "Bench Press", sets: 5, reps: "5", rest: 180),
            gex("ex-1", 12, "Overhead Press", sets: 4, reps: "8", rest: 120),
        ])
        // Coach removed Bench from the workout entirely. User had 3 done sets — must persist.
        let after = workout([gex("ex-1", 12, "Overhead Press", sets: 4, reps: "8", rest: 120)])
        let diff = WorkoutDiff(before: before, after: after, changes: [], reasoning: nil)

        store.applyWorkoutDiffToActiveSession(diff)
        let exs = store.active!.exercises
        XCTAssertEqual(exs.count, 2, "Bench survives because user had logged sets there")
        XCTAssertTrue(exs.contains { $0.name == "Bench Press" })
    }

    func testRemovedExerciseWithoutLoggedWorkIsDropped() {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(
            templateId: "gen-test", name: "Push Day", category: "Generated", startTime: Date(),
            exercises: [
                loggedExercise("gex-ex-0", "Bench Press", target: 5, doneCount: 0),    // no logged work
                loggedExercise("gex-ex-1", "Overhead Press", target: 4, doneCount: 0),
            ],
            feel: nil, note: nil
        ))

        let before = workout([
            gex("ex-0", 11, "Bench Press", sets: 5, reps: "5", rest: 180),
            gex("ex-1", 12, "Overhead Press", sets: 4, reps: "8", rest: 120),
        ])
        let after = workout([gex("ex-1", 12, "Overhead Press", sets: 4, reps: "8", rest: 120)])
        let diff = WorkoutDiff(before: before, after: after, changes: [], reasoning: nil)

        store.applyWorkoutDiffToActiveSession(diff)
        let exs = store.active!.exercises
        XCTAssertEqual(exs.count, 1)
        XCTAssertEqual(exs[0].name, "Overhead Press", "Bench dropped — no work to preserve")
    }

    // MARK: - Title sync

    func testSessionNameMirrorsDiffAfterTitle() {
        let store = SessionStore(defaults: defaults())
        store.saveActive(ActiveSession(
            templateId: "gen-test", name: "Push Day", category: "Generated", startTime: Date(),
            exercises: [loggedExercise("gex-ex-0", "Bench Press", target: 3, doneCount: 0)],
            feel: nil, note: nil
        ))
        let before = workout([gex("ex-0", 11, "Bench Press", sets: 3, reps: "5", rest: 180)], title: "Push Day")
        let after  = workout([gex("ex-0", 11, "Bench Press", sets: 3, reps: "5", rest: 180)], title: "Lighter Push")
        let diff = WorkoutDiff(before: before, after: after, changes: [], reasoning: nil)

        store.applyWorkoutDiffToActiveSession(diff)
        XCTAssertEqual(store.active?.name, "Lighter Push")
    }

    // MARK: - No active session

    func testReturnsFalseWhenNoActiveSession() {
        let store = SessionStore(defaults: defaults())
        let w = workout([gex("ex-0", 11, "Bench", sets: 3, reps: "5", rest: 180)])
        let diff = WorkoutDiff(before: w, after: w, changes: [], reasoning: nil)
        XCTAssertFalse(store.applyWorkoutDiffToActiveSession(diff))
    }
}
