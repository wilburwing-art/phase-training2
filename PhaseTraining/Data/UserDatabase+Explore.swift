// UserDatabase+Explore.swift — A3 storage for ExploreSession.

import Foundation
import SQLite3

extension UserDatabase: ExploreSink {

    /// Same retention as the missed / abandoned / outcome logs.
    static let exploreRetentionDays = 90

    func recordExploreSession(_ session: ExploreSession) {
        _ = insertExploreSession(session)
    }

    @discardableResult
    func insertExploreSession(_ s: ExploreSession) -> Bool { withLock {
        guard let db else { return false }
        let sql = """
        INSERT OR REPLACE INTO explore_sessions
          (id, surface, started_at, ended_at, query, result_count, tier, broadened,
           opens_json, conversions_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let opens = (try? enc.encode(s.opens)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let convs = (try? enc.encode(s.conversions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        sqlite3_bind_text(stmt, 1, s.id, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 2, s.surface.rawValue, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_double(stmt, 3, s.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, s.endedAt.timeIntervalSince1970)
        if let q = s.query { sqlite3_bind_text(stmt, 5, q, -1, SQLITE_TRANSIENT_USER) } else { sqlite3_bind_null(stmt, 5) }
        if let n = s.resultCount { sqlite3_bind_int64(stmt, 6, Int64(n)) } else { sqlite3_bind_null(stmt, 6) }
        if let t = s.tier { sqlite3_bind_int64(stmt, 7, Int64(t)) } else { sqlite3_bind_null(stmt, 7) }
        sqlite3_bind_int(stmt, 8, s.broadened ? 1 : 0)
        sqlite3_bind_text(stmt, 9, opens, -1, SQLITE_TRANSIENT_USER)
        sqlite3_bind_text(stmt, 10, convs, -1, SQLITE_TRANSIENT_USER)
        return sqlite3_step(stmt) == SQLITE_DONE
    } }

    /// Newest first. Rows whose surface or JSON no longer decode are skipped.
    func listExploreSessions(since: Date? = nil) -> [ExploreSession] { withLock {
        guard let db else { return [] }
        var sql = """
        SELECT id, surface, started_at, ended_at, query, result_count, tier, broadened,
               opens_json, conversions_json
        FROM explore_sessions
        """
        if since != nil { sql += " WHERE started_at >= ?" }
        sql += " ORDER BY started_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let since { sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        var out: [ExploreSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = text(stmt, 0),
                  let surface = text(stmt, 1).flatMap(ExploreSurface.init(rawValue:)),
                  let opens = text(stmt, 8).flatMap({ try? dec.decode([ExploreOpen].self, from: Data($0.utf8)) }),
                  let convs = text(stmt, 9).flatMap({ try? dec.decode([ExploreConversion].self, from: Data($0.utf8)) })
            else { continue }
            out.append(ExploreSession(
                id: id, surface: surface,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                endedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                query: text(stmt, 4), resultCount: intOrNil(stmt, 5), tier: intOrNil(stmt, 6),
                broadened: sqlite3_column_int(stmt, 7) != 0,
                opens: opens, conversions: convs))
        }
        return out
    } }

    /// Drop sessions older than the retention window. Run on every open.
    @discardableResult
    func pruneExploreSessions(now: Date = Date()) -> Int { withLock {
        guard let db else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(Self.exploreRetentionDays) * 86_400)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM explore_sessions WHERE started_at < ?", -1, &stmt, nil) == SQLITE_OK
        else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
        return Int(sqlite3_changes(db))
    } }
}
