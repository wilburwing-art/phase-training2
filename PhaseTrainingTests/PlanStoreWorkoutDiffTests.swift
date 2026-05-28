// PlanStoreWorkoutDiffTests.swift — pins behavior on the chat edit → plan
// apply path. Two invariants:
//   1. applying a workout diff STAMPS the day's refinedByLLMAt so the
//      background refinement pass SKIPS the edited workout (the LLM filter
//      at PlanStore+LLMRefinement.swift excludes refined days). The earlier
//      build-99 code cleared the flag + refired refinement, which rerolled
//      the just-applied edit from scratch ~5-10s later — a silent revert.
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

    // MARK: - refinedByLLMAt stamping (refinement must skip applied edits)

    func test_applyWorkoutDiff_marksRefinedSoRefinementSkipsTheDay() {
        // An applied workout diff is the user's final word for that day.
        // After it lands, refinedByLLMAt must be NON-nil so the background
        // refinement candidate filter excludes the day — otherwise the LLM
        // would regenerate it from scratch (refineSingleDay never reads the
        // edited exercises) and silently revert the swap a few seconds later.
        let defaults = freshDefaults("PlanStoreWorkoutDiffTests.marks_refined")
        let store = PlanStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        // Start from an UN-refined workout — this is the case the old code
        // got wrong (it left refinedByLLMAt nil → eligible for reroll).
        let baseline = fixtureWorkout(refinedAt: nil)
        store.setPlan(fixturePlan(today: today, workout: baseline))

        var after = baseline
        after.exercises[0] = GeneratedExercise(
            id: "ex-0", exerciseId: 0, name: "Floor Press",
            pattern: "horizontal_push", isCompound: true,
            sets: 5, reps: "5", restSeconds: 180, notes: nil
        )
        let diff = WorkoutDiff(
            before: baseline, after: after,
            changes: [WorkoutChange(op: "swap", fromName: "Bench Press",
                                    toName: "Floor Press")],
            reasoning: "Shoulder-friendlier."
        )

        let ok = store.applyWorkoutDiff(diff, on: today)
        XCTAssertTrue(ok)
        let applied = store.plan?.days[0].generatedWorkout
        XCTAssertNotNil(applied?.refinedByLLMAt,
                        "An applied edit must be stamped so background refinement skips it (no silent reroll)")
        XCTAssertEqual(applied?.exercises[0].name, "Floor Press",
                       "The applied swap must survive on the plan")

        // The stamped day must NOT be a refinement candidate.
        if let plan = store.plan {
            let candidateIdxs = store.refinementCandidates(in: plan).map(\.index)
            XCTAssertFalse(candidateIdxs.contains(0),
                           "A just-edited day must be excluded from LLM refinement candidates")
        }
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

    // MARK: - refinementCandidates exclusions

    func test_refinementCandidates_includesPlainUnrefinedLiftDay() {
        let defaults = freshDefaults("PlanStoreWorkoutDiffTests.cand_includes")
        let store = PlanStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        store.setPlan(fixturePlan(today: today, workout: fixtureWorkout(refinedAt: nil)))
        XCTAssertEqual(store.refinementCandidates(in: store.plan!).map(\.index), [0],
                       "A lift day with an unrefined workout and no override is a refinement candidate")
    }

    func test_refinementCandidates_excludesAlreadyRefinedDay() {
        let defaults = freshDefaults("PlanStoreWorkoutDiffTests.cand_refined")
        let store = PlanStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        store.setPlan(fixturePlan(today: today, workout: fixtureWorkout(refinedAt: Date())))
        XCTAssertTrue(store.refinementCandidates(in: store.plan!).isEmpty,
                      "An already-refined day must not be re-refined")
    }

    func test_refinementCandidates_excludesCustomRoutineOverrideDay() {
        // The Week-tab "Override workout" bug: a custom-routine override day
        // carries a nil refinedByLLMAt (composeWorkout(fromCustom:) doesn't
        // stamp it), so without the override guard it would be picked as a
        // candidate and rerolled — reverting the user's pick 5-10s later.
        let defaults = freshDefaults("PlanStoreWorkoutDiffTests.cand_override")
        let store = PlanStore(defaults: defaults)
        let today = Calendar.current.startOfDay(for: Date())
        store.setPlan(fixturePlan(today: today, workout: fixtureWorkout(refinedAt: nil)))

        // Pre-condition: without an override, the day IS a candidate.
        XCTAssertEqual(store.refinementCandidates(in: store.plan!).map(\.index), [0])

        // Schedule a custom-routine override on that day (what the Week-tab
        // "Override workout" → scheduleOverride path writes).
        store.overrides.customRoutineByDate[today] = "custom-123"

        XCTAssertTrue(store.refinementCandidates(in: store.plan!).isEmpty,
                      "A day with a custom-routine override must be excluded from refinement so the override survives")
    }
}
