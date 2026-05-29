// ImportedWorkoutsDatabaseTests — round-trip insert + fetch on the
// Phase 2 `imported_workouts` table. Uses an in-memory UserDatabase so
// the real Documents/user.db is never touched.

import XCTest
@testable import PhaseTraining

final class ImportedWorkoutsDatabaseTests: XCTestCase {

    func testInsertAndFetchRoundTrip() {
        let db = UserDatabase(path: ":memory:")
        let now = Date()
        let rows = [
            ImportedWorkout(
                id: "HK-UUID-1",
                source: .healthKit,
                kind: .strength,
                startTime: now.addingTimeInterval(-3600),
                duration: 2700,
                energyKcal: 320
            ),
            ImportedWorkout(
                id: "HK-UUID-2",
                source: .healthKit,
                kind: .cardio,
                startTime: now.addingTimeInterval(-7200),
                duration: 1800,
                energyKcal: nil
            )
        ]
        db.insertImportedWorkouts(rows)
        let out = db.recentImportedWorkouts(within: 7)
        XCTAssertEqual(out.count, 2)
        // newest-first ordering
        XCTAssertEqual(out[0].id, "HK-UUID-1")
        XCTAssertEqual(out[1].id, "HK-UUID-2")
        XCTAssertEqual(out[0].kind, .strength)
        XCTAssertEqual(out[1].kind, .cardio)
        XCTAssertEqual(out[0].energyKcal, 320)
        XCTAssertNil(out[1].energyKcal)
    }

    func testWindowExcludesOlderRows() {
        let db = UserDatabase(path: ":memory:")
        let now = Date()
        let recent = ImportedWorkout(id: "R", source: .healthKit, kind: .strength,
                                     startTime: now.addingTimeInterval(-86_400),  // 1d ago
                                     duration: 1800, energyKcal: nil)
        let stale = ImportedWorkout(id: "S", source: .healthKit, kind: .strength,
                                    startTime: now.addingTimeInterval(-30 * 86_400),  // 30d ago
                                    duration: 1800, energyKcal: nil)
        db.insertImportedWorkouts([recent, stale])
        let in7 = db.recentImportedWorkouts(within: 7)
        XCTAssertEqual(in7.map(\.id), ["R"])
        let in60 = db.recentImportedWorkouts(within: 60)
        XCTAssertEqual(in60.count, 2)
    }

    func testInsertIsIdempotentOnId() {
        let db = UserDatabase(path: ":memory:")
        let now = Date()
        let row = ImportedWorkout(id: "X", source: .healthKit, kind: .strength,
                                  startTime: now, duration: 1000, energyKcal: nil)
        db.insertImportedWorkouts([row])
        // Re-import same id with updated duration → replaces, no dup row.
        let updated = ImportedWorkout(id: "X", source: .healthKit, kind: .strength,
                                      startTime: now, duration: 2000, energyKcal: 50)
        db.insertImportedWorkouts([updated])
        let out = db.recentImportedWorkouts(within: 7)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].duration, 2000)
        XCTAssertEqual(out[0].energyKcal, 50)
    }

    func testSummaryEmpty() {
        let db = UserDatabase(path: ":memory:")
        let summary = db.importedWorkoutSummary()
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.count, 0)
        XCTAssertNil(summary?.oldest)
    }

    func testSummaryPopulated() {
        let db = UserDatabase(path: ":memory:")
        let now = Date()
        db.insertImportedWorkouts([
            ImportedWorkout(id: "A", source: .healthKit, kind: .strength,
                            startTime: now.addingTimeInterval(-86_400 * 5),
                            duration: 1800, energyKcal: nil),
            ImportedWorkout(id: "B", source: .healthKit, kind: .cardio,
                            startTime: now.addingTimeInterval(-86_400),
                            duration: 1800, energyKcal: nil)
        ])
        let summary = db.importedWorkoutSummary()
        XCTAssertEqual(summary?.count, 2)
        XCTAssertNotNil(summary?.oldest)
        XCTAssertNotNil(summary?.newest)
        XCTAssertNotNil(summary?.lastImported)
        // newest > oldest
        if let o = summary?.oldest, let n = summary?.newest {
            XCTAssertLessThan(o, n)
        }
    }
}
