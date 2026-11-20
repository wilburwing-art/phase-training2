import XCTest
@testable import PhaseTraining

/// `WorkoutGenerator.represcribe` branches the store-level tests in
/// `PlanStoreSeamsTests` do not reach: a row whose exercise id is missing
/// from coach.db, and the summary and time estimate a full refresh rewrites.
final class WorkoutGeneratorRepresribeTests: XCTestCase {

    private let danglingId = 9_999_999

    private func memory() -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        return m
    }

    private func row(id: String, exerciseId: Int, name: String,
                     sets: Int = 3, reps: String = "8", rest: Int = 90,
                     notes: String? = nil, superset: Int? = nil) -> GeneratedExercise {
        GeneratedExercise(id: id, exerciseId: exerciseId, name: name,
                          pattern: "horizontal-push", isCompound: false,
                          sets: sets, reps: reps, restSeconds: rest,
                          notes: notes, supersetGroup: superset)
    }

    private func workout(_ rows: [GeneratedExercise]) -> GeneratedWorkout {
        GeneratedWorkout(title: "Mine", summary: "stored summary", exercises: rows,
                         estimatedMinutes: 999, provenance: "custom")
    }

    private func run(_ w: GeneratedWorkout, _ mode: PrescriptionRefreshMode) -> GeneratedWorkout {
        let m = memory()
        return WorkoutGenerator.represcribe(
            workout: w, mode: mode, focus: .push, memory: m,
            profile: DemographicProfile.from(m), context: .empty)
    }

    private func realExercise() throws -> Exercise {
        let pool = CoachDatabase.shared.exercises(matchingPattern: "horizontal-push")
        return try XCTUnwrap(pool.first, "coach.db must have horizontal-push exercises")
    }

    // MARK: - Dangling id

    func testDanglingIdRowIsKeptUntouchedInBothModes() {
        XCTAssertNil(CoachDatabase.shared.exercise(id: danglingId))
        let stored = row(id: "cex-x", exerciseId: danglingId, name: "Gone Lift",
                         sets: 5, reps: "3", rest: 180, notes: "my cue", superset: 2)
        for mode in [PrescriptionRefreshMode.fullRefresh, .weightsOnly] {
            let out = run(workout([stored]), mode)
            XCTAssertEqual(out.exercises, [stored], "\(mode)")
        }
    }

    func testDanglingRowNextToRealRowKeepsItsPlace() throws {
        let ex = try realExercise()
        let gone = row(id: "cex-0", exerciseId: danglingId, name: "Gone Lift")
        let real = row(id: "cex-1", exerciseId: ex.id, name: "My Name For It",
                       notes: "elbows in", superset: 1)
        let out = run(workout([gone, real]), .fullRefresh)
        XCTAssertEqual(out.exercises.map(\.id), ["cex-0", "cex-1"])
        XCTAssertEqual(out.exercises[0], gone)
        XCTAssertEqual(out.exercises[1].name, "My Name For It")
        XCTAssertEqual(out.exercises[1].supersetGroup, 1)
        XCTAssertEqual(out.exercises[1].exerciseId, ex.id)
        XCTAssertTrue(out.exercises[1].notes?.hasPrefix("elbows in") == true,
                      "user note must lead: \(out.exercises[1].notes ?? "nil")")
    }

    // MARK: - Summary recompute

    /// A dangling row counts sets × (45 s + rest) + 30 s toward the estimate.
    /// 10 × (45 + 300) + 30 = 3480 s = 58 min.
    func testFullRefreshRecomputesSummaryFromDanglingRowTime() {
        let stored = row(id: "cex-x", exerciseId: danglingId, name: "Gone Lift",
                         sets: 10, rest: 300)
        let out = run(workout([stored]), .fullRefresh)
        XCTAssertEqual(out.estimatedMinutes, 58)
        XCTAssertEqual(out.summary, "1 movement · ~58 min")
    }

    func testFullRefreshEstimateHasFifteenMinuteFloor() {
        // 3 × (45 + 90) + 30 = 435 s = 7 min, floored to 15.
        let stored = row(id: "cex-x", exerciseId: danglingId, name: "Gone Lift")
        let out = run(workout([stored]), .fullRefresh)
        XCTAssertEqual(out.estimatedMinutes, 15)
        XCTAssertEqual(out.summary, "1 movement · ~15 min")
    }

    func testFullRefreshSummaryPluralisesMovements() throws {
        let ex = try realExercise()
        let out = run(workout([row(id: "a", exerciseId: ex.id, name: "A"),
                               row(id: "b", exerciseId: danglingId, name: "B")]),
                      .fullRefresh)
        XCTAssertNotEqual(out.estimatedMinutes, 999)
        XCTAssertGreaterThanOrEqual(out.estimatedMinutes, 15)
        XCTAssertEqual(out.summary, "2 movements · ~\(out.estimatedMinutes) min")
    }

    func testWeightsOnlyLeavesSummaryAndEstimateAlone() throws {
        let ex = try realExercise()
        let stored = row(id: "a", exerciseId: ex.id, name: "A", sets: 4, reps: "8-12", rest: 75)
        let out = run(workout([stored]), .weightsOnly)
        XCTAssertEqual(out.summary, "stored summary")
        XCTAssertEqual(out.estimatedMinutes, 999)
        XCTAssertEqual(out.exercises[0].sets, 4)
        XCTAssertEqual(out.exercises[0].reps, "8-12")
        XCTAssertEqual(out.exercises[0].restSeconds, 75)
    }
}
