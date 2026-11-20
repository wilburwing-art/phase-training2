import XCTest
@testable import PhaseTraining

final class AuthoredWorkoutTemplateTests: XCTestCase {

    // MARK: - Helpers

    private func row(slug: String = "test-slug", name: String = "Test Routine",
                     goal: String? = "strength", phase: String? = "base") -> BundledRoutineRow {
        BundledRoutineRow(id: 1, name: name, slug: slug, description: nil, goal: goal,
                          difficulty: nil, phase: phase, durationMinutes: nil,
                          environment: nil, exerciseCount: 0, setCount: 0)
    }

    private func rex(_ id: Int = 1, sets: Int? = nil, reps: String? = nil, rest: String? = nil,
                     superset: Int? = nil) -> RoutineExercise {
        RoutineExercise(id: id, exerciseId: id, name: "Ex \(id)", position: id,
                        sets: sets, reps: reps, rest: rest, supersetGroup: superset)
    }

    private func first(_ e: RoutineExercise) -> ExerciseTemplate {
        row().toWorkoutTemplate(with: [e]).exercises[0]
    }

    private func generated() -> GeneratedWorkout {
        let gex = GeneratedExercise(id: "g1", exerciseId: 1, name: "Bench", isCompound: true,
                                    sets: 3, reps: "5", restSeconds: 120)
        return GeneratedWorkout(title: "t", summary: "", exercises: [gex],
                                estimatedMinutes: 30, provenance: "")
    }

    private func day(routineId: Int?, generated: GeneratedWorkout?) -> DayPlan {
        DayPlan(date: Date(), kind: .lift, title: "Day", routineId: routineId,
                generatedWorkout: generated)
    }

    // MARK: - toWorkoutTemplate

    func test_numericRepsRangeUsesLeadingNumberAndDropsLabel() {
        let t = first(rex(reps: "8-12"))
        XCTAssertEqual(t.targetReps, 8)
        XCTAssertNil(t.repsLabel)
    }

    func test_nonNumericRepsKeepsLabel() {
        let t = first(rex(reps: "30-60 sec"))
        XCTAssertEqual(t.targetReps, 30)
        XCTAssertEqual(t.repsLabel, "30-60 sec")
    }

    func test_nilRepsDefaultsTo8() {
        XCTAssertEqual(first(rex(reps: nil)).targetReps, 8)
    }

    func test_nonNumericRepsDefaultsTo8() {
        XCTAssertEqual(first(rex(reps: "AMRAP")).targetReps, 8)
    }

    func test_nilSetsDefaultsTo3() {
        XCTAssertEqual(first(rex(sets: nil)).targetSets, 3)
    }

    func test_explicitSetsCarried() {
        XCTAssertEqual(first(rex(sets: 5)).targetSets, 5)
    }

    func test_nilRest_defaultsTo90() {
        XCTAssertEqual(first(rex(rest: nil)).rest, 90)
    }

    func test_restParsing() {
        XCTAssertEqual(first(rex(rest: "2 min")).rest, 120)
        XCTAssertEqual(first(rex(rest: "45s")).rest, 45)
        XCTAssertEqual(first(rex(rest: "1.5 min")).rest, 90)
    }

    func test_supersetGroupCarriedPerExercise() {
        let t = row().toWorkoutTemplate(with: [rex(1, superset: 2), rex(2, superset: nil)])
        XCTAssertEqual(t.exercises[0].supersetGroup, 2)
        XCTAssertNil(t.exercises[1].supersetGroup)
    }

    func test_templateIdentityAndCategory() {
        let t = row(slug: "my-slug", name: "My Name", goal: "strength", phase: "base")
            .toWorkoutTemplate(with: [])
        XCTAssertEqual(t.id, "my-slug")
        XCTAssertEqual(t.name, "My Name")
        XCTAssertEqual(t.category, "strength · base")
    }

    func test_categoryIsGoalAloneWhenPhaseNil() {
        let t = row(goal: "strength", phase: nil).toWorkoutTemplate(with: [])
        XCTAssertEqual(t.category, "strength")
    }

    func test_exerciseIdsPrefixedAndOrderPreserved() {
        let t = row().toWorkoutTemplate(with: [rex(7), rex(3), rex(9)])
        XCTAssertEqual(t.exercises.map(\.id), ["rex-7", "rex-3", "rex-9"])
    }

    // MARK: - DayPlan.workoutTemplate

    func test_generatedWorkoutProducesStableTemplateId() {
        let g = generated()
        let t = day(routineId: nil, generated: g).workoutTemplate
        XCTAssertEqual(t?.id, g.stableTemplateId)
    }

    func test_routineIdFallbackUsesBundledRoutine() throws {
        let slug = try XCTUnwrap(CoachDatabase.shared.listRoutines().first(where: { $0.id == 1 })?.slug)
        let t = try XCTUnwrap(day(routineId: 1, generated: nil).workoutTemplate)
        XCTAssertEqual(t.id, slug)
        XCTAssertFalse(t.exercises.isEmpty)
        XCTAssertEqual(t.exercises.count, CoachDatabase.shared.exercises(forRoutineId: 1).count)
    }

    func test_noSourcesReturnsNil() {
        XCTAssertNil(day(routineId: nil, generated: nil).workoutTemplate)
    }

    func test_unknownRoutineIdReturnsNil() {
        XCTAssertNil(day(routineId: 999_999, generated: nil).workoutTemplate)
    }

    func test_generatedWorkoutWinsOverRoutineId() {
        let g = generated()
        let t = day(routineId: 1, generated: g).workoutTemplate
        XCTAssertEqual(t?.id, g.stableTemplateId)
    }
}
