// PlanStoreWorkoutDiffTests.swift — pins build-99 behavior on the chat
// edit → plan apply path. Two invariants:
//   1. applying a workout diff clears the day's refinedByLLMAt so the
//      next refinement pass picks the edited workout up (otherwise the
//      LLM filter at PlanStore+LLMRefinement.swift would skip it).
//   2. an unmatched date returns false and leaves the plan untouched.

import XCTest
@testable import PhaseTraining

final class PlanStoreWorkoutDiffTests: XCTestCase {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func fixtureWorkout(refinedAt: Date? = nil) -> GeneratedWorkout {
        var workout = GeneratedWorkout(
            title: "Push Day",
            summary: "test",
            exercises: [
                GeneratedExercise(id: "ex-0", exerciseId: 11, name: "Bench Press",
                                  pattern: "horizontal_push", isCompound: true,
                                  sets: 5, reps: "5", restSeconds: 180, notes: nil),
                GeneratedExercise(id: "ex-1", exerciseId: 12, name: "Overhead Press",
                                  pattern: "vertical_push", isCompound: true,
                                  sets: 4, reps: "8", restSeconds: 120, notes: nil),
            ],
            estimatedMinutes: 45,
            provenance: "test"
        )
        workout.refinedByLLMAt = refinedAt
        return workout
    }

    private func fixturePlan(today: Date, workout: GeneratedWorkout) -> WeekPlan {
        let days = [
            DayPlan(date: today, kind: .lift, title: "Push Day",
                    generatedWorkout: workout)
        ]
        return WeekPlan(days: days, generatedAt: today, inputsHash: "test")
    }

    // MARK: - refinedByLLMAt clearing

    func test_applyWorkoutDiff_clearsRefinedByLLMAt() {
        // A workout already polished by the LLM (refinedByLLMAt = some
        // date) must come back NOT polished after a human edit lands,
        // so the next refinement pass re-personalizes from the edited
        // baseline instead of skipping the day.
        let defaults = freshDefaults("PlanStoreWorkoutDiffTests.clears_refined")
        let store = PlanStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        let preRefined = fixtureWorkout(refinedAt: Date(timeIntervalSinceNow: -3600))
        store.setPlan(fixturePlan(today: today, workout: preRefined))

        var after = preRefined
        after.exercises[0] = GeneratedExercise(
            id: "ex-0", exerciseId: 0, name: "Floor Press",
            pattern: "horizontal_push", isCompound: true,
            sets: 5, reps: "5", restSeconds: 180, notes: nil
        )
        // refinedByLLMAt is preserved by WorkoutDiffBuilder — it walks
        // exercises only — which is exactly the bug this test pins.
        let diff = WorkoutDiff(
            before: preRefined, after: after,
            changes: [WorkoutChange(op: "swap", fromName: "Bench Press",
                                    toName: "Floor Press")],
            reasoning: "Shoulder-friendlier."
        )

        let ok = store.applyWorkoutDiff(diff, on: today)
        XCTAssertTrue(ok)
        XCTAssertNil(store.plan?.days[0].generatedWorkout?.refinedByLLMAt,
                     "Human-applied edits must clear refinedByLLMAt so the next refinement pass doesn't skip this day")
        XCTAssertEqual(store.plan?.days[0].generatedWorkout?.exercises[0].name, "Floor Press")
    }

    func test_applyWorkoutDiff_returnsFalseWhenDateUnmatched() {
        let defaults = freshDefaults("PlanStoreWorkoutDiffTests.unmatched_date")
        let store = PlanStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        let workout = fixtureWorkout(refinedAt: nil)
        store.setPlan(fixturePlan(today: today, workout: workout))

        var after = workout
        after.exercises.removeFirst()
        let diff = WorkoutDiff(
            before: workout, after: after,
            changes: [WorkoutChange(op: "swap", fromName: "Bench Press", toName: "X")],
            reasoning: nil
        )
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let ok = store.applyWorkoutDiff(diff, on: yesterday)
        XCTAssertFalse(ok, "Unknown date must not mutate the plan")
        // Plan is unchanged.
        XCTAssertEqual(store.plan?.days[0].generatedWorkout?.exercises.count, 2)
    }
}
