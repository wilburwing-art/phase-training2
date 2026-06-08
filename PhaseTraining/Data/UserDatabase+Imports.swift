// UserDatabase+Imports.swift
//
// Extracted from UserDatabase.swift (Tier-3 god-object split). Imported
// workout + imported set history (Phase 2 HealthKit, Phase 3 CSV): batch
// inserts, readiness-window reads, Settings diagnostics, and the per-source
// delete. Core open/withLock, the versioned-migration runner, and the shared
// column helpers stay in UserDatabase.swift.

import Foundation
import SQLite3

extension UserDatabase {
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
        // Honor the documented "all rows or none": a mid-batch step failure
        // ROLLs the whole transaction back rather than committing a partial.
        var ok = true
        defer { sqlite3_exec(db, ok ? "COMMIT" : "ROLLBACK", nil, nil, nil) }

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

            if sqlite3_step(stmt) != SQLITE_DONE { ok = false; break }
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
        // Honor the documented "all rows or none": a mid-batch step failure
        // ROLLs the whole transaction back rather than committing a partial.
        var ok = true
        defer { sqlite3_exec(db, ok ? "COMMIT" : "ROLLBACK", nil, nil, nil) }

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

            if sqlite3_step(stmt) != SQLITE_DONE { ok = false; break }
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
        // If either DELETE fails, ROLL the pair back so the two tables can't
        // desync (the whole point of the transaction).
        var ok = true
        defer { sqlite3_exec(db, ok ? "COMMIT" : "ROLLBACK", nil, nil, nil) }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM imported_sets WHERE source = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, source.rawValue, -1, SQLITE_TRANSIENT_USER)
            if sqlite3_step(stmt) != SQLITE_DONE { ok = false }
            sqlite3_finalize(stmt)
        } else { ok = false }
        var stmt2: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM imported_workouts WHERE source = ?", -1, &stmt2, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt2, 1, source.rawValue, -1, SQLITE_TRANSIENT_USER)
            if sqlite3_step(stmt2) != SQLITE_DONE { ok = false }
            sqlite3_finalize(stmt2)
        } else { ok = false }
    } }
}
