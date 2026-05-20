import Foundation
import SQLite3

final class CoachDatabase {
    static let shared = CoachDatabase()

    private var db: OpaquePointer?

    /// Serializes ALL public reads on this singleton. SQLite is opened with
    /// FULLMUTEX so per-statement access is already safe at the C level —
    /// this lock exists at the Swift level so any Swift-side mutable state
    /// we add to this class in the future (caches, counters, etc.) is also
    /// safe under xcodebuild's parallel test runner.
    ///
    /// Recursive so methods can call each other (e.g. `adjacentByDifficulty`
    /// calls `exercise(id:)`) without deadlocking. Every public method must
    /// `lock.lock()` on entry + `defer lock.unlock()`. The
    /// `CoachDatabaseConcurrencyTests` guards regressions against this rule.
    private let lock = NSRecursiveLock()

    /// Lock-helper used by every public read method. Keeping it inline as a
    /// generic means the call site is one line: `withLock { ... }`.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private init() {
        guard let path = Bundle.main.path(forResource: "coach", ofType: "db") else { return }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        // Open with a small retry loop. The actual root cause of the
        // intermittent "0 exercises returned" test failures under
        // xcodebuild's parallel runner was sqlite3_open_v2 leaving `db` in
        // SQLite's "indeterminate" state on transient failure (per the docs
        // the handle is non-null but unusable, so `isOpen` reported true
        // and every query came back empty). Three retries with a tiny
        // back-off + nil-on-failure makes the bad state observable.
        var lastResult: Int32 = SQLITE_OK
        for attempt in 0..<3 {
            if attempt > 0 {
                // Discard the indeterminate handle before retrying.
                if let d = db { sqlite3_close(d); db = nil }
                Thread.sleep(forTimeInterval: 0.01 * Double(attempt))
            }
            lastResult = sqlite3_open_v2(path, &db, flags, nil)
            if lastResult == SQLITE_OK { return }
        }
        // Final failure — make sure isOpen reports nil so callers fail loudly
        // rather than silently returning empty arrays.
        if let d = db { sqlite3_close(d); db = nil }
    }

    deinit { if let db { sqlite3_close(db) } }

    var isOpen: Bool { db != nil }

    func listRoutines(search: String? = nil, goal: String? = nil) -> [Routine] { withLock {
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
        if goal != nil {
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
    } }

    func goalCounts() -> [(goal: String, count: Int)] { withLock {
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
    } }

    func listExercises(search: String? = nil, modality: String? = nil) -> [Exercise] { withLock {
        guard let db else { return [] }
        var sql = """
        SELECT id, name, slug, description, instructions, cues, difficulty, modality,
               environment, is_compound, is_unilateral,
               default_sets, default_reps, default_rest, default_duration,
               regression, progression, image_url, thumbnail_url,
               video_url, source_video_attribution
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
    } }

    func exercise(id: Int) -> Exercise? { withLock {
        guard let db else { return nil }
        let sql = """
        SELECT id, name, slug, description, instructions, cues, difficulty, modality,
               environment, is_compound, is_unilateral,
               default_sets, default_reps, default_rest, default_duration,
               regression, progression, image_url, thumbnail_url,
               video_url, source_video_attribution
        FROM exercises WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(id))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return decodeExercise(stmt)
    } }

    func modalityCounts() -> [(modality: String, count: Int)] { withLock {
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
    } }

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
            progression: text(stmt, 16),
            imageURL: text(stmt, 17),
            thumbnailURL: text(stmt, 18),
            videoURL: text(stmt, 19),
            sourceVideoAttribution: text(stmt, 20)
        )
    }

    /// Pre-curated substitutes for an exercise from the `exercise_substitutions`
    /// table. Aggregated across all context tags (lower_intensity, home_friendly,
    /// equipment_swap, etc.) so the caller gets a single ranked list. Score is
    /// the MAX similarity across rows for the same substitute_id; contexts are
    /// merged + deduped.
    func substitutes(forExerciseId exerciseId: Int) -> [ExerciseSubstitute] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT s.substitute_id, s.context, s.similarity_score, s.notes,
               e.id, e.name, e.slug, e.description, e.instructions, e.cues, e.difficulty, e.modality,
               e.environment, e.is_compound, e.is_unilateral,
               e.default_sets, e.default_reps, e.default_rest, e.default_duration,
               e.regression, e.progression, e.image_url, e.thumbnail_url,
               e.video_url, e.source_video_attribution
        FROM exercise_substitutions s
        JOIN exercises e ON e.id = s.substitute_id
        WHERE s.exercise_id = ?
        ORDER BY s.similarity_score DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(exerciseId))

        // Bucket per substitute id; one ExerciseSubstitute aggregates contexts.
        var indexFor: [Int: Int] = [:]
        var out: [ExerciseSubstitute] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let subId = Int(sqlite3_column_int64(stmt, 0))
            let context = text(stmt, 1) ?? ""
            let score = sqlite3_column_double(stmt, 2)
            let notes = text(stmt, 3)
            // exercise columns shift by +4
            let exStmt = stmt
            let exercise = Exercise(
                id: Int(sqlite3_column_int64(exStmt, 4)),
                name: text(exStmt, 5) ?? "",
                slug: text(exStmt, 6) ?? "",
                description: text(exStmt, 7),
                instructions: text(exStmt, 8),
                cues: {
                    let raw = text(exStmt, 9)
                    return raw
                        .flatMap { $0.data(using: .utf8) }
                        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] }
                        ?? []
                }(),
                difficulty: text(exStmt, 10),
                modality: text(exStmt, 11),
                environment: text(exStmt, 12),
                isCompound: (intOrNil(exStmt, 13) ?? 0) == 1,
                isUnilateral: (intOrNil(exStmt, 14) ?? 0) == 1,
                defaultSets: intOrNil(exStmt, 15),
                defaultReps: text(exStmt, 16),
                defaultRest: text(exStmt, 17),
                defaultDuration: text(exStmt, 18),
                regression: text(exStmt, 19),
                progression: text(exStmt, 20),
                imageURL: text(exStmt, 21),
                thumbnailURL: text(exStmt, 22),
                videoURL: text(exStmt, 23),
                sourceVideoAttribution: text(exStmt, 24)
            )
            if let i = indexFor[subId] {
                if !out[i].contexts.contains(context) { out[i].contexts.append(context) }
                if score > out[i].score { out[i].score = score }
                if out[i].notes == nil, let n = notes { out[i].notes = n }
            } else {
                indexFor[subId] = out.count
                out.append(ExerciseSubstitute(
                    exercise: exercise,
                    contexts: [context],
                    score: score,
                    notes: notes
                ))
            }
        }
        return out.sorted { $0.score > $1.score }
    } }

    /// Exercises that hit a given movement pattern (movement_patterns.slug),
    /// post-filtered in Swift by difficulty / environment / name-keyword
    /// excludes / id excludes. Used by WorkoutGenerator.
    func exercises(
        matchingPattern pattern: String,
        difficulties: Set<String> = [],
        environments: Set<String> = [],
        excludeKeywords: [String] = [],
        excludeIds: Set<Int> = [],
        modalities: Set<String> = []
    ) -> [Exercise] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT DISTINCT e.id, e.name, e.slug, e.description, e.instructions,
               e.cues, e.difficulty, e.modality, e.environment,
               e.is_compound, e.is_unilateral,
               e.default_sets, e.default_reps, e.default_rest, e.default_duration,
               e.regression, e.progression, e.image_url, e.thumbnail_url,
               e.video_url, e.source_video_attribution
        FROM exercises e
        JOIN exercise_movement_patterns emp ON emp.exercise_id = e.id
        JOIN movement_patterns mp ON mp.id = emp.movement_pattern_id
        WHERE mp.slug = ?
        ORDER BY e.name ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)

        var raw: [Exercise] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            raw.append(decodeExercise(stmt))
        }

        let lowerExcludes = excludeKeywords.map { $0.lowercased() }
        return raw.filter { ex in
            if excludeIds.contains(ex.id) { return false }
            if !difficulties.isEmpty {
                guard let d = ex.difficulty, difficulties.contains(d) else { return false }
            }
            if !environments.isEmpty {
                if let env = ex.environment, !env.isEmpty, !environments.contains(env) {
                    return false
                }
            }
            if !modalities.isEmpty {
                guard let m = ex.modality, modalities.contains(m) else { return false }
            }
            if !lowerExcludes.isEmpty {
                let lowerName = ex.name.lowercased()
                if lowerExcludes.contains(where: { lowerName.contains($0) }) {
                    return false
                }
            }
            return true
        }
    } }

    // MARK: - Injuries

    /// 56 common injuries grouped by body region. Used by the Profile screen's
    /// injury picker and by DemographicProfile to look up contraindications.
    func listInjuries() -> [CommonInjury] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT id, name, slug, body_region, description
        FROM common_injuries
        ORDER BY body_region ASC, name ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [CommonInjury] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(CommonInjury(
                id: Int(sqlite3_column_int64(stmt, 0)),
                name: text(stmt, 1) ?? "",
                slug: text(stmt, 2) ?? "",
                bodyRegion: text(stmt, 3),
                description: text(stmt, 4)
            ))
        }
        return out
    } }

    /// Exercise ids explicitly tagged 'contraindicated' for any of the given
    /// injury slugs. Prehab / rehab roles are NOT included — those are often
    /// the right exercises for the injury and the planner should be free to
    /// pick them. The generator unions this set with its in-workout dedup
    /// before querying candidates.
    func contraindicatedExerciseIds(forInjurySlugs slugs: Set<String>) -> Set<Int> { withLock {
        guard !slugs.isEmpty, let db else { return [] }
        let placeholders = slugs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT DISTINCT eir.exercise_id
        FROM exercise_injury_relevance eir
        JOIN common_injuries ci ON ci.id = eir.injury_id
        WHERE eir.role = 'contraindicated'
          AND ci.slug IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, slug) in slugs.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), slug, -1, SQLITE_TRANSIENT)
        }
        var out: Set<Int> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.insert(Int(sqlite3_column_int64(stmt, 0)))
        }
        return out
    } }

    /// Look up the muscle groups an exercise targets. Used by the Progress
    /// muscle-balance card and the coach context to allocate logged volume
    /// to body areas. Returns (slug, role, label) tuples — slug is
    /// `muscle_groups.slug`, role is one of "primary" | "secondary" |
    /// "stabilizer" per the schema, label is the display name.
    func musclesForExercise(_ exerciseId: Int) -> [(slug: String, role: String, label: String)] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT mg.slug, em.role, mg.name
        FROM exercise_muscles em
        JOIN muscle_groups mg ON mg.id = em.muscle_group_id
        WHERE em.exercise_id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(exerciseId))

        var rows: [(String, String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let slug = text(stmt, 0) ?? ""
            let role = text(stmt, 1) ?? ""
            let label = text(stmt, 2) ?? slug.replacingOccurrences(of: "_", with: " ").capitalized
            if !slug.isEmpty, !role.isEmpty { rows.append((slug, role, label)) }
        }
        return rows
    } }

    /// Look up the movement-pattern slugs an exercise satisfies. Used by the
    /// coach context's PATTERN FREQUENCY section to flag which canonical
    /// lifting patterns the user has (and hasn't) trained in the last N
    /// weeks. Same JOIN-in-SQL pattern as musclesForExercise so we don't
    /// have to do a second lookup per row.
    func patternsForExercise(_ exerciseId: Int) -> [String] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT mp.slug
        FROM exercise_movement_patterns emp
        JOIN movement_patterns mp ON mp.id = emp.movement_pattern_id
        WHERE emp.exercise_id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(exerciseId))

        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let slug = text(stmt, 0), !slug.isEmpty { out.append(slug) }
        }
        return out
    } }

    /// Adjacent peers along the difficulty axis within the same movement
    /// pattern(s). Returns one easier and one harder pick if available — the
    /// alphabetically-first peer at the nearest difficulty tier (beginner →
    /// intermediate → advanced → elite). Drives the Exercise detail sheet's
    /// progression-chain navigation.
    ///
    /// Calls `exercise(id:)` internally — this is why `withLock` uses an
    /// NSRecursiveLock and not a non-reentrant DispatchQueue.
    func adjacentByDifficulty(forExerciseId exerciseId: Int) -> (easier: Exercise?, harder: Exercise?) { withLock {
        guard let db, let current = exercise(id: exerciseId),
              let currentRank = difficultyRank(current.difficulty) else {
            return (nil, nil)
        }

        let sql = """
        SELECT DISTINCT e.id, e.name, e.slug, e.description, e.instructions, e.cues,
               e.difficulty, e.modality, e.environment, e.is_compound, e.is_unilateral,
               e.default_sets, e.default_reps, e.default_rest, e.default_duration,
               e.regression, e.progression, e.image_url, e.thumbnail_url,
               e.video_url, e.source_video_attribution
        FROM exercises e
        JOIN exercise_movement_patterns emp ON emp.exercise_id = e.id
        WHERE e.id != ?
          AND emp.movement_pattern_id IN (
            SELECT movement_pattern_id FROM exercise_movement_patterns
            WHERE exercise_id = ?
          )
        ORDER BY e.name ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(exerciseId))
        sqlite3_bind_int64(stmt, 2, Int64(exerciseId))

        var peers: [Exercise] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            peers.append(decodeExercise(stmt))
        }

        let easierCandidates = peers.compactMap { ex -> (rank: Int, ex: Exercise)? in
            guard let r = difficultyRank(ex.difficulty), r < currentRank else { return nil }
            return (r, ex)
        }
        let easier = nameMatch(in: easierCandidates.map(\.ex), against: current.regression)
            ?? easierCandidates.sorted { a, b in
                a.rank != b.rank ? a.rank > b.rank : a.ex.name < b.ex.name
            }.first?.ex

        let harderCandidates = peers.compactMap { ex -> (rank: Int, ex: Exercise)? in
            guard let r = difficultyRank(ex.difficulty), r > currentRank else { return nil }
            return (r, ex)
        }
        let harder = nameMatch(in: harderCandidates.map(\.ex), against: current.progression)
            ?? harderCandidates.sorted { a, b in
                a.rank != b.rank ? a.rank < b.rank : a.ex.name < b.ex.name
            }.first?.ex

        return (easier, harder)
    } }

    /// Free-text fallback for adjacentByDifficulty: when the current
    /// exercise's regression/progression text mentions a peer by name
    /// (substring match, ≥5 chars to avoid noise), use that peer instead of
    /// the alphabetical-first pick. Caller has already filtered to the
    /// correct difficulty tier so we don't break the easier/harder invariant.
    private func nameMatch(in peers: [Exercise], against text: String?) -> Exercise? {
        guard let text = text?.lowercased(), !text.isEmpty else { return nil }
        let matches = peers.filter { peer in
            let name = peer.name.lowercased()
            return name.count >= 5 && text.contains(name)
        }
        return matches.max { $0.name.count < $1.name.count }
    }

    private func difficultyRank(_ d: String?) -> Int? {
        switch d?.lowercased() {
        case "beginner":     return 1
        case "intermediate": return 2
        case "advanced":     return 3
        case "elite":        return 4
        default:             return nil
        }
    }

    func exercises(forRoutineId routineId: Int) -> [RoutineExercise] { withLock {
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
    } }

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
