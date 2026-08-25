// UserDatabase+Sessions.swift
//
// Extracted from UserDatabase.swift (Tier-3 god-object split). Saved-session
// persistence (sessions / session_exercises / session_sets), session deletes
// + the canonical wipeAll, and the SQL-side PR aggregation that replaces the
// in-memory walks in SessionStore. Core open/withLock, the versioned-migration
// runner, and the shared column helpers stay in UserDatabase.swift.

import Foundation
import SQLite3

extension UserDatabase {
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

    /// COUNT(*) over sessions. Same rationale as `routineCount()` — the full
    /// sessions → exercises → sets tree is wasted work for a count.
    func savedSessionCount() -> Int { withLock { countLocked(table: "sessions") } }

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
    /// Returns false when the session did not reach disk. Previously this was
    /// `Void` with a silent `guard let db else { return }`, so a closed or
    /// un-migrated database swallowed the write while SessionStore still
    /// reported success to CompleteScreen — the workout looked saved until the
    /// next launch, when it was gone.
    @discardableResult
    func saveSession(_ session: SavedSession) -> Bool { withLock {
        guard let db else { return false }
        var ok = true
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
            if sqlite3_step(s) != SQLITE_DONE { ok = false }
        } else {
            ok = false
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
                if sqlite3_step(eStmt) != SQLITE_DONE { ok = false }
            } else {
                ok = false
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
                    if sqlite3_step(sStmt) != SQLITE_DONE { ok = false }
                } else {
                    ok = false
                }
                sqlite3_finalize(sStmt)
            }
        }
        return ok
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

    /// Canonical "delete every user-owned row" path for the SQLite layer:
    /// saved sessions, custom routines, and imported-workout history. Paired
    /// with `MemoryStore.wipeAllUserData` (the UserDefaults side) so the full
    /// "Erase all my data" flow clears both stores. Single transaction so a
    /// crash mid-wipe can't leave a half-deleted tree.
    func wipeAll() { withLock {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for table in ["session_sets", "session_exercises", "sessions",
                      "user_routine_exercises", "user_routines",
                      "imported_sets", "imported_workouts"] {
            sqlite3_exec(db, "DELETE FROM \(table)", nil, nil, nil)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
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
}
