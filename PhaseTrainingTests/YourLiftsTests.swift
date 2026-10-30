import XCTest
@testable import PhaseTraining

/// The full lifts list shows each lift once, newest first, imported-only
/// lifts included.
final class YourLiftsTests: XCTestCase {

    func test_onePerLift_newestFirst_includingImportedOnly() throws {
        guard let squat = CoachDatabase.shared.exerciseId(forImportName: "Back Squat") else { throw XCTSkip("no Back Squat") }
        let now = Date()
        let old = now.addingTimeInterval(-20 * 86_400)
        let imported = (1...3).map {
            ImportedSet(id: "s\($0)", source: .fitbodCSV, exerciseId: squat, exerciseNameRaw: "Back Squat",
                        performedAt: old, setNum: $0, weight: 100, reps: 5, rir: nil, rpe: nil)
        }
        let start = now.addingTimeInterval(-86_400)
        let native = SavedSession(templateId: "t", name: "Arms", category: "lift", startTime: start,
                                  exercises: [LoggedExercise(id: "c", name: "Cable Curl", type: nil, unit: "lbs",
                                                             targetSets: 1, targetReps: 10, rest: 60,
                                                             sets: [LoggedSet(num: 1, weight: "40", reps: "10", rpe: "", done: true)],
                                                             prevSets: [])],
                                  feel: nil, note: nil, endTime: start.addingTimeInterval(1800), duration: 1800)
        let profile = HistoryProfile.build(sessions: [native], imported: imported, now: now)
        XCTAssertGreaterThan(profile.exercises.count, 2, "the map keys lifts under several names")

        let rows = YourLifts.rows(profile)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.name, "Cable Curl")
        XCTAssertEqual(rows.last?.name, CoachDatabase.shared.exercise(id: squat)?.name)
    }
}
