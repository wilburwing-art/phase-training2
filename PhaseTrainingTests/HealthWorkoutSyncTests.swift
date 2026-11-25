// HealthWorkoutSyncTests: the kcal labels on the Health sync screen's
// LAST 28 DAYS list (backlog 2026-11c 6.8), and imported workouts merged
// into the History list (6.11).

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

    func test_historyMerge_holdsOneRowPerImportedWorkoutWithItsKcal() {
        let now = Date()
        let ride = ImportedWorkout(id: "HK-ride", source: .healthKit, kind: .cardio,
                                   startTime: now.addingTimeInterval(-3_600), duration: 42 * 60, energyKcal: 349.6)
        let row = ImportedWorkout(id: "fitbodCSV:cardio:1:Row", source: .fitbodCSV, kind: .cardio,
                                  startTime: now.addingTimeInterval(-3 * 86_400), duration: 20 * 60, energyKcal: nil)
        let lift = SavedSession(templateId: "t", name: "Upper", category: "strength",
                                startTime: now.addingTimeInterval(-86_400), exercises: [],
                                feel: nil, note: nil, endTime: now.addingTimeInterval(-86_400 + 2_400),
                                duration: 2_400)

        let entries = HistoryEntries.merge(sessions: [lift], workouts: [row, ride])

        XCTAssertEqual(entries.map(\.id), ["workout-HK-ride", "session-\(lift.id)", "workout-fitbodCSV:cardio:1:Row"])
        let workouts = entries.compactMap { e -> ImportedWorkout? in
            if case .workout(let w) = e { return w } else { return nil }
        }
        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(ImportedWorkoutEnergy.detail(workouts[0]), "Cardio · 42 min · 350 kcal")
        XCTAssertEqual(HistoryEntries.title(workouts[0]), "Apple Health workout")
        XCTAssertEqual(ImportedWorkoutEnergy.detail(workouts[1]), "Cardio · 20 min")
    }

    func test_historyImportedWorkouts_readsEveryStoredRow_andDisplaySessionsStaySetsOnly() {
        let db = UserDatabase(path: ":memory:")
        let old = ImportedWorkout(id: "HK-old", source: .healthKit, kind: .cardio,
                                  startTime: Date().addingTimeInterval(-400 * 86_400), duration: 1_800, energyKcal: 200)
        db.insertImportedWorkouts([old, workout(kcal: 300)])
        let suite = "HealthWorkoutSyncTests-\(UUID().uuidString)"
        let store = SessionStore(defaults: UserDefaults(suiteName: suite)!, userDB: db)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.historyImportedWorkouts().count, 2)
        XCTAssertTrue(store.displaySessions(usesImperial: true).isEmpty)
    }
}
