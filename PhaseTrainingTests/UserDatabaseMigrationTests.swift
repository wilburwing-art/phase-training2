// UserDatabaseMigrationTests — characterize the PRAGMA user_version
// migration runner in UserDatabase.
//
// Two paths matter:
//  1. Fresh install: every migration runs; v10 replaces is_warmup with
//     set_type; v11 adds user_exercises.
//  2. Pre-versioning upgrade: a legacy user.db (user_version = 0, session_sets
//     WITHOUT is_warmup) gets the column via the explicit existence check,
//     then v1 no-ops over the live schema and v10 backfills set_type.
//
// Uses a temp FILE path (not :memory:) so a second raw-SQLite connection can
// inspect what UserDatabase wrote — and so the legacy fixture can be staged
// before UserDatabase ever opens the file.

import XCTest
import SQLite3
@testable import PhaseTraining

final class UserDatabaseMigrationTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "migration-test-\(UUID().uuidString).db"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    // MARK: - Raw-SQLite helpers (second connection, no UserDatabase code)

    private func withRawDB<T>(_ body: (OpaquePointer) -> T) -> T? {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }
        return body(db)
    }

    private func userVersion() -> Int32? {
        withRawDB { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return Int32(-1) }
            return sqlite3_column_int(stmt, 0)
        }
    }

    private func sessionSetsColumns() -> [String] { columns(of: "session_sets") }
    private func sessionsColumns() -> [String] { columns(of: "sessions") }

    private func columns(of table: String) -> [String] {
        withRawDB { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return [] }
            var cols: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 1) { cols.append(String(cString: c)) }
            }
            return cols
        } ?? []
    }

    // MARK: - Fresh install

    func test_freshInstall_stampsLatestVersion_withSetTypeNotWarmup() {
        let db = UserDatabase(path: path)
        XCTAssertTrue(db.isOpen)

        XCTAssertEqual(userVersion(), UserDatabase.latestSchemaVersion,
                       "fresh install must run every migration")
        let cols = sessionSetsColumns()
        XCTAssertTrue(cols.contains("set_type"),
                      "v10 must add set_type; got \(cols)")
        XCTAssertFalse(cols.contains("is_warmup"),
                       "v10 must drop is_warmup; got \(cols)")
        XCTAssertTrue(sessionsColumns().contains("mood"),
                      "v3 must add sessions.mood on a fresh install; got \(sessionsColumns())")
    }

    // MARK: - Pre-versioning upgrade

    func test_legacyDB_withoutWarmupColumn_isUpgradedAndStamped() {
        // Stage a legacy fixture: the pre-is_warmup session_sets shape at
        // user_version 0, with one row, BEFORE UserDatabase opens the file.
        let staged: Bool? = withRawDB { db in
            let stmts = [
                """
                CREATE TABLE session_sets (
                  session_start      INTEGER NOT NULL,
                  exercise_position  INTEGER NOT NULL,
                  num                INTEGER NOT NULL,
                  weight             TEXT NOT NULL,
                  reps               TEXT NOT NULL,
                  rpe                TEXT NOT NULL,
                  done               INTEGER NOT NULL,
                  PRIMARY KEY (session_start, exercise_position, num)
                )
                """,
                "INSERT INTO session_sets VALUES (1, 0, 1, '135', '5', '7', 1)"
            ]
            for sql in stmts where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { return false }
            return true
        }
        XCTAssertEqual(staged, true, "legacy fixture must stage cleanly")
        XCTAssertEqual(userVersion(), 0)
        XCTAssertFalse(sessionSetsColumns().contains("is_warmup"))

        let db = UserDatabase(path: path)
        XCTAssertTrue(db.isOpen)

        XCTAssertEqual(userVersion(), UserDatabase.latestSchemaVersion,
                       "a pre-versioning file must be upgraded through every migration")
        XCTAssertTrue(sessionSetsColumns().contains("set_type"),
                      "legacy session_sets must end with set_type")
        XCTAssertFalse(sessionSetsColumns().contains("is_warmup"),
                       "v10 drops is_warmup after the shim added it")
        XCTAssertTrue(sessionsColumns().contains("mood"),
                      "legacy sessions must gain mood via v3")

        // The pre-existing row survives as a normal set.
        let setType: String? = withRawDB { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT set_type FROM session_sets WHERE session_start = 1", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW,
                  let c = sqlite3_column_text(stmt, 0) else { return "" }
            return String(cString: c)
        }
        XCTAssertEqual(setType, "normal")
    }

    // MARK: - v10 backfill

    func test_v9File_backfillsWarmupIntoSetType() throws {
        let start: Int64 = 1_780_000_000
        do {
            let v = UserDatabase(path: path)
            let db = try XCTUnwrap(v.db)
            XCTAssertEqual(sqlite3_exec(db, "ALTER TABLE session_sets DROP COLUMN set_type", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, "ALTER TABLE session_sets ADD COLUMN is_warmup INTEGER NOT NULL DEFAULT 0", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 9", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, """
                INSERT INTO sessions(start_time, template_id, name, category, end_time, duration)
                VALUES (\(start), 't', 'Old', 'lift', \(start + 1800), 1800);
                INSERT INTO session_exercises(session_start, position, exercise_template_id, name, type, unit,
                                              target_sets, target_reps, rest, prev_sets_json)
                VALUES (\(start), 0, 'sq', 'Back Squat', 'Barbell', 'lbs', 2, 5, 180, '[]');
                INSERT INTO session_sets(session_start, exercise_position, num, weight, reps, rpe, done, is_warmup, rir)
                VALUES (\(start), 0, 1, '95', '5', '', 1, 1, '');
                INSERT INTO session_sets(session_start, exercise_position, num, weight, reps, rpe, done, is_warmup, rir)
                VALUES (\(start), 0, 2, '225', '5', '', 1, 0, '');
                """, nil, nil, nil), SQLITE_OK, "v9 fixture insert failed; check the column lists")
        }

        let reopened = UserDatabase(path: path)
        XCTAssertNil(reopened.unavailableReason)
        XCTAssertFalse(sessionSetsColumns().contains("is_warmup"))
        let loaded = try XCTUnwrap(reopened.listSavedSessions().first {
            Int64($0.startTime.timeIntervalSince1970) == start
        })
        XCTAssertEqual(loaded.exercises.first?.sets.map(\.setType), [.warmup, .normal])
    }

    // MARK: - v11 user_exercises

    func test_freshInstall_hasUserExercisesWithItsFiveColumns() {
        let db = UserDatabase(path: path)
        XCTAssertNil(db.unavailableReason)
        XCTAssertEqual(columns(of: "user_exercises"),
                       ["id", "name", "muscle_bucket", "notes", "created_at"])
    }

    func test_v10File_upgradesToV11_andKeepsSessions() throws {
        let start: Int64 = 1_780_000_000
        do {
            let v = UserDatabase(path: path)
            let db = try XCTUnwrap(v.db)
            XCTAssertEqual(sqlite3_exec(db, "DROP TABLE user_exercises", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 10", nil, nil, nil), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(db, """
                INSERT INTO sessions(start_time, template_id, name, category, end_time, duration)
                VALUES (\(start), 't', 'Old', 'lift', \(start + 1800), 1800);
                INSERT INTO session_exercises(session_start, position, exercise_template_id, name, type, unit,
                                              target_sets, target_reps, rest, prev_sets_json)
                VALUES (\(start), 0, 'sq', 'Back Squat', 'Barbell', 'lbs', 2, 5, 180, '[]');
                INSERT INTO session_sets(session_start, exercise_position, num, weight, reps, rpe, done, rir, set_type)
                VALUES (\(start), 0, 1, '95', '5', '', 1, '', 'warmup');
                INSERT INTO session_sets(session_start, exercise_position, num, weight, reps, rpe, done, rir, set_type)
                VALUES (\(start), 0, 2, '225', '5', '', 1, '', 'normal');
                """, nil, nil, nil), SQLITE_OK, "v10 fixture insert failed; check the column lists")
        }
        XCTAssertEqual(userVersion(), 10)
        XCTAssertEqual(columns(of: "user_exercises"), [], "fixture: v10 has no user_exercises")

        let reopened = UserDatabase(path: path)
        XCTAssertNil(reopened.unavailableReason)
        XCTAssertEqual(userVersion(), UserDatabase.latestSchemaVersion)
        XCTAssertEqual(columns(of: "user_exercises"),
                       ["id", "name", "muscle_bucket", "notes", "created_at"])
        let loaded = try XCTUnwrap(reopened.listSavedSessions().first {
            Int64($0.startTime.timeIntervalSince1970) == start
        })
        XCTAssertEqual(loaded.exercises.map(\.name), ["Back Squat"])
        XCTAssertEqual(loaded.exercises.first?.sets.map(\.weight), ["95", "225"])
        XCTAssertEqual(loaded.exercises.first?.sets.map(\.setType), [.warmup, .normal])
        XCTAssertNoThrow(try reopened.createUserExercise(name: "Zorblax", muscleBucket: nil, notes: nil).get(),
                         "the upgraded table accepts writes")
    }

    // MARK: - Re-open is a no-op

    func test_reopen_atLatestVersion_staysThere() {
        _ = UserDatabase(path: path)          // fresh install → latest
        XCTAssertEqual(userVersion(), UserDatabase.latestSchemaVersion)
        let again = UserDatabase(path: path)  // re-open: migrations skip
        XCTAssertTrue(again.isOpen)
        XCTAssertEqual(userVersion(), UserDatabase.latestSchemaVersion)
    }

    // MARK: - FK cascade (session_sets follow their exercises)

    /// saveSession pre-clears session_exercises for the start_time before
    /// re-inserting; the composite FK on session_sets (ON DELETE CASCADE,
    /// enforced by the per-open PRAGMA foreign_keys) must sweep the old
    /// sets with them — re-saving a smaller session leaves no orphans.
    func test_resaveSmallerSession_leavesNoOrphanSets() {
        let db = UserDatabase(path: path)
        let start = Date(timeIntervalSince1970: 1_000)
        let set = LoggedSet(num: 1, weight: "135", reps: "5", rpe: "7", done: true)
        func exercise(_ name: String, sets: [LoggedSet]) -> LoggedExercise {
            LoggedExercise(id: name, name: name, type: nil, unit: "lbs",
                           targetSets: sets.count, targetReps: 5, rest: 90,
                           sets: sets, prevSets: [])
        }
        func session(_ exercises: [LoggedExercise]) -> SavedSession {
            SavedSession(templateId: "t1", name: "Push", category: "cat",
                         startTime: start, exercises: exercises,
                         feel: nil, note: nil,
                         endTime: start.addingTimeInterval(3_000), duration: 3_000)
        }
        func rawSetCount() -> Int32? {
            withRawDB { db in
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM session_sets", -1, &stmt, nil) == SQLITE_OK,
                      sqlite3_step(stmt) == SQLITE_ROW else { return Int32(-1) }
                return sqlite3_column_int(stmt, 0)
            }
        }

        // Two exercises x two sets, then resave the same start_time smaller.
        db.saveSession(session([
            exercise("Squat", sets: [set, LoggedSet(num: 2, weight: "145", reps: "5", rpe: "8", done: true)]),
            exercise("Bench", sets: [set, LoggedSet(num: 2, weight: "95", reps: "8", rpe: "7", done: true)])
        ]))
        XCTAssertEqual(rawSetCount(), 4)

        db.saveSession(session([exercise("Squat", sets: [set])]))
        XCTAssertEqual(rawSetCount(), 1,
                       "re-saving smaller must cascade away the old sets, not orphan them")
    }
}
