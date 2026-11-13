import XCTest
@testable import PhaseTraining

/// The VOLUME stat on the Complete screen.
final class WorkingVolumeTests: XCTestCase {

    private func ex(_ unit: String, _ sets: [LoggedSet]) -> LoggedExercise {
        LoggedExercise(id: UUID().uuidString, name: "Lift", type: nil, unit: unit,
                       targetSets: sets.count, targetReps: 5, rest: 90, sets: sets,
                       prevSets: [], rpe: nil, tempo: nil, supersetGroup: nil)
    }

    private func session(_ exercises: [LoggedExercise]) -> ActiveSession {
        ActiveSession(templateId: "t", name: "T", category: "c", startTime: Date(),
                      exercises: exercises, feel: nil, note: nil)
    }

    func test_countsDoneWorkingSetsOnly() {
        let s = session([ex("lbs", [
            LoggedSet(num: 1, weight: "95", reps: "5", rpe: "", done: true, setType: .warmup),
            LoggedSet(num: 2, weight: "135", reps: "5", rpe: "", done: true),
            LoggedSet(num: 3, weight: "135", reps: "5", rpe: "", done: true),
            LoggedSet(num: 4, weight: "135", reps: "5", rpe: "", done: false),
        ])])
        XCTAssertEqual(s.workingVolume(usesImperial: true), 1350)
    }

    func test_dropAndFailureSetsAddVolume_warmupDoesNot() {
        let s = session([ex("lbs", [
            LoggedSet(num: 1, weight: "95", reps: "5", rpe: "", done: true, setType: .warmup),
            LoggedSet(num: 2, weight: "135", reps: "5", rpe: "", done: true),
            LoggedSet(num: 3, weight: "100", reps: "10", rpe: "", done: true, setType: .drop),
            LoggedSet(num: 4, weight: "135", reps: "4", rpe: "", done: true, setType: .failure),
        ])])
        let expected: Double = 675 + 1000 + 540
        XCTAssertEqual(s.workingVolume(usesImperial: true), expected)
    }

    func test_bodyweightCountsAddedLoadOnly() {
        let s = session([ex(LoggedExercise.bodyweightUnit, [
            LoggedSet(num: 1, weight: "", reps: "10", rpe: "", done: true),
            LoggedSet(num: 2, weight: "+25", reps: "8", rpe: "", done: true),
        ])])
        XCTAssertEqual(s.workingVolume(usesImperial: true), 200)
    }

    func test_convertsToTheLiftersUnit() {
        let kgRow = session([ex("kg", [LoggedSet(num: 1, weight: "100", reps: "1", rpe: "", done: true)])])
        XCTAssertEqual(kgRow.workingVolume(usesImperial: true), 100 / ImportUnitCorrection.kgPerLb, accuracy: 0.01)
        let lbRow = session([ex("lbs", [LoggedSet(num: 1, weight: "100", reps: "1", rpe: "", done: true)])])
        XCTAssertEqual(lbRow.workingVolume(usesImperial: false), 100 * ImportUnitCorrection.kgPerLb, accuracy: 0.01)
    }
}
