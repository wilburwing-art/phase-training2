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

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    private func withLock<T>(_ body: () -> T) -> T {
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
            "CREATE INDEX IF NOT EXISTS idx_imported_sets_source   ON imported_sets(source)",
            "PRAGMA foreign_keys = ON"
        ]
        for sql in stmts {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                if let err { sqlite3_free(err) }
            }
        }
        // Idempotent ALTER for pre-existing session_sets rows from earlier
        // builds where the table existed without is_warmup. The DEFAULT 0
        // in the CREATE handles fresh installs; this handles upgrades.
        // Errors are expected + ignored on subsequent runs (duplicate column).
        var alterErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "ALTER TABLE session_sets ADD COLUMN is_warmup INTEGER NOT NULL DEFAULT 0", nil, nil, &alterErr)
        if let alterErr { sqlite3_free(alterErr) }
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

    // MARK: - Saved sessions

    /// All saved sessions, newest first. Materializes the full nested tree
    /// (sessions → exercises → sets) for the @Published cache that
    /// SwiftUI screens bind to.
    func listSavedSessions() -> [SavedSession] { withLock {
        guard let db else { return [] }
        let sql = "SELECT start_time, template_id, name, category, end_time, duration, feel, note FROM sessions ORDER BY start_time DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [(start: Int64, tpl: String, name: String, cat: String, end: Int64, dur: Int, feel: String?, note: String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((
                sqlite3_column_int64(stmt, 0),
                text(stmt, 1) ?? "",
                text(stmt, 2) ?? "",
                text(stmt, 3) ?? "",
                sqlite3_column_int64(stmt, 4),
                Int(sqlite3_column_int64(stmt, 5)),
                text(stmt, 6),
                text(stmt, 7)
            ))
        }
        return rows.map { r in
            SavedSession(
                templateId: r.tpl,
                name: r.name,
                category: r.cat,
                startTime: Date(timeIntervalSince1970: TimeInterval(r.start)),
                exercises: loadExercisesLocked(sessionStart: r.start),
                feel: r.feel,
                note: r.note,
                endTime: Date(timeIntervalSince1970: TimeInterval(r.end)),
                duration: r.dur
            )
        }
    } }

    /// Newest session matching `templateId`. Indexed by (template_id, start_time DESC).
    /// Replaces the O(N) scan in SessionStore.getPreviousSession.
    func previousSession(templateId: String) -> SavedSession? { withLock {
        guard let db else { return nil }
        let sql = "SELECT start_time, template_id, name, category, end_time, duration, feel, note FROM sessions WHERE template_id = ? ORDER BY start_time DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, templateId, -1, SQLITE_TRANSIENT_USER)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let start = sqlite3_column_int64(stmt, 0)
        return SavedSession(
            templateId: text(stmt, 1) ?? "",
            name: text(stmt, 2) ?? "",
            category: text(stmt, 3) ?? "",
            startTime: Date(timeIntervalSince1970: TimeInterval(start)),
            exercises: loadExercisesLocked(sessionStart: start),
            feel: text(stmt, 6),
            note: text(stmt, 7),
            endTime: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4))),
            duration: Int(sqlite3_column_int64(stmt, 5))
        )
    } }

    /// Most recent LoggedExercise (by name, case-insensitive) that has at
    /// least one completed WORKING set with a non-empty weight. Indexed
    /// lookup replacing the O(N×M) cross-session scan in SessionStore.
    ///
    /// Warmup sets excluded — progressive-overload autofill should reflect
    /// the user's last working weight, not the warmup ramp.
    func mostRecentExerciseByName(_ name: String) -> LoggedExercise? { withLock {
        guard let db else { return nil }
        let sql = """
        SELECT se.session_start, se.position
        FROM session_exercises se
        WHERE se.name = ? COLLATE NOCASE
          AND EXISTS (
            SELECT 1 FROM session_sets ss
            WHERE ss.session_start = se.session_start
              AND ss.exercise_position = se.position
              AND ss.done = 1
              AND ss.is_warmup = 0
              AND ss.weight <> ''
          )
        ORDER BY se.session_start DESC
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT_USER)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let sessionStart = sqlite3_column_int64(stmt, 0)
        let position = Int(sqlite3_column_int64(stmt, 1))
        return loadOneExerciseLocked(sessionStart: sessionStart, position: position)
    } }

    /// Caller holds the lock. Used by listSavedSessions + previousSession.
    private func loadExercisesLocked(sessionStart: Int64) -> [LoggedExercise] {
        guard let db else { return [] }
        let sql = """
        SELECT position, exercise_template_id, name, type, unit, target_sets, target_reps, rest, prev_sets_json
        FROM session_exercises
        WHERE session_start = ?
        ORDER BY position ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sessionStart)

        var heads: [(position: Int, tplId: String, name: String, type: String?, unit: String, targetSets: Int, targetReps: Int, rest: Int, prevJSON: String?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            heads.append((
                Int(sqlite3_column_int64(stmt, 0)),
                text(stmt, 1) ?? "",
                text(stmt, 2) ?? "",
                text(stmt, 3),
                text(stmt, 4) ?? "lbs",
                Int(sqlite3_column_int64(stmt, 5)),
                Int(sqlite3_column_int64(stmt, 6)),
                Int(sqlite3_column_int64(stmt, 7)),
                text(stmt, 8)
            ))
        }
        return heads.map { h in
            LoggedExercise(
                id: h.tplId,
                name: h.name,
                type: h.type,
                unit: h.unit,
                targetSets: h.targetSets,
                targetReps: h.targetReps,
                rest: h.rest,
                sets: loadSetsLocked(sessionStart: sessionStart, position: h.position),
                prevSets: decodePrevSets(h.prevJSON)
            )
        }
    }

    private func loadOneExerciseLocked(sessionStart: Int64, position: Int) -> LoggedExercise? {
        guard let db else { return nil }
        let sql = """
        SELECT exercise_template_id, name, type, unit, target_sets, target_reps, rest, prev_sets_json
        FROM session_exercises
        WHERE session_start = ? AND position = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sessionStart)
        sqlite3_bind_int64(stmt, 2, Int64(position))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return LoggedExercise(
            id: text(stmt, 0) ?? "",
            name: text(stmt, 1) ?? "",
            type: text(stmt, 2),
            unit: text(stmt, 3) ?? "lbs",
            targetSets: Int(sqlite3_column_int64(stmt, 4)),
            targetReps: Int(sqlite3_column_int64(stmt, 5)),
            rest: Int(sqlite3_column_int64(stmt, 6)),
            sets: loadSetsLocked(sessionStart: sessionStart, position: position),
            prevSets: decodePrevSets(text(stmt, 7))
        )
    }

    private func loadSetsLocked(sessionStart: Int64, position: Int) -> [LoggedSet] {
        guard let db else { return [] }
        let sql = "SELECT num, weight, reps, rpe, done, is_warmup FROM session_sets WHERE session_start = ? AND exercise_position = ? ORDER BY num ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sessionStart)
        sqlite3_bind_int64(stmt, 2, Int64(position))
        var out: [LoggedSet] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(LoggedSet(
                num: Int(sqlite3_column_int64(stmt, 0)),
                weight: text(stmt, 1) ?? "",
                reps: text(stmt, 2) ?? "",
                rpe: text(stmt, 3) ?? "",
                done: sqlite3_column_int64(stmt, 4) == 1,
                isWarmup: sqlite3_column_int64(stmt, 5) == 1
            ))
        }
        return out
    }

    private func decodePrevSets(_ json: String?) -> [LoggedSet] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        let dec = JSONDecoder()
        return (try? dec.decode([LoggedSet].self, from: data)) ?? []
    }

    /// Insert one completed session + its exercises + its sets in one
    /// transaction. Idempotent on PK conflict (start_time): REPLACE so
    /// re-saving from an in-memory list during migration doesn't dup-fail.
    func saveSession(_ session: SavedSession) { withLock {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        let start = Int64(session.startTime.timeIntervalSince1970)
        let end = Int64(session.endTime.timeIntervalSince1970)

        // Wipe old children for idempotent re-save (migration replay safety).
        var clrEx: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM session_exercises WHERE session_start = ?", -1, &clrEx, nil) == SQLITE_OK {
            sqlite3_bind_int64(clrEx, 1, start)
            sqlite3_step(clrEx)
        }
        sqlite3_finalize(clrEx)

        let sessSQL = """
        INSERT INTO sessions(start_time, template_id, name, category, end_time, duration, feel, note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(start_time) DO UPDATE SET
          template_id = excluded.template_id,
          name = excluded.name,
          category = excluded.category,
          end_time = excluded.end_time,
          duration = excluded.duration,
          feel = excluded.feel,
          note = excluded.note
        """
        var s: OpaquePointer?
        if sqlite3_prepare_v2(db, sessSQL, -1, &s, nil) == SQLITE_OK {
            sqlite3_bind_int64(s, 1, start)
            sqlite3_bind_text(s, 2, session.templateId, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(s, 3, session.name, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(s, 4, session.category, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int64(s, 5, end)
            sqlite3_bind_int64(s, 6, Int64(session.duration))
            if let f = session.feel { sqlite3_bind_text(s, 7, f, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(s, 7) }
            if let n = session.note { sqlite3_bind_text(s, 8, n, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(s, 8) }
            sqlite3_step(s)
        }
        sqlite3_finalize(s)

        let exSQL = """
        INSERT INTO session_exercises(session_start, position, exercise_template_id, name, type, unit, target_sets, target_reps, rest, prev_sets_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let setSQL = """
        INSERT INTO session_sets(session_start, exercise_position, num, weight, reps, rpe, done, is_warmup)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        let enc = JSONEncoder()
        for (pos, ex) in session.exercises.enumerated() {
            var eStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, exSQL, -1, &eStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(eStmt, 1, start)
                sqlite3_bind_int64(eStmt, 2, Int64(pos))
                sqlite3_bind_text(eStmt, 3, ex.id, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_text(eStmt, 4, ex.name, -1, SQLITE_TRANSIENT_USER)
                if let t = ex.type { sqlite3_bind_text(eStmt, 5, t, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(eStmt, 5) }
                sqlite3_bind_text(eStmt, 6, ex.unit, -1, SQLITE_TRANSIENT_USER)
                sqlite3_bind_int64(eStmt, 7, Int64(ex.targetSets))
                sqlite3_bind_int64(eStmt, 8, Int64(ex.targetReps))
                sqlite3_bind_int64(eStmt, 9, Int64(ex.rest))
                let prevJSON = (try? enc.encode(ex.prevSets)).flatMap { String(data: $0, encoding: .utf8) }
                if let j = prevJSON { sqlite3_bind_text(eStmt, 10, j, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(eStmt, 10) }
                sqlite3_step(eStmt)
            }
            sqlite3_finalize(eStmt)

            for set in ex.sets {
                var sStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, setSQL, -1, &sStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int64(sStmt, 1, start)
                    sqlite3_bind_int64(sStmt, 2, Int64(pos))
                    sqlite3_bind_int64(sStmt, 3, Int64(set.num))
                    sqlite3_bind_text(sStmt, 4, set.weight, -1, SQLITE_TRANSIENT_USER)
                    sqlite3_bind_text(sStmt, 5, set.reps, -1, SQLITE_TRANSIENT_USER)
                    sqlite3_bind_text(sStmt, 6, set.rpe, -1, SQLITE_TRANSIENT_USER)
                    sqlite3_bind_int64(sStmt, 7, set.done ? 1 : 0)
                    sqlite3_bind_int64(sStmt, 8, set.isWarmup ? 1 : 0)
                    sqlite3_step(sStmt)
                }
                sqlite3_finalize(sStmt)
            }
        }
    } }

    func deleteSession(startTime: Date) { withLock {
        guard let db else { return }
        let start = Int64(startTime.timeIntervalSince1970)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM sessions WHERE start_time = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, start)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    } }

    func clearAllSessions() { withLock {
        guard let db else { return }
        sqlite3_exec(db, "DELETE FROM session_sets", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM session_exercises", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM sessions", nil, nil, nil)
    } }

    // MARK: - PR aggregation (replaces in-memory walks in SessionStore)

    /// Flat row from a qualifying completed set, suitable for replaying the
    /// running-best walk that powers `allPersonalRecords()`.
    struct PRSetRow {
        let name: String
        let reps: Int
        let weight: Double
        let sessionStart: Int64
    }

    /// All completed sets with parseable positive (weight, reps), ordered by
    /// session_start ASC then by position. Parsing mirrors Swift's
    /// `LoggedSet.repsValue`/`weightValue`: reps must START with a digit (the
    /// leading int via CAST, so "8-10" -> 8 and "AMRAP" is rejected), and a
    /// decimal comma is normalized before CAST (so "60,5" -> 60.5). Keeping
    /// these in lock-step with the Swift parser prevents the live PR path
    /// (personalRecords(in:)) from disagreeing with this baseline.
    ///
    /// Warmup sets excluded — never count as PRs.
    func qualifyingSetsForPRs() -> [PRSetRow] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT se.name,
               CAST(ss.reps AS INTEGER) AS reps_int,
               CAST(REPLACE(ss.weight, ',', '.') AS REAL) AS weight_real,
               ss.session_start
        FROM session_sets ss
        JOIN session_exercises se
          ON se.session_start = ss.session_start
         AND se.position = ss.exercise_position
        WHERE ss.done = 1
          AND ss.is_warmup = 0
          AND ss.weight <> ''
          AND ss.reps GLOB '[0-9]*'
          AND CAST(REPLACE(ss.weight, ',', '.') AS REAL) > 0
        ORDER BY ss.session_start ASC, ss.exercise_position ASC, ss.num ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [PRSetRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(PRSetRow(
                name: text(stmt, 0) ?? "",
                reps: Int(sqlite3_column_int64(stmt, 1)),
                weight: sqlite3_column_double(stmt, 2),
                sessionStart: sqlite3_column_int64(stmt, 3)
            ))
        }
        return out
    } }

    /// Map of `[exerciseName -> [reps -> max_weight]]` across all qualifying
    /// completed sets. Optionally excludes one session by start_time (used
    /// by `personalRecords(in:excludingSessionId:)` when comparing a
    /// just-saved session against pre-existing history).
    ///
    /// Warmup sets excluded — never count as PRs.
    func bestWeightsByExerciseAndReps(excludingSessionStart: Int64? = nil) -> [String: [Int: Double]] { withLock {
        guard let db else { return [:] }
        var sql = """
        SELECT se.name,
               CAST(ss.reps AS INTEGER) AS reps_int,
               MAX(CAST(REPLACE(ss.weight, ',', '.') AS REAL)) AS max_weight
        FROM session_sets ss
        JOIN session_exercises se
          ON se.session_start = ss.session_start
         AND se.position = ss.exercise_position
        WHERE ss.done = 1
          AND ss.is_warmup = 0
          AND ss.weight <> ''
          AND ss.reps GLOB '[0-9]*'
          AND CAST(REPLACE(ss.weight, ',', '.') AS REAL) > 0
        """
        if excludingSessionStart != nil {
            sql += " AND ss.session_start <> ?"
        }
        sql += " GROUP BY se.name, CAST(ss.reps AS INTEGER)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        if let exclude = excludingSessionStart {
            sqlite3_bind_int64(stmt, 1, exclude)
        }
        var out: [String: [Int: Double]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = text(stmt, 0) ?? ""
            let reps = Int(sqlite3_column_int64(stmt, 1))
            let weight = sqlite3_column_double(stmt, 2)
            out[name, default: [:]][reps] = weight
        }
        return out
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

    // MARK: - Imported workouts (Phase 2: HealthKit; Phase 3: CSV)

    /// Insert (or replace on id conflict) a batch of imported workouts.
    /// Wrapped in a single transaction — HK syncs typically batch the
    /// whole 28-day window, so per-row commits would cost real ms on
    /// the first sync. `imported_at` is stamped at insert time so the
    /// Settings screen can show "last synced N min ago" without keeping
    /// a separate timestamp.
    func insertImportedWorkouts(_ rows: [ImportedWorkout]) { withLock {
        guard let db, !rows.isEmpty else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        let sql = """
        INSERT OR REPLACE INTO imported_workouts(
          id, source, hk_uuid, kind, start_time, duration_seconds,
          energy_kcal, imported_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let now = Int64(Date().timeIntervalSince1970)
        for row in rows {
            sqlite3_bind_text(stmt, 1, row.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, row.source.rawValue, -1, SQLITE_TRANSIENT_USER)
            // HK rows carry the same UUID in `id` and `hk_uuid`. For CSV
            // rows, hk_uuid is NULL.
            if row.source == .healthKit {
                sqlite3_bind_text(stmt, 3, row.id, -1, SQLITE_TRANSIENT_USER)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, row.kind.rawValue, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int64(stmt, 5, Int64(row.startTime.timeIntervalSince1970))
            sqlite3_bind_double(stmt, 6, row.duration)
            if let kcal = row.energyKcal {
                sqlite3_bind_double(stmt, 7, kcal)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_int64(stmt, 8, now)

            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    } }

    /// Fetch imported workouts whose `start_time` falls within the last
    /// `days` days, newest first. Used by `GeneratorContext.from(...)`
    /// to union with native sessions for readiness signal computation.
    func recentImportedWorkouts(within days: Int) -> [ImportedWorkout] { withLock {
        guard let db, days > 0 else { return [] }
        let cutoff = Int64(Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970)
        let sql = """
        SELECT id, source, kind, start_time, duration_seconds, energy_kcal
        FROM imported_workouts
        WHERE start_time >= ?
        ORDER BY start_time DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoff)

        var out: [ImportedWorkout] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let id = text(stmt, 0),
                let sourceRaw = text(stmt, 1),
                let source = ImportSource(rawValue: sourceRaw),
                let kindRaw = text(stmt, 2),
                let kind = WorkoutKind(rawValue: kindRaw)
            else { continue }
            let startTime = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
            let dur = sqlite3_column_double(stmt, 4)
            let kcal: Double? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(stmt, 5)
            out.append(ImportedWorkout(
                id: id,
                source: source,
                kind: kind,
                startTime: startTime,
                duration: dur,
                energyKcal: kcal
            ))
        }
        return out
    } }

    /// Diagnostic helper for Settings → Health & Imports. Returns
    /// (row count, oldest start, newest start, last import timestamp)
    /// or nil if no imports exist.
    func importedWorkoutSummary() -> (count: Int, oldest: Date?, newest: Date?, lastImported: Date?)? { withLock {
        guard let db else { return nil }
        let sql = """
        SELECT COUNT(*), MIN(start_time), MAX(start_time), MAX(imported_at)
        FROM imported_workouts
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_int64(stmt, 0))
        if count == 0 { return (0, nil, nil, nil) }
        let oldest = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)))
        let newest = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
        let last = sqlite3_column_type(stmt, 3) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
        return (count, oldest, newest, last)
    } }

    // MARK: - Imported sets (Phase 3: CSV strength history)

    /// Insert (or replace on id conflict) a batch of imported sets in a
    /// single transaction. A 5k-row Fitbod history is typical; per-row
    /// commits would noticeably slow the first import. `imported_at` is
    /// stamped at write time. `exercise_id` is nullable — unmatched names
    /// keep `exercise_name_raw` for later remediation.
    func insertImportedSets(_ rows: [ImportedSet]) { withLock {
        guard let db, !rows.isEmpty else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        let sql = """
        INSERT OR REPLACE INTO imported_sets(
          id, source, exercise_id, exercise_name_raw, performed_at, set_num,
          weight, reps, rir, rpe, imported_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let now = Int64(Date().timeIntervalSince1970)
        for row in rows {
            sqlite3_bind_text(stmt, 1, row.id, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_text(stmt, 2, row.source.rawValue, -1, SQLITE_TRANSIENT_USER)
            if let exId = row.exerciseId {
                sqlite3_bind_int64(stmt, 3, Int64(exId))
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, row.exerciseNameRaw, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int64(stmt, 5, Int64(row.performedAt.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 6, Int64(row.setNum))
            if let w = row.weight { sqlite3_bind_double(stmt, 7, w) } else { sqlite3_bind_null(stmt, 7) }
            if let r = row.reps { sqlite3_bind_int64(stmt, 8, Int64(r)) } else { sqlite3_bind_null(stmt, 8) }
            if let rir = row.rir { sqlite3_bind_double(stmt, 9, rir) } else { sqlite3_bind_null(stmt, 9) }
            if let rpe = row.rpe { sqlite3_bind_double(stmt, 10, rpe) } else { sqlite3_bind_null(stmt, 10) }
            sqlite3_bind_int64(stmt, 11, now)

            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
    } }

    /// Per-exercise heaviest matched set in the import history. Used by
    /// `GeneratorContext.from(...)` to seed priorBest for users who
    /// import lifetime history before they've logged a native session.
    /// Returns rows for exercises with a resolved `exercise_id` only —
    /// unmatched names can't safely back priorBest.
    func importedSetsLifetimePeaks() -> [(exerciseId: Int, weight: Double, reps: Int, performedAt: Date)] { withLock {
        guard let db else { return [] }
        // Heaviest single-set weight per exercise, with the rep count and
        // date from that same row. Tiebreak by most recent (we prefer
        // newer evidence of the same peak).
        let sql = """
        SELECT exercise_id, weight, reps, performed_at
        FROM imported_sets
        WHERE exercise_id IS NOT NULL
          AND weight IS NOT NULL
          AND reps IS NOT NULL
        ORDER BY exercise_id, weight DESC, performed_at DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var lastEx = -1
        var out: [(exerciseId: Int, weight: Double, reps: Int, performedAt: Date)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let exId = Int(sqlite3_column_int64(stmt, 0))
            if exId == lastEx { continue }  // first row per exId is the peak
            lastEx = exId
            let w = sqlite3_column_double(stmt, 1)
            let r = Int(sqlite3_column_int64(stmt, 2))
            let at = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
            out.append((exId, w, r, at))
        }
        return out
    } }

    /// Settings diagnostic + per-source delete preflight. Returns count,
    /// oldest, newest, plus a per-source breakdown for the import list UI.
    func importedSetsSummary() -> (count: Int, oldest: Date?, newest: Date?, perSource: [String: Int])? { withLock {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*), MIN(performed_at), MAX(performed_at) FROM imported_sets", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_int64(stmt, 0))
        if count == 0 { return (0, nil, nil, [:]) }
        let oldest = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)))
        let newest = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))

        var perSource: [String: Int] = [:]
        var src: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT source, COUNT(*) FROM imported_sets GROUP BY source", -1, &src, nil) == SQLITE_OK {
            defer { sqlite3_finalize(src) }
            while sqlite3_step(src) == SQLITE_ROW {
                if let s = text(src, 0) {
                    perSource[s] = Int(sqlite3_column_int64(src, 1))
                }
            }
        }
        return (count, oldest, newest, perSource)
    } }

    /// Drop both imported_sets AND imported_workouts for a given source.
    /// Used by the Settings → Imports per-source delete row. Wrapped in a
    /// single transaction so partial deletes can't desync the two tables.
    func deleteImports(source: ImportSource) { withLock {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM imported_sets WHERE source = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, source.rawValue, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        var stmt2: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM imported_workouts WHERE source = ?", -1, &stmt2, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt2, 1, source.rawValue, -1, SQLITE_TRANSIENT_USER)
            sqlite3_step(stmt2)
            sqlite3_finalize(stmt2)
        }
    } }
}

private let SQLITE_TRANSIENT_USER = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
