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
    /// Production singleton, opened against `Documents/user.db`.
    static let shared = UserDatabase()

    var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private convenience init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        self.init(path: dir?.appendingPathComponent("user.db").path ?? ":memory:")
    }

    /// Default backing store for app-level stores (SessionStore,
    /// CustomRoutineStore). In production returns `.shared`. Under XCTest
    /// or SwiftUI Previews returns a FRESH in-memory instance per call so
    /// each test / preview gets isolated state — otherwise tests pollute
    /// each other through the singleton and previews would mutate the
    /// user's real Documents/user.db.
    static func defaultStore() -> UserDatabase {
        let env = ProcessInfo.processInfo.environment
        let isEphemeral = env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || env["XCTestConfigurationFilePath"] != nil
        return isEphemeral ? UserDatabase(path: ":memory:") : .shared
    }

    /// Build a UserDatabase against an explicit file path. Pass `":memory:"`
    /// for previews and unit tests so they never touch the real user.db.
    init(path: String) {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            if let d = db { sqlite3_close(d); db = nil }
            return
        }
        runMigrations()
    }

    deinit { if let db { sqlite3_close(db) } }

    var isOpen: Bool { db != nil }

    // MARK: - Migrations

    /// Schema migrations, applied in order. Each entry is (target_version,
    /// statements). The DB's `PRAGMA user_version` tracks the highest applied
    /// version; on open we run any migration whose version exceeds current.
    /// Existing pre-versioning installs (user_version = 0) re-run v1 — all v1
    /// statements use `IF NOT EXISTS`, so the migration is a no-op on top of
    /// the live schema and just stamps user_version = 1.
    ///
    /// To add a column or table, append a new entry. Never edit or reorder
    /// past entries — that would skip the change on installed users.
    private static let migrations: [(version: Int32, statements: [String])] = [
        (1, [
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
            """
            CREATE TABLE IF NOT EXISTS sessions (
              start_time   INTEGER PRIMARY KEY,
              template_id  TEXT NOT NULL,
              name         TEXT NOT NULL,
              category     TEXT NOT NULL,
              end_time     INTEGER NOT NULL,
              duration     INTEGER NOT NULL,
              feel         TEXT,
              note         TEXT
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS session_exercises (
              session_start         INTEGER NOT NULL,
              position              INTEGER NOT NULL,
              exercise_template_id  TEXT NOT NULL,
              name                  TEXT NOT NULL,
              type                  TEXT,
              unit                  TEXT NOT NULL,
              target_sets           INTEGER NOT NULL,
              target_reps           INTEGER NOT NULL,
              rest                  INTEGER NOT NULL,
              prev_sets_json        TEXT,
              PRIMARY KEY (session_start, position),
              FOREIGN KEY (session_start) REFERENCES sessions(start_time) ON DELETE CASCADE
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS session_sets (
              session_start      INTEGER NOT NULL,
              exercise_position  INTEGER NOT NULL,
              num                INTEGER NOT NULL,
              weight             TEXT NOT NULL,
              reps               TEXT NOT NULL,
              rpe                TEXT NOT NULL,
              done               INTEGER NOT NULL,
              is_warmup          INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (session_start, exercise_position, num),
              FOREIGN KEY (session_start, exercise_position)
                REFERENCES session_exercises(session_start, position) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_sessions_template_start ON sessions(template_id, start_time DESC)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_time DESC)",
            "CREATE INDEX IF NOT EXISTS idx_session_exercises_name ON session_exercises(name COLLATE NOCASE, session_start DESC)",
            // Phase 2 — imported workouts (HealthKit in v1, CSV imports
            // in Phase 3). One row per externally-sourced workout. Keyed
            // by the source's own UUID (HK UUID for HK, generated UUID
            // for CSV) so re-import is idempotent. We persist both
            // `source` and `hk_uuid` separately because Phase 3 CSV
            // sources will reuse the same table and we want HK rows
            // queryable on the original UUID for sync diagnostics.
            //
            // Indexed on start_time DESC for the readiness-window query
            // (most recent 28 days) and on kind for any future per-kind
            // filtering. No FK to native sessions — these are parallel
            // history streams that GeneratorContext unions in Swift.
            """
            CREATE TABLE IF NOT EXISTS imported_workouts (
              id                TEXT PRIMARY KEY,
              source            TEXT NOT NULL,
              hk_uuid           TEXT,
              kind              TEXT NOT NULL,
              start_time        INTEGER NOT NULL,
              duration_seconds  REAL NOT NULL,
              energy_kcal       REAL,
              imported_at       INTEGER NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_imported_workouts_start ON imported_workouts(start_time DESC)",
            "CREATE INDEX IF NOT EXISTS idx_imported_workouts_kind  ON imported_workouts(kind)",
            // Phase 3: set-level import history. Lives alongside imported_workouts
            // (workout-level summary). CSV sources emit both: the workout-level
            // row gives readiness signal (frequency/recency); the set-level rows
            // give priorBest + true training-age + lifetime-peak detection. The
            // two are joined by performed_at proximity in Swift, NOT by FK —
            // workout-level rows from HK arrive without set detail.
            //
            // exercise_id is nullable: CSV exercise names that don't fuzzy-match
            // any coach.db row are still preserved (we never drop data) but
            // can't feed priorBest until the user manually maps or coach.db
            // grows aliases.
            """
            CREATE TABLE IF NOT EXISTS imported_sets (
              id                   TEXT PRIMARY KEY,
              source               TEXT NOT NULL,
              exercise_id          INTEGER,
              exercise_name_raw    TEXT NOT NULL,
              performed_at         INTEGER NOT NULL,
              set_num              INTEGER NOT NULL,
              weight               REAL,
              reps                 INTEGER,
              rir                  REAL,
              rpe                  REAL,
              imported_at          INTEGER NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_imported_sets_exercise ON imported_sets(exercise_id, performed_at DESC)",
            "CREATE INDEX IF NOT EXISTS idx_imported_sets_perf     ON imported_sets(performed_at DESC)",
            "CREATE INDEX IF NOT EXISTS idx_imported_sets_source   ON imported_sets(source)"
        ])
    ]

    private func runMigrations() {
        guard let db else { return }
        // Per-connection pragma, not a migration — must run on every open.
        sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        let current = currentUserVersion()
        // Legacy shim, pre-versioning installs only: builds before is_warmup
        // created session_sets without it, and v1's IF NOT EXISTS won't touch
        // the existing table. Explicit column-existence check, run once on the
        // 0 → 1 transition — replaces the old run-ALTER-every-launch-and-
        // swallow-the-duplicate-error pattern.
        if current == 0 { addWarmupColumnIfMissing() }
        for migration in Self.migrations where migration.version > current {
            if !apply(migration: migration) { return }
        }
    }

    /// Run one migration inside a transaction; roll back on the first failed
    /// statement so user_version never advances past a half-applied schema.
    private func apply(migration: (version: Int32, statements: [String])) -> Bool {
        guard let db else { return false }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for sql in migration.statements {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                if let err { sqlite3_free(err) }
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
        }
        // PRAGMA user_version doesn't accept bound params; interpolation is
        // safe — version is a compile-time Int32 from our own array.
        if sqlite3_exec(db, "PRAGMA user_version = \(migration.version)", nil, nil, nil) != SQLITE_OK {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        return true
    }

    private func currentUserVersion() -> Int32 {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0)
        }
        return 0
    }

    /// Add is_warmup to a pre-versioning session_sets that lacks it. A fresh
    /// install never reaches the ALTER (the table is absent here; v1's CREATE
    /// includes the column).
    private func addWarmupColumnIfMissing() {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(session_sets)", -1, &stmt, nil) == SQLITE_OK else { return }
        var hasTable = false, hasColumn = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            hasTable = true
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == "is_warmup" {
                hasColumn = true
                break
            }
        }
        sqlite3_finalize(stmt)
        if hasTable && !hasColumn {
            sqlite3_exec(db, "ALTER TABLE session_sets ADD COLUMN is_warmup INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        }
    }

    // MARK: - Helpers

    /// Caller holds the lock. Bare COUNT(*) over `table` — table names come
    /// from our own string literals, never user input.
    func countLocked(table: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    func intOrNil(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        if sqlite3_column_type(stmt, idx) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(stmt, idx))
    }
}

let SQLITE_TRANSIENT_USER = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
