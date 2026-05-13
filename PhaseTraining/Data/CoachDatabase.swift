import Foundation
import SQLite3

final class CoachDatabase {
    static let shared = CoachDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "coach.db.read")

    private init() {
        guard let path = Bundle.main.path(forResource: "coach", ofType: "db") else { return }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        sqlite3_open_v2(path, &db, flags, nil)
    }

    deinit { if let db { sqlite3_close(db) } }

    var isOpen: Bool { db != nil }

    func listRoutines(search: String? = nil, goal: String? = nil) -> [Routine] {
        guard let db else { return [] }
        var sql = """
        SELECT r.id, r.name, r.slug, r.description, r.goal, r.difficulty, r.phase,
               r.duration_minutes, r.environment,
               COUNT(DISTINCT re.id) AS ex_count,
               COALESCE(SUM(re.sets), 0) AS set_count
        FROM routines r
        LEFT JOIN routine_exercises re ON re.routine_id = r.id
        """
        var clauses: [String] = []
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            clauses.append("r.name LIKE ?")
        }
        if let g = goal {
            clauses.append("r.goal = ?")
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " GROUP BY r.id ORDER BY r.id ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 1
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            sqlite3_bind_text(stmt, bindIdx, "%\(s)%", -1, SQLITE_TRANSIENT)
            bindIdx += 1
        }
        if let g = goal {
            sqlite3_bind_text(stmt, bindIdx, g, -1, SQLITE_TRANSIENT)
            bindIdx += 1
        }

        var rows: [Routine] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Routine(
                id: Int(sqlite3_column_int64(stmt, 0)),
                name: text(stmt, 1) ?? "",
                slug: text(stmt, 2) ?? "",
                description: text(stmt, 3),
                goal: text(stmt, 4),
                difficulty: text(stmt, 5),
                phase: text(stmt, 6),
                durationMinutes: intOrNil(stmt, 7),
                environment: text(stmt, 8),
                exerciseCount: Int(sqlite3_column_int64(stmt, 9)),
                setCount: Int(sqlite3_column_int64(stmt, 10))
            ))
        }
        return rows
    }

    func goalCounts() -> [(goal: String, count: Int)] {
        guard let db else { return [] }
        let sql = "SELECT goal, COUNT(*) FROM routines WHERE goal IS NOT NULL GROUP BY goal ORDER BY 2 DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let g = text(stmt, 0) else { continue }
            out.append((g, Int(sqlite3_column_int64(stmt, 1))))
        }
        return out
    }

    func listExercises(search: String? = nil, modality: String? = nil) -> [Exercise] {
        guard let db else { return [] }
        var sql = """
        SELECT id, name, slug, description, instructions, cues, difficulty, modality,
               environment, is_compound, is_unilateral,
               default_sets, default_reps, default_rest, default_duration,
               regression, progression
        FROM exercises
        """
        var clauses: [String] = []
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            clauses.append("name LIKE ?")
        }
        if modality != nil { clauses.append("modality = ?") }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY name ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 1
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            sqlite3_bind_text(stmt, bindIdx, "%\(s)%", -1, SQLITE_TRANSIENT)
            bindIdx += 1
        }
        if let m = modality {
            sqlite3_bind_text(stmt, bindIdx, m, -1, SQLITE_TRANSIENT)
            bindIdx += 1
        }

        var out: [Exercise] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(decodeExercise(stmt))
        }
        return out
    }

    func exercise(id: Int) -> Exercise? {
        guard let db else { return nil }
        let sql = """
        SELECT id, name, slug, description, instructions, cues, difficulty, modality,
               environment, is_compound, is_unilateral,
               default_sets, default_reps, default_rest, default_duration,
               regression, progression
        FROM exercises WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(id))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return decodeExercise(stmt)
    }

    func modalityCounts() -> [(modality: String, count: Int)] {
        guard let db else { return [] }
        let sql = "SELECT modality, COUNT(*) FROM exercises GROUP BY modality ORDER BY 2 DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let m = text(stmt, 0) else { continue }
            out.append((m, Int(sqlite3_column_int64(stmt, 1))))
        }
        return out
    }

    private func decodeExercise(_ stmt: OpaquePointer?) -> Exercise {
        let cuesRaw = text(stmt, 5)
        let cues: [String] = cuesRaw
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] }
            ?? []
        return Exercise(
            id: Int(sqlite3_column_int64(stmt, 0)),
            name: text(stmt, 1) ?? "",
            slug: text(stmt, 2) ?? "",
            description: text(stmt, 3),
            instructions: text(stmt, 4),
            cues: cues,
            difficulty: text(stmt, 6),
            modality: text(stmt, 7),
            environment: text(stmt, 8),
            isCompound: (intOrNil(stmt, 9) ?? 0) == 1,
            isUnilateral: (intOrNil(stmt, 10) ?? 0) == 1,
            defaultSets: intOrNil(stmt, 11),
            defaultReps: text(stmt, 12),
            defaultRest: text(stmt, 13),
            defaultDuration: text(stmt, 14),
            regression: text(stmt, 15),
            progression: text(stmt, 16)
        )
    }

    func exercises(forRoutineId routineId: Int) -> [RoutineExercise] {
        guard let db else { return [] }
        let sql = """
        SELECT re.id, re.exercise_id, e.name, re.position, re.sets, re.reps, re.rest, re.notes
        FROM routine_exercises re
        JOIN exercises e ON e.id = re.exercise_id
        WHERE re.routine_id = ?
        ORDER BY re.position ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(routineId))

        var rows: [RoutineExercise] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(RoutineExercise(
                id: Int(sqlite3_column_int64(stmt, 0)),
                exerciseId: Int(sqlite3_column_int64(stmt, 1)),
                name: text(stmt, 2) ?? "",
                position: Int(sqlite3_column_int64(stmt, 3)),
                sets: intOrNil(stmt, 4),
                reps: text(stmt, 5),
                rest: text(stmt, 6),
                notes: text(stmt, 7)
            ))
        }
        return rows
    }

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    private func intOrNil(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        if sqlite3_column_type(stmt, idx) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(stmt, idx))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
