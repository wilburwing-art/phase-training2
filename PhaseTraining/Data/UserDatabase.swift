import Foundation
import SQLite3

/// Read-write SQLite store for user-owned routines. Lives at
/// `Documents/user.db`, separate from the bundled read-only `coach.db` so
/// the catalog can be stomped on every install without touching user data.
///
/// Schema (see `runMigrations`):
///   user_routines(id TEXT PK, name, focus, created_at, updated_at)
///   user_routine_exercises(id TEXT PK, routine_id FK, exercise_id, position,
///                          sets, reps, rest, notes)
///
/// Cross-DB joins are not used — when display needs an exercise name from
/// coach.db, the caller asks `CoachDatabase.exercise(id:)`. SQLite connections
/// are cheap; keeping the two stores at arm's length avoids ATTACH semantics
/// + simplifies the catalog-update story.
final class UserDatabase {
    static let shared = UserDatabase()

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private init() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("user.db")
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK {
            if let d = db { sqlite3_close(d); db = nil }
            return
        }
        runMigrations()
    }

    deinit { if let db { sqlite3_close(db) } }

    var isOpen: Bool { db != nil }

    // MARK: - Migrations

    private func runMigrations() {
        let stmts = [
            """
            CREATE TABLE IF NOT EXISTS user_routines (
              id          TEXT PRIMARY KEY,
              name        TEXT NOT NULL,
              focus       TEXT,
              created_at  INTEGER NOT NULL,
              updated_at  INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS user_routine_exercises (
              id           TEXT PRIMARY KEY,
              routine_id   TEXT NOT NULL,
              exercise_id  INTEGER NOT NULL,
              position     INTEGER NOT NULL,
              sets         INTEGER,
              reps         TEXT,
              rest         TEXT,
              notes        TEXT,
              name         TEXT NOT NULL,
              FOREIGN KEY (routine_id) REFERENCES user_routines(id) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_ure_routine ON user_routine_exercises(routine_id, position)",
            "PRAGMA foreign_keys = ON"
        ]
        for sql in stmts {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                if let err { sqlite3_free(err) }
            }
        }
    }

    // MARK: - Reads

    /// All custom routines, newest first. Each row carries its full exercise
    /// list — at the current data volume (<100 customs per user) the join is
    /// trivial. If/when this grows, split into a lighter list query + lazy
    /// exercise fetch per row.
    func listRoutines() -> [CustomRoutine] { withLock {
        guard let db else { return [] }
        let sql = "SELECT id, name, created_at FROM user_routines ORDER BY created_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var heads: [(id: String, name: String, createdAt: Date)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = text(stmt, 0) else { continue }
            heads.append((
                id,
                text(stmt, 1) ?? "",
                Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
            ))
        }
        return heads.map { h in
            CustomRoutine(
                id: h.id,
                name: h.name,
                exercises: loadExercisesLocked(routineId: h.id),
                createdAt: h.createdAt
            )
        }
    } }

    func routine(id: String) -> CustomRoutine? { withLock {
        guard let db else { return nil }
        let sql = "SELECT id, name, created_at FROM user_routines WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT_USER)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let rid = text(stmt, 0) ?? id
        return CustomRoutine(
            id: rid,
            name: text(stmt, 1) ?? "",
            exercises: loadExercisesLocked(routineId: rid),
            createdAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
        )
    } }

    /// Caller holds the lock. Used by listRoutines and routine(id:).
    private func loadExercisesLocked(routineId: String) -> [CustomRoutineExercise] {
        guard let db else { return [] }
        let sql = """
        SELECT id, exercise_id, name, position, sets, reps, rest, notes
        FROM user_routine_exercises
        WHERE routine_id = ?
        ORDER BY position ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, routineId, -1, SQLITE_TRANSIENT_USER)

        var out: [CustomRoutineExercise] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(CustomRoutineExercise(
                id: text(stmt, 0) ?? UUID().uuidString,
                exerciseId: Int(sqlite3_column_int64(stmt, 1)),
                name: text(stmt, 2) ?? "",
                position: Int(sqlite3_column_int64(stmt, 3)),
                sets: intOrNil(stmt, 4),
                reps: text(stmt, 5),
                rest: text(stmt, 6),
                notes: text(stmt, 7)
            ))
        }
        return out
    }

    // MARK: - Writes

    /// Upsert one routine + replace its exercise list. Wrapped in a
    /// transaction so a partial write can't leave dangling exercises with
    /// no parent row.
    func save(_ routine: CustomRoutine) { withLock {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        let now = Int64(Date().timeIntervalSince1970)
        let createdAt = Int64(routine.createdAt.timeIntervalSince1970)

        let upsertSQL = """
        INSERT INTO user_routines(id, name, focus, created_at, updated_at)
        VALUES (?, ?, NULL, ?, ?)
        ON CONFLICT(id) DO UPDATE SET name = excluded.name, updated_at = excluded.updated_at
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, routine.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, routine.name, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int64(stmt, 3, createdAt)
            sqlite3_bind_int64(stmt, 4, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM user_routine_exercises WHERE routine_id = ?", -1, &delStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(delStmt, 1, routine.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(delStmt)
        }
        sqlite3_finalize(delStmt)

        let insertSQL = """
        INSERT INTO user_routine_exercises(id, routine_id, exercise_id, position, sets, reps, rest, notes, name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        for ex in routine.exercises {
            var iStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertSQL, -1, &iStmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(iStmt, 1, ex.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(iStmt, 2, routine.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int64(iStmt, 3, Int64(ex.exerciseId))
            sqlite3_bind_int64(iStmt, 4, Int64(ex.position))
            if let s = ex.sets { sqlite3_bind_int64(iStmt, 5, Int64(s)) } else { sqlite3_bind_null(iStmt, 5) }
            if let r = ex.reps { sqlite3_bind_text(iStmt, 6, r, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(iStmt, 6) }
            if let rest = ex.rest { sqlite3_bind_text(iStmt, 7, rest, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(iStmt, 7) }
            if let n = ex.notes { sqlite3_bind_text(iStmt, 8, n, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(iStmt, 8) }
            sqlite3_bind_text(iStmt, 9, ex.name, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(iStmt)
            sqlite3_finalize(iStmt)
        }
    } }

    func delete(routineId: String) { withLock {
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM user_routines WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, routineId, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        var exStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM user_routine_exercises WHERE routine_id = ?", -1, &exStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(exStmt, 1, routineId, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(exStmt)
        }
        sqlite3_finalize(exStmt)
    } }

    func clearAll() { withLock {
        guard let db else { return }
        sqlite3_exec(db, "DELETE FROM user_routine_exercises", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM user_routines", nil, nil, nil)
    } }

    // MARK: - Helpers

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    private func intOrNil(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        if sqlite3_column_type(stmt, idx) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(stmt, idx))
    }
}

private let SQLITE_TRANSIENT_USER = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
