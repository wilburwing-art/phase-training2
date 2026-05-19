import XCTest
@testable import PhaseTraining

/// Regression guard for the singleton-read serialization rule on
/// `CoachDatabase`. Until build 62 the database singleton's reads were
/// not serialized at the Swift layer — under xcodebuild's parallel test
/// runner, suites that read concurrently (Planner / WorkoutGenerator /
/// DemographicProfile) intermittently saw "0 exercises returned" and
/// failed. The `withLock` wrapper on every public method fixes that;
/// this test fires N concurrent reads and asserts every result is
/// non-empty + matches a serial reference, which trips immediately if a
/// future change drops the lock from any public method.
final class CoachDatabaseConcurrencyTests: XCTestCase {

    func test_concurrentReads_areStable() throws {
        // Skip when the test bundle can't load the coach.db — keeps the
        // suite green in environments without the bundled resource.
        guard CoachDatabase.shared.isOpen else {
            throw XCTSkip("coach.db not available in this test bundle")
        }

        // Serial reference values.
        let refExercises = CoachDatabase.shared.listExercises().count
        let refRoutines  = CoachDatabase.shared.listRoutines().count
        let refInjuries  = CoachDatabase.shared.listInjuries().count
        XCTAssertGreaterThan(refExercises, 100, "sanity — coach.db has hundreds of exercises")
        XCTAssertGreaterThan(refRoutines, 20, "sanity — coach.db has dozens of routines")

        // Fire concurrent reads from a wide queue. If the lock is dropped
        // anywhere, one or more of these will return 0.
        let iterations = 50
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.coach.concurrent",
                                  attributes: .concurrent)
        let lock = NSLock()
        var exerciseCounts: [Int] = []
        var routineCounts: [Int] = []
        var injuryCounts: [Int] = []

        for _ in 0..<iterations {
            group.enter()
            queue.async {
                let e = CoachDatabase.shared.listExercises().count
                let r = CoachDatabase.shared.listRoutines().count
                let i = CoachDatabase.shared.listInjuries().count
                lock.lock()
                exerciseCounts.append(e)
                routineCounts.append(r)
                injuryCounts.append(i)
                lock.unlock()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success,
                       "all concurrent reads should complete within 10s")

        // Every concurrent result must equal the serial reference. Any
        // deviation = the lock leaked.
        XCTAssertTrue(exerciseCounts.allSatisfy { $0 == refExercises },
                      "exercise counts under load drifted from serial reference: got \(Set(exerciseCounts))")
        XCTAssertTrue(routineCounts.allSatisfy { $0 == refRoutines },
                      "routine counts drifted: got \(Set(routineCounts))")
        XCTAssertTrue(injuryCounts.allSatisfy { $0 == refInjuries },
                      "injury counts drifted: got \(Set(injuryCounts))")
    }

    /// `adjacentByDifficulty` calls `exercise(id:)` internally — proves the
    /// recursive lock allows re-entry from the same thread. A non-reentrant
    /// lock would deadlock here.
    func test_recursiveLock_allowsSelfCalls() throws {
        guard CoachDatabase.shared.isOpen else {
            throw XCTSkip("coach.db not available in this test bundle")
        }
        // Use any exercise id present in the bundled DB. We don't care about
        // the specific result, only that the call returns without hanging.
        let first = CoachDatabase.shared.listExercises().first
        guard let ex = first else { return XCTFail("expected at least one exercise") }
        let (easier, harder) = CoachDatabase.shared.adjacentByDifficulty(forExerciseId: ex.id)
        // We don't assert on the values — just that the call completed.
        _ = easier
        _ = harder
    }
}
