// SessionExerciseHintsPersistenceTests — user.db v7: LoggedExercise.rpe,
// tempo and supersetGroup reach SQLite and come back, and a v6 file's
// existing rows load with all three nil after the upgrade.

import XCTest
import SQLite3
@testable import PhaseTraining

final class SessionExerciseHintsPersistenceTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "hints-test-\(UUID().uuidString).db"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    private func session(start: Date, exercises: [LoggedExercise]) -> SavedSession {
        SavedSession(templateId: "t", name: "Upper", category: "lift", startTime: start,
                     exercises: exercises, feel: nil, note: nil,
                     endTime: start.addingTimeInterval(1800), duration: 1800)
    }

    private func exercise(_ id: String, rpe: String?, tempo: String?, group: Int?) -> LoggedExercise {
        LoggedExercise(id: id, name: "Bench \(id)", type: "Barbell", unit: "lbs",
                       targetSets: 1, targetReps: 5, rest: 120,
                       sets: [LoggedSet(num: 1, weight: "135", reps: "5", rpe: "", done: true)],
                       prevSets: [], rpe: rpe, tempo: tempo, supersetGroup: group)
    }

    func test_hints_roundTripThroughSave() throws {
        let db = UserDatabase(path: path)
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        XCTAssertTrue(db.saveSession(session(start: start, exercises: [
            exercise("a", rpe: "RPE 8", tempo: "3-1-1-0", group: 1),
            exercise("b", rpe: nil, tempo: nil, group: nil),
        ])))

        let loaded = try XCTUnwrap(db.listSavedSessions().first { $0.startTime == start })
        XCTAssertEqual(loaded.exercises.map(\.rpe), ["RPE 8", nil])
        XCTAssertEqual(loaded.exercises.map(\.tempo), ["3-1-1-0", nil])
        XCTAssertEqual(loaded.exercises.map(\.supersetGroup), [1, nil])

        // The by-name path reads through loadOneExerciseLocked.
        let byName = try XCTUnwrap(db.mostRecentExerciseByName("Bench a"))
        XCTAssertEqual(byName.rpe, "RPE 8")
        XCTAssertEqual(byName.tempo, "3-1-1-0")
        XCTAssertEqual(byName.supersetGroup, 1)
    }

    func test_v6File_upgrades_andOldRowsLoadWithNilHints() throws {
        let start: Int64 = 1_780_000_000
        do {
            let v = UserDatabase(path: path)
            let db = try XCTUnwrap(v.db)
            for column in ["rpe", "tempo", "superset_group"] {
                XCTAssertEqual(sqlite3_exec(db, "ALTER TABLE session_exercises DROP COLUMN \(column)", nil, nil, nil), SQLITE_OK)
            }
            XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 6", nil, nil, nil), SQLITE_OK)
            // A row written by a v6 build: no hint columns exist yet.
            XCTAssertEqual(sqlite3_exec(db, """
                INSERT INTO sessions(start_time, template_id, name, category, end_time, duration)
                VALUES (\(start), 't', 'Old', 'lift', \(start + 1800), 1800);
                INSERT INTO session_exercises(session_start, position, exercise_template_id, name, type, unit,
                                              target_sets, target_reps, rest, prev_sets_json, note)
                VALUES (\(start), 0, 'sq', 'Back Squat', 'Barbell', 'lbs', 3, 5, 180, '[]', 'seat 4');
                INSERT INTO session_sets(session_start, exercise_position, num, weight, reps, rpe, done, is_warmup, rir)
                VALUES (\(start), 0, 1, '225', '5', '', 1, 0, '2');
                """, nil, nil, nil), SQLITE_OK, "v6 fixture insert failed; check the column lists")
        }

        let reopened = UserDatabase(path: path)
        XCTAssertNil(reopened.unavailableReason)
        let loaded = try XCTUnwrap(reopened.listSavedSessions().first {
            Int64($0.startTime.timeIntervalSince1970) == start
        })
        let ex = try XCTUnwrap(loaded.exercises.first)
        XCTAssertNil(ex.rpe)
        XCTAssertNil(ex.tempo)
        XCTAssertNil(ex.supersetGroup)
        XCTAssertEqual(ex.name, "Back Squat")
        XCTAssertEqual(ex.note, "seat 4")
        XCTAssertEqual(ex.sets.first?.weight, "225")
        XCTAssertEqual(ex.sets.first?.rir, "2")
    }
}
