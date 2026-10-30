// UserDatabase+ImportNames.swift — matching imported names the catalog missed.
//
// An imported exercise name that resolves to no coach.db exercise keeps a nil
// `exercise_id`, so its sets never reach suggestions or the history profile.
// The user can match it by hand (UnmatchedNamesSheet); the choice lands in
// `import_name_map` and on every unmatched row with that name, and the import
// resolvers read the map before the catalog.

import Foundation
import SQLite3

extension UserDatabase {

    /// raw name -> exercise id, everything the user has matched.
    func importNameMap() -> [String: Int] { withLock {
        guard let db else { return [:] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name_raw, exercise_id FROM import_name_map", -1, &stmt, nil) == SQLITE_OK
        else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var out: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 0) { out[name] = Int(sqlite3_column_int64(stmt, 1)) }
        }
        return out
    } }

    /// Unmatched imported names with their set counts, most sets first.
    func unmatchedImportNames() -> [(name: String, sets: Int)] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT exercise_name_raw, COUNT(*) AS n FROM imported_sets
        WHERE exercise_id IS NULL
        GROUP BY exercise_name_raw
        ORDER BY n DESC, exercise_name_raw ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 0) { out.append((name, Int(sqlite3_column_int64(stmt, 1)))) }
        }
        return out
    } }

    /// Match `raw` to `exerciseId`: remember it and fill every unmatched row
    /// with that name. Rows the catalog already matched are left alone.
    func setImportName(_ raw: String, exerciseId: Int) { withLock {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil)
        var ok = true
        defer { sqlite3_exec(db, ok ? "COMMIT" : "ROLLBACK", nil, nil, nil) }
        for sql in ["INSERT OR REPLACE INTO import_name_map(name_raw, exercise_id) VALUES (?, ?)",
                    "UPDATE imported_sets SET exercise_id = ?2 WHERE exercise_name_raw = ?1 AND exercise_id IS NULL"] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { ok = false; return }
            sqlite3_bind_text(stmt, 1, raw, -1, SQLITE_TRANSIENT_USER)
            sqlite3_bind_int64(stmt, 2, Int64(exerciseId))
            if sqlite3_step(stmt) != SQLITE_DONE { ok = false }
            sqlite3_finalize(stmt)
            if !ok { return }
        }
    }; postImportedSetsChanged() }

    /// The import resolver: the user's match first, then the catalog.
    func importNameResolver(coach: CoachDatabase) -> (String) -> Int? {
        let map = importNameMap()
        return { raw in map[raw] ?? coach.exerciseId(forImportName: raw) }
    }
}
