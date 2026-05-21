import Foundation
import SQLite3

final class CoachDatabase {
    static let shared = CoachDatabase()

    /// When an exercise carries this many or more rows in
    /// exercise_sport_relevance, treat it as universal foundation and keep
    /// it visible for every user regardless of their sport profile. Picked
    /// at 10 because the DB distribution puts the genuinely-cross-sport
    /// rows (Back Squat, Conventional Deadlift, Couch Stretch, Band
    /// Pull-Apart, Single-Leg Balance, etc.) at >= 10 tags, while
    /// discipline-cluster drills (capoeira/dance/ginga, HEMA cuts, iaido
    /// forms, OCR-specific carries) sit at 1-7 tags.
    static let foundationTagThreshold = 10

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
        // Open + VERIFY in a retry loop. Earlier versions trusted
        // sqlite3_open_v2's SQLITE_OK return, but per the docs the handle
        // can still be in an "indeterminate" state — opens cleanly, queries
        // come back empty. Under xcodebuild's parallel runner that produced
        // intermittent "0 exercises returned" test failures. Verifying with
        // a small SELECT before declaring init successful catches this.
        // Exponential backoff over ~3 seconds total. The simulator's
        // resource bundle is sometimes not fully readable for the first
        // few hundred ms after a fresh test-bundle install — the early
        // retries usually nail it; later ones are insurance.
        let backoffsMs: [Double] = [0, 50, 150, 400, 800, 1600]
        for delay in backoffsMs {
            if let d = db { sqlite3_close(d); db = nil }
            if delay > 0 { Thread.sleep(forTimeInterval: delay / 1000) }

            let openResult = sqlite3_open_v2(path, &db, flags, nil)
            guard openResult == SQLITE_OK, let opened = db else { continue }

            // Sanity check: a healthy bundled coach.db has hundreds of
            // exercises. Anything less than ~100 means the handle is
            // broken / the file is empty / SQLite is in a weird state.
            // Scoped block so the statement is finalized before the loop
            // potentially decides to discard the handle.
            let count: Int64 = {
                var stmt: OpaquePointer?
                let prepared = sqlite3_prepare_v2(opened, "SELECT COUNT(*) FROM exercises", -1, &stmt, nil)
                defer { sqlite3_finalize(stmt) }
                guard prepared == SQLITE_OK else { return 0 }
                guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
                return sqlite3_column_int64(stmt, 0)
            }()
            if count >= 100 { return }   // DB is healthy + readable
        }
        // All retries failed — make sure isOpen reports nil so callers fail
        // loudly rather than silently returning empty arrays.
        if let d = db { sqlite3_close(d); db = nil }
    }

    deinit { if let db { sqlite3_close(db) } }

    var isOpen: Bool { db != nil }

    func listRoutines(search: String? = nil, goal: String? = nil) -> [BundledRoutineRow] { withLock {
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

        var rows: [BundledRoutineRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(BundledRoutineRow(
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

    /// Unified search used by the new filter UI. All filter params are
    /// optional and AND-ed together. muscleSlugs / patternSlugs are slug
    /// arrays from MuscleBucket.memberSlugs / MovementCategory.memberPatternSlugs
    /// — they expand to EXISTS subqueries that match if ANY member slug hits
    /// (within a bucket, the slugs are OR-ed; the bucket itself is AND-ed
    /// with other filters).
    func listExercises(
        search: String? = nil,
        muscleSlugs: [String] = [],
        patternSlugs: [String] = [],
        modality: String? = nil,
        difficulty: String? = nil,
        environment: String? = nil,
        compoundOnly: Bool? = nil,
        userSportSlugs: [String] = []
    ) -> [Exercise] { withLock {
        guard let db else { return [] }
        // When userSportSlugs is non-empty, we order by the row's best matching
        // sport relevance_score so the most-specific exercises bubble up. We
        // still UNION exercises with zero sport_relevance rows (the ~76
        // universal lifts) and rows tagged specificity='general' so the user
        // never loses bench/squat/deadlift behind a niche-filter wall. The
        // `bestRel` subquery returns the highest matching relevance (or 0
        // for the foundation rows so they sort after specific matches but
        // remain visible).
        let useSportRank = !userSportSlugs.isEmpty
        let sportSelect = useSportRank
            ? """
              ,
              COALESCE((
                SELECT MAX(esr.relevance_score)
                FROM exercise_sport_relevance esr
                JOIN sport_categories sc ON sc.id = esr.sport_id
                WHERE esr.exercise_id = e.id
                  AND sc.slug IN (\(userSportSlugs.map { _ in "?" }.joined(separator: ",")))
              ), 0.0) AS best_rel
              """
            : ""
        var sql = """
        SELECT e.id, e.name, e.slug, e.description, e.instructions, e.cues, e.difficulty, e.modality,
               e.environment, e.is_compound, e.is_unilateral,
               e.default_sets, e.default_reps, e.default_rest, e.default_duration,
               e.regression, e.progression, e.image_url, e.thumbnail_url,
               e.video_url, e.source_video_attribution\(sportSelect)
        FROM exercises e
        """
        // Build the WHERE clauses + a parallel ordered list of bound values
        // (strings or ints) so we can apply them after sqlite3_prepare_v2 in
        // a single loop. Each entry corresponds to one `?` placeholder.
        enum Bind { case str(String), int(Int32) }
        var clauses: [String] = []
        var binds: [Bind] = []

        // SELECT-list placeholders come first (before WHERE) — the bestRel
        // subquery has one `?` per user sport slug.
        if useSportRank {
            for slug in userSportSlugs { binds.append(.str(slug)) }
        }

        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            clauses.append("e.name LIKE ?")
            binds.append(.str("%\(s)%"))
        }
        if let m = modality {
            clauses.append("e.modality = ?")
            binds.append(.str(m))
        }
        if let d = difficulty {
            clauses.append("e.difficulty = ?")
            binds.append(.str(d))
        }
        if let env = environment {
            clauses.append("e.environment = ?")
            binds.append(.str(env))
        }
        if let compound = compoundOnly {
            clauses.append("e.is_compound = ?")
            binds.append(.int(compound ? 1 : 0))
        }
        if !muscleSlugs.isEmpty {
            // Primary OR secondary role both count — a "Chest" filter should
            // return bench press (chest=primary) and overhead press (chest=
            // secondary). Stabilizer is excluded — too tenuous for a
            // user-facing "this exercise targets X" claim.
            let placeholders = muscleSlugs.map { _ in "?" }.joined(separator: ",")
            clauses.append("""
            EXISTS (
                SELECT 1 FROM exercise_muscles em
                JOIN muscle_groups mg ON mg.id = em.muscle_group_id
                WHERE em.exercise_id = e.id
                  AND em.role IN ('primary','secondary')
                  AND mg.slug IN (\(placeholders))
            )
            """)
            for slug in muscleSlugs { binds.append(.str(slug)) }
        }
        if !patternSlugs.isEmpty {
            let placeholders = patternSlugs.map { _ in "?" }.joined(separator: ",")
            clauses.append("""
            EXISTS (
                SELECT 1 FROM exercise_movement_patterns emp
                JOIN movement_patterns mp ON mp.id = emp.movement_pattern_id
                WHERE emp.exercise_id = e.id
                  AND mp.slug IN (\(placeholders))
            )
            """)
            for slug in patternSlugs { binds.append(.str(slug)) }
        }
        if useSportRank {
            // Visibility rules (foundation always visible, niche hidden):
            //   (a) rows with at least one exercise_sport_relevance row
            //       targeting one of the user's sports — visible, ranked
            //       by best_rel.
            //   (b) rows with NO exercise_sport_relevance rows at all — the
            //       ~76 explicitly-untagged foundation lifts.
            //   (c) rows tagged for >= FOUNDATION_TAG_THRESHOLD distinct
            //       sports — treated as foundation even though they have
            //       tags, because the data was tagged unevenly (e.g. Back
            //       Squat has 18 sport tags but tennis isn't one of them,
            //       and we want it visible for tennis users anyway).
            // Cross-sport 'general' rows with a small tag count (e.g. a
            // capoeira drill tagged general for kung-fu/dance only) stay
            // hidden — they're discipline-foundation, not universal.
            let placeholders = userSportSlugs.map { _ in "?" }.joined(separator: ",")
            clauses.append("""
            (
              EXISTS (
                SELECT 1 FROM exercise_sport_relevance esr
                JOIN sport_categories sc ON sc.id = esr.sport_id
                WHERE esr.exercise_id = e.id
                  AND sc.slug IN (\(placeholders))
              )
              OR NOT EXISTS (
                SELECT 1 FROM exercise_sport_relevance esr2
                WHERE esr2.exercise_id = e.id
              )
              OR (
                SELECT COUNT(*) FROM exercise_sport_relevance esr3
                WHERE esr3.exercise_id = e.id
              ) >= \(Self.foundationTagThreshold)
            )
            """)
            for slug in userSportSlugs { binds.append(.str(slug)) }
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        if useSportRank {
            sql += " ORDER BY best_rel DESC, e.name ASC"
        } else {
            sql += " ORDER BY e.name ASC"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch b {
            case .str(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int(stmt, idx, n)
            }
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
        decodeExerciseStartingAt(stmt, offset: 0)
    }

    /// Same as `decodeExercise` but tolerant of leading columns from joined
    /// queries — caller passes the offset where the 21-column `exercises.*`
    /// projection starts. Used by injury-relevance queries that prefix the
    /// projection with `common_injuries.slug`.
    fileprivate func decodeExerciseStartingAt(_ stmt: OpaquePointer?, offset: Int32) -> Exercise {
        let cuesRaw = text(stmt, offset + 5)
        let cues: [String] = cuesRaw
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] }
            ?? []
        return Exercise(
            id: Int(sqlite3_column_int64(stmt, offset + 0)),
            name: text(stmt, offset + 1) ?? "",
            slug: text(stmt, offset + 2) ?? "",
            description: text(stmt, offset + 3),
            instructions: text(stmt, offset + 4),
            cues: cues,
            difficulty: text(stmt, offset + 6),
            modality: text(stmt, offset + 7),
            environment: text(stmt, offset + 8),
            isCompound: (intOrNil(stmt, offset + 9) ?? 0) == 1,
            isUnilateral: (intOrNil(stmt, offset + 10) ?? 0) == 1,
            defaultSets: intOrNil(stmt, offset + 11),
            defaultReps: text(stmt, offset + 12),
            defaultRest: text(stmt, offset + 13),
            defaultDuration: text(stmt, offset + 14),
            regression: text(stmt, offset + 15),
            progression: text(stmt, offset + 16),
            imageURL: text(stmt, offset + 17),
            thumbnailURL: text(stmt, offset + 18),
            videoURL: text(stmt, offset + 19),
            sourceVideoAttribution: text(stmt, offset + 20)
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
        modalities: Set<String> = [],
        userSportSlugs: [String] = []
    ) -> [Exercise] { withLock {
        guard let db else { return [] }
        // Sport filter mirrors listExercises: keep matching-sport rows AND
        // specificity='general' AND no-sport-relevance rows (foundation lifts).
        // Generator path doesn't need a relevance_score rank — variety logic
        // handles picking — so this is a pure inclusion filter.
        let sportClause: String
        if userSportSlugs.isEmpty {
            sportClause = ""
        } else {
            // Same two-bucket policy as listExercises: keep matching-sport
            // rows + zero-relevance foundation lifts. Cross-sport 'general'
            // rows stay hidden — they're discipline-foundation, not universal.
            let placeholders = userSportSlugs.map { _ in "?" }.joined(separator: ",")
            sportClause = """
              AND (
                EXISTS (
                  SELECT 1 FROM exercise_sport_relevance esr
                  JOIN sport_categories sc ON sc.id = esr.sport_id
                  WHERE esr.exercise_id = e.id
                    AND sc.slug IN (\(placeholders))
                )
                OR NOT EXISTS (
                  SELECT 1 FROM exercise_sport_relevance esr2
                  WHERE esr2.exercise_id = e.id
                )
              )
            """
        }
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
        WHERE mp.slug = ?\(sportClause)
        ORDER BY e.name ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        for (i, slug) in userSportSlugs.enumerated() {
            sqlite3_bind_text(stmt, Int32(2 + i), slug, -1, SQLITE_TRANSIENT)
        }

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

    /// Same data as `contraindicatedExerciseIds` but bucketed per slug — the
    /// CoachContext snapshot uses this to write "INJURY FILTERS — ACL: Back
    /// Squat, Front Squat, ..." per-injury lines instead of a flat union. Slugs
    /// with zero rows in the join are omitted; callers can detect "no
    /// contraindications" by checking presence.
    func contraindicatedExerciseIds(bySlug slugs: Set<String>) -> [String: Set<Int>] { withLock {
        guard !slugs.isEmpty, let db else { return [:] }
        let placeholders = slugs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT ci.slug, eir.exercise_id
        FROM exercise_injury_relevance eir
        JOIN common_injuries ci ON ci.id = eir.injury_id
        WHERE eir.role = 'contraindicated'
          AND ci.slug IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        for (i, slug) in slugs.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), slug, -1, SQLITE_TRANSIENT)
        }
        var out: [String: Set<Int>] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let slug = text(stmt, 0) ?? ""
            let exId = Int(sqlite3_column_int64(stmt, 1))
            guard !slug.isEmpty else { continue }
            out[slug, default: []].insert(exId)
        }
        return out
    } }

    /// Exercises tagged with the given role(s) for any of the given injury
    /// slugs, bucketed per slug. Used to build the prehab pool — for each
    /// injury the user has, the generator picks one of these on mobility
    /// days, and the CoachContext lists them as suggested alternatives. Roles
    /// of interest: "prehab" (stay-healthy) and "rehab_late" (you've healed
    /// enough to load it). "rehab_early" is too sensitive to recommend
    /// generically and stays out.
    func exercises(forInjurySlugs slugs: Set<String>,
                   roles: Set<String>) -> [String: [Exercise]] { withLock {
        guard !slugs.isEmpty, !roles.isEmpty, let db else { return [:] }
        let slugPlaceholders = slugs.map { _ in "?" }.joined(separator: ",")
        let rolePlaceholders = roles.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT ci.slug,
               e.id, e.name, e.slug, e.description, e.instructions,
               e.cues, e.difficulty, e.modality, e.environment,
               e.is_compound, e.is_unilateral,
               e.default_sets, e.default_reps, e.default_rest, e.default_duration,
               e.regression, e.progression, e.image_url, e.thumbnail_url,
               e.video_url, e.source_video_attribution
        FROM exercise_injury_relevance eir
        JOIN common_injuries ci ON ci.id = eir.injury_id
        JOIN exercises e ON e.id = eir.exercise_id
        WHERE ci.slug IN (\(slugPlaceholders))
          AND eir.role IN (\(rolePlaceholders))
        ORDER BY ci.slug ASC, e.name ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var bindIdx: Int32 = 1
        for slug in slugs {
            sqlite3_bind_text(stmt, bindIdx, slug, -1, SQLITE_TRANSIENT)
            bindIdx += 1
        }
        for role in roles {
            sqlite3_bind_text(stmt, bindIdx, role, -1, SQLITE_TRANSIENT)
            bindIdx += 1
        }
        var out: [String: [Exercise]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let slug = text(stmt, 0) ?? ""
            guard !slug.isEmpty else { continue }
            // Decode shares the same column layout as decodeExercise(stmt) but
            // we offset by 1 because column 0 is the slug.
            let ex = decodeExerciseStartingAt(stmt, offset: 1)
            out[slug, default: []].append(ex)
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
        SELECT re.id, re.exercise_id, e.name, re.position, re.sets, re.reps, re.rest, re.notes, re.superset_group
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
                notes: text(stmt, 7),
                supersetGroup: intOrNil(stmt, 8)
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
