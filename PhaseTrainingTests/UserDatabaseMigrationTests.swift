// UserDatabaseMigrationTests — characterize the PRAGMA user_version
// migration runner in UserDatabase.
//
// Two paths matter:
//  1. Fresh install: v1 creates the full current schema (is_warmup in the
//     CREATE) and stamps user_version = 1.
//  2. Pre-versioning upgrade: a legacy user.db (user_version = 0, session_sets
//     WITHOUT is_warmup) gets the column via the explicit existence check,
//     then v1 no-ops over the live schema and stamps 1.
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

    private func sessionSetsColumns() -> [String] {
        withRawDB { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(session_sets)", -1, &stmt, nil) == SQLITE_OK else { return [] }
            var cols: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 1) { cols.append(String(cString: c)) }
            }
            return cols
        } ?? []
    }

    // MARK: - Fresh install

    func test_freshInstall_stampsVersion1_withWarmupInCreate() {
        let db = UserDatabase(path: path)
        XCTAssertTrue(db.isOpen)

        XCTAssertEqual(userVersion(), 1, "fresh install must stamp user_version = 1")
        let cols = sessionSetsColumns()
        XCTAssertTrue(cols.contains("is_warmup"),
                      "v1 CREATE must include is_warmup; got \(cols)")
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

        XCTAssertEqual(userVersion(), 1, "upgrade must stamp user_version = 1")
        XCTAssertTrue(sessionSetsColumns().contains("is_warmup"),
                      "legacy session_sets must gain is_warmup via the existence check")

        // The pre-existing row survives with the DEFAULT 0 backfill.
        let warmup: Int32? = withRawDB { db in
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT is_warmup FROM session_sets WHERE session_start = 1", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return Int32(-1) }
            return sqlite3_column_int(stmt, 0)
        }
        XCTAssertEqual(warmup, 0)
    }

    // MARK: - Re-open is a no-op

    func test_reopen_atVersion1_staysAtVersion1() {
        _ = UserDatabase(path: path)          // fresh install → v1
        XCTAssertEqual(userVersion(), 1)
        let again = UserDatabase(path: path)  // re-open: migrations skip
        XCTAssertTrue(again.isOpen)
        XCTAssertEqual(userVersion(), 1)
    }
}
