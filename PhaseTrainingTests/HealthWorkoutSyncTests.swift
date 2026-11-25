// HealthWorkoutSyncTests: the kcal labels on the Health sync screen's
// LAST 28 DAYS list (backlog 2026-11c 6.8).

import XCTest
@testable import PhaseTraining

final class HealthWorkoutSyncTests: XCTestCase {

    private func workout(kind: WorkoutKind = .cardio, minutes: Double = 42, kcal: Double?) -> ImportedWorkout {
        ImportedWorkout(id: UUID().uuidString, source: .healthKit, kind: kind,
                        startTime: Date(), duration: minutes * 60, energyKcal: kcal)
    }

    func test_totalKcal_nilWhenNoRowCarriesEnergy() {
        XCTAssertNil(ImportedWorkoutEnergy.totalKcal([]))
        XCTAssertNil(ImportedWorkoutEnergy.totalKcal([workout(kcal: nil), workout(kcal: nil)]))
    }

    func test_totalKcal_sumsOnlyRowsWithEnergy() {
        let rows = [workout(kcal: 350.4), workout(kcal: nil), workout(kcal: 120.3)]
        XCTAssertEqual(ImportedWorkoutEnergy.totalKcal(rows), 471)
    }

    func test_detail_showsKindMinutesAndKcal() {
        XCTAssertEqual(ImportedWorkoutEnergy.detail(workout(kcal: 349.6)), "Cardio · 42 min · 350 kcal")
    }

    func test_detail_dropsMissingOrZeroParts() {
        XCTAssertEqual(ImportedWorkoutEnergy.detail(workout(kind: .strength, kcal: nil)), "Strength · 42 min")
        XCTAssertEqual(ImportedWorkoutEnergy.detail(workout(kind: .sport, minutes: 0, kcal: 0)), "Sport")
    }

    func test_storedKcalRoundTripsIntoTheLabel() {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedWorkouts([workout(kcal: 300)])
        let back = db.recentImportedWorkouts(within: 28)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(ImportedWorkoutEnergy.totalKcal(back), 300)
    }
}
