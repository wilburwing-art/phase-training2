import XCTest
@testable import PhaseTraining

/// Bird-dog weight-default behaviour: reps-only movements log as bodyweight
/// so the LogScreen can hide their weight input (the user stops tapping 0
/// into every set). These pin the `EquipmentCategory` → unit mapping and the
/// LoggedExercise helpers the log row reads.
final class LoggedExerciseBodyweightTests: XCTestCase {

    // MARK: - unit(for:)

    func test_unit_repsOnly_collapsesToBodyweight() {
        XCTAssertEqual(LoggedExercise.unit(for: .repsOnly), LoggedExercise.bodyweightUnit)
    }

    func test_unit_loadedCategories_logInLbs() {
        for category in [EquipmentCategory.barbell, .dumbbell, .machineOther,
                         .weightedBodyweight, .assistedBodyweight, .cardio, .duration] {
            XCTAssertEqual(LoggedExercise.unit(for: category), "lbs",
                           "\(category) should log in lbs, not bodyweight")
        }
    }

    func test_unit_unknownCategory_defaultsToLbs() {
        XCTAssertEqual(LoggedExercise.unit(for: nil), "lbs")
    }

    // MARK: - isBodyweight / displayUnit

    func test_isBodyweight_trueOnlyForSentinelUnit() {
        XCTAssertTrue(make(unit: LoggedExercise.bodyweightUnit).isBodyweight)
        XCTAssertFalse(make(unit: "lbs").isBodyweight)
        XCTAssertFalse(make(unit: "").isBodyweight)
    }

    func test_displayUnit_mapsBodyweightSentinelToLbs() {
        // A weight vest / plate logged on a bodyweight exercise should read in
        // lbs everywhere a real number is shown — never "185 bw".
        XCTAssertEqual(make(unit: LoggedExercise.bodyweightUnit).displayUnit, "lbs")
        XCTAssertEqual(make(unit: "lbs").displayUnit, "lbs")
    }

    // MARK: - Helpers

    private func make(unit: String) -> LoggedExercise {
        LoggedExercise(
            id: "ex", name: "Bird Dog", type: nil, unit: unit,
            targetSets: 3, targetReps: 10, rest: 45,
            sets: [], prevSets: []
        )
    }
}
