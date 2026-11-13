import XCTest
@testable import PhaseTraining

final class PickedExerciseCategoryTests: XCTestCase {

    private func custom() -> Exercise {
        UserExercise(id: 3, name: "Zorblax Cable Twist", muscleBucket: nil, notes: nil,
                     createdAt: Date(timeIntervalSince1970: 0)).exercise
    }

    private func catalogExercise(id: Int) -> Exercise {
        Exercise(id: id, name: "Catalog \(id)", slug: "catalog-\(id)", description: nil,
                 instructions: nil, cues: [], difficulty: nil, modality: nil, environment: nil,
                 isCompound: false, isUnilateral: false,
                 defaultSets: nil, defaultReps: nil, defaultRest: nil, defaultDuration: nil,
                 regression: nil, progression: nil,
                 imageURL: nil, thumbnailURL: nil, videoURL: nil, sourceVideoAttribution: nil)
    }

    func test_customExercise_isWeighted() {
        let category = LoggedExercise.equipmentCategory(forPicked: custom())
        XCTAssertNotNil(category)
        XCTAssertNotEqual(category, .repsOnly)
        XCTAssertEqual(LoggedExercise.unit(for: category), "lbs")
    }

    func test_catalogExercises_matchTheCatalogLookup() throws {
        let catalog = CoachDatabase.shared
        let ids = Set(1...600)
        let all = catalog.equipmentCategory(forExerciseIds: ids)
        let repsOnlyId = try XCTUnwrap(all.first { $0.value == .repsOnly }?.key,
                                       "catalog has no reps-only exercise")
        let loadedId = try XCTUnwrap(all.first { $0.value != .repsOnly }?.key,
                                     "catalog has no loaded exercise")
        for id in [repsOnlyId, loadedId] {
            XCTAssertEqual(LoggedExercise.equipmentCategory(forPicked: catalogExercise(id: id)),
                           catalog.equipmentCategory(forExerciseIds: [id])[id], "id \(id)")
        }
        XCTAssertEqual(LoggedExercise.unit(for: LoggedExercise.equipmentCategory(forPicked: catalogExercise(id: repsOnlyId))),
                       LoggedExercise.bodyweightUnit)
    }

    func test_customRoutineTemplate_logsACustomExerciseInLbs() {
        let routine = CustomRoutine(
            id: "r", name: "R",
            exercises: [CustomRoutineExercise(id: "e", exerciseId: -3, name: "Zorblax Cable Twist",
                                              position: 1, sets: nil, reps: nil, rest: nil,
                                              notes: nil, supersetGroup: nil)],
            createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(routine.toWorkoutTemplate().exercises.first?.unit, "lbs")
    }
}
