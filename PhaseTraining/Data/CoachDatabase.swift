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

    // MARK: - Search normalization & fuzzy matching

    /// Separator characters stripped from BOTH the catalog name and the
    /// user's query before substring matching, so harmless punctuation
    /// "typos" don't hide results: typing "pull up" (or "pullup") still
    /// finds "Pull-Up", "farmers walk" finds "Farmer's Walk", etc. Order
    /// doesn't matter — each is removed independently from both sides.
    /// Straight + curly apostrophes are both listed because the catalog
    /// mixes them. Also used as the token boundary for fuzzy matching.
    static let searchSeparators: [Character] = [" ", "-", "'", "\u{2019}", "."]

    /// Swift-side mirror of `nameNormalizeSQL`: collapse a free-text query to
    /// its separator-free form so the bound LIKE pattern lines up with the
    /// normalized column expression. Lowercasing isn't needed — SQLite LIKE
    /// is ASCII-case-insensitive — but stripping the separators here is.
    static func normalizeSearchTerm(_ raw: String) -> String {
        var out = raw
        for sep in searchSeparators {
            out = out.replacingOccurrences(of: String(sep), with: "")
        }
        return out
    }

    /// SQL expression that strips `searchSeparators` from a name column so it
    /// can be LIKE-matched against a `normalizeSearchTerm`-ed query. Nested
    /// REPLACE() — one layer per separator. Single quotes are escaped by
    /// doubling per SQL string-literal rules.
    private static func nameNormalizeSQL(_ column: String) -> String {
        var expr = column
        for sep in searchSeparators {
            let literal = sep == "'" ? "''" : String(sep)
            expr = "REPLACE(\(expr), '\(literal)', '')"
        }
        return expr
    }

    /// Lowercase + split on `searchSeparators` (and any whitespace), dropping
    /// empties. Tokenizing on these keeps "Pull-Up", "pull up", and "pull,up"
    /// all yielding [pull, up], so the fuzzy matcher compares word-by-word.
    static func searchTokens(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { searchSeparators.contains($0) || $0.isWhitespace })
            .map(String.init)
    }

    /// Per-token edit-distance budget, scaled by how much the user typed.
    /// Short tokens get zero slack (too ambiguous — "rw" shouldn't match
    /// "row"); longer tokens absorb one or two typos. OSA counts an adjacent
    /// transposition as a single edit, so 2 covers most fat-finger cases.
    private static func fuzzyTolerance(forTokenLength len: Int) -> Int {
        switch len {
        case ..<3: return 0
        case 3...5: return 1
        default: return 2
        }
    }

    /// Optimal String Alignment distance (Damerau-Levenshtein restricted so
    /// no substring is edited twice). Counts an adjacent transposition as a
    /// single edit, so "benhc"→"bench" and "deadlfit"→"deadlift" are distance
    /// 1 — the dominant real-world typo. Takes Character arrays the caller
    /// already built, to avoid repeatedly re-indexing String.
    static func osaDistance(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var d = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { d[i][0] = i }
        for j in 0...n { d[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(d[i - 1][j] + 1,          // deletion
                            d[i][j - 1] + 1,          // insertion
                            d[i - 1][j - 1] + cost)   // substitution
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, d[i - 2][j - 2] + 1)   // adjacent transposition
                }
                d[i][j] = v
            }
        }
        return d[m][n]
    }

    /// Total edit-distance score for matching every token of `query` against
    /// the closest token of `name`, or nil if any query token has no name
    /// token within tolerance. Lower = closer. Order-independent (so "press
    /// bench" still finds "Bench Press"), unlike the contiguous substring
    /// path. Only meaningful as a zero-result fallback — see `fuzzyMatches`.
    static func fuzzyNameScore(query: String, name: String) -> Int? {
        let qTokens = searchTokens(query)
        guard !qTokens.isEmpty else { return nil }
        let nTokens = searchTokens(name)
        guard !nTokens.isEmpty else { return nil }
        let nChars = nTokens.map(Array.init)
        var total = 0
        for q in qTokens {
            let tol = fuzzyTolerance(forTokenLength: q.count)
            let qChars = Array(q)
            var best = Int.max
            for (k, n) in nTokens.enumerated() {
                // Length-gate: tokens differing in length by more than the
                // tolerance can't possibly be within it — skip the DP.
                if abs(n.count - q.count) > tol { continue }
                let dist = osaDistance(qChars, nChars[k])
                if dist < best { best = dist; if best == 0 { break } }
            }
            guard best <= tol else { return nil }
            total += best
        }
        return total
    }

    /// Rank `candidates` by how close their names are to a (possibly typo'd)
    /// `query`, keeping only those within per-token edit-distance tolerance.
    /// Best-first; empty if nothing is close enough. Used purely as a fallback
    /// when the substring search found nothing, so it can only add results a
    /// literal match missed — never reorder or hide good substring hits.
    static func fuzzyMatches(in candidates: [Exercise], query: String) -> [Exercise] {
        candidates
            .compactMap { ex -> (ex: Exercise, score: Int)? in
                guard let score = fuzzyNameScore(query: query, name: ex.name) else { return nil }
                return (ex, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.ex.name.count != rhs.ex.name.count { return lhs.ex.name.count < rhs.ex.name.count }
                return lhs.ex.name < rhs.ex.name
            }
            .map(\.ex)
    }

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

    /// Total catalog size. The Library eyebrow only needs the number, and was
    /// materializing all 582 rows (21 columns each, fully decoded) to call
    /// `.count` on the array.
    func exerciseCount() -> Int { withLock {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM exercises", -1, &stmt, nil) == SQLITE_OK
        else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
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
            // Separator-insensitive: see nameNormalizeSQL / normalizeSearchTerm.
            clauses.append("\(Self.nameNormalizeSQL("name")) LIKE ?")
        }
        if modality != nil { clauses.append("modality = ?") }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY name ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 1
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            sqlite3_bind_text(stmt, bindIdx, "%\(Self.normalizeSearchTerm(s))%", -1, SQLITE_TRANSIENT)
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
            // Separator-insensitive: "pull up" / "pullup" both match "Pull-Up".
            // See nameNormalizeSQL / normalizeSearchTerm.
            clauses.append("\(Self.nameNormalizeSQL("e.name")) LIKE ?")
            binds.append(.str("%\(Self.normalizeSearchTerm(s))%"))
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

        // Fuzzy fallback: the separator-insensitive substring query found
        // nothing, but the user may have typo'd a name ("benhc press" →
        // "Bench Press", "deadlfit" → "Deadlift"). Re-run with the SAME
        // filters minus the name, then rank survivors by character-level edit
        // distance. Fires only on an otherwise-empty result, so it can only
        // rescue a dead-end search — never displace real substring matches.
        // The self-call passes search:nil (so it can't recurse back into this
        // branch); NSRecursiveLock makes re-entering withLock safe.
        if out.isEmpty, let q = search?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            let candidates = listExercises(
                search: nil,
                muscleSlugs: muscleSlugs,
                patternSlugs: patternSlugs,
                modality: modality,
                difficulty: difficulty,
                environment: environment,
                compoundOnly: compoundOnly,
                userSportSlugs: userSportSlugs
            )
            return Self.fuzzyMatches(in: candidates, query: q)
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
        userSportSlugs: [String] = [],
        allowedEquipmentSlugs: Set<String> = []
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
        // Equipment allow-list is the proper axis: per-exercise required slugs
        // (is_required = 1) joined from exercise_equipment. Fetched in one
        // batch so we don't paginate the catalog per-row. Empty allow-list =
        // no filter, preserving the pre-build-103 behaviour for full-gym
        // callers and for code paths that don't pass equipment.
        // Equipment slugs feed BOTH the allow-list filter and the equipment-
        // dislike match (T1.7), so fetch when either is active.
        let needsEquip = !allowedEquipmentSlugs.isEmpty || !lowerExcludes.isEmpty
        let requiredByExId: [Int: Set<String>] =
            needsEquip ? requiredEquipmentSlugs(forExerciseIds: Set(raw.map(\.id))) : [:]
        // slug → equipment display-name, only when there are dislikes to match.
        let equipNameBySlug: [String: String] = lowerExcludes.isEmpty ? [:] : equipmentNameBySlug()
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
                // Equipment-tag dislike (T1.7): "machine" / "cable" / "barbell"
                // rarely appear in the exercise NAME (Lying Leg Curl requires
                // leg-curl-machine), so match the dislike against each required
                // equipment's slug AND display name too.
                for slug in requiredByExId[ex.id] ?? [] {
                    let hay = slug + " " + (equipNameBySlug[slug] ?? "")
                    if lowerExcludes.contains(where: { hay.contains($0) }) {
                        return false
                    }
                }
            }
            if !allowedEquipmentSlugs.isEmpty {
                let required = requiredByExId[ex.id] ?? []
                // Exercise passes iff every required slug is in the allow-list.
                // An exercise with no required equipment passes freely.
                if !required.isSubset(of: allowedEquipmentSlugs) {
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

    /// Every muscle_groups row as (slug, name) pairs. Filters out container
    /// rollups (`full-body`, `upper-body`, `lower-body`, `arms`, `core`,
    /// `back`) — the Recovery view wants leaf muscles, not the buckets the
    /// generator uses for filtering.
    func allMuscleGroups() -> [(slug: String, name: String)] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT slug, name FROM muscle_groups
        WHERE slug NOT IN ('full-body','upper-body','lower-body','arms','core','back')
        ORDER BY name ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let slug = text(stmt, 0) ?? ""
            let name = text(stmt, 1) ?? slug
            if !slug.isEmpty { out.append((slug, name)) }
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

    // MARK: - Equipment lookups

    /// Per-exercise required equipment slugs (is_required = 1). Single-shot
    /// batch query keyed on coach.db exercise.id. Equipment that's tagged
    /// optional (is_required = 0) is intentionally excluded — an exercise
    /// that "optionally uses a mat" should not be filtered out for a user
    /// who didn't pick a mat. Empty Set in the result means "no required
    /// equipment" (pure bodyweight or unmapped) — those pass any filter.
    func requiredEquipmentSlugs(forExerciseIds ids: Set<Int>) -> [Int: Set<String>] { withLock {
        guard !ids.isEmpty, let db else { return [:] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT ee.exercise_id, eq.slug
        FROM exercise_equipment ee
        JOIN equipment eq ON eq.id = ee.equipment_id
        WHERE ee.exercise_id IN (\(placeholders))
          AND ee.is_required = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in ids.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), Int64(id))
        }
        var result: [Int: Set<String>] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let exId = Int(sqlite3_column_int64(stmt, 0))
            let slug = text(stmt, 1) ?? ""
            result[exId, default: []].insert(slug)
        }
        return result
    } }

    /// slug → lowercased display name for every equipment row (~97). Lets the
    /// exclude filter match an equipment dislike ("machine", "cable") against
    /// the equipment NAME too, not just the slug — "Lying Leg Curl" requires
    /// `leg-curl-machine` (caught by slug), while "Pec Deck Machine" hides
    /// "machine" only in its display name (caught by name). (T1.7)
    func equipmentNameBySlug() -> [String: String] { withLock {
        guard let db else { return [:] }
        var out: [String: String] = [:]
        let sql = "SELECT slug, name FROM equipment"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let slug = text(stmt, 0) else { continue }
            out[slug] = (text(stmt, 1) ?? "").lowercased()
        }
        return out
    } }

    /// Equipment category per exercise id — composes the modality / rep
    /// metadata with the required-equipment slugs and runs the shared
    /// `EquipmentCategory.classify` rules. The template builders use this to
    /// pick the LogScreen weight unit (`.repsOnly` → bodyweight, hides the
    /// weight input). Unmapped ids fall through to `.repsOnly`, matching the
    /// classifier's "no equipment = bodyweight" default.
    func equipmentCategory(forExerciseIds ids: Set<Int>) -> [Int: EquipmentCategory] {
        guard !ids.isEmpty else { return [:] }
        // Two separately-locked reads, then classify outside the lock so we
        // never re-enter `withLock`.
        let meta = exerciseLoggingMeta(forExerciseIds: ids)
        let equip = requiredEquipmentSlugs(forExerciseIds: ids)
        var out: [Int: EquipmentCategory] = [:]
        for id in ids {
            let m = meta[id]
            out[id] = EquipmentCategory.classify(
                modality: m?.modality,
                defaultReps: m?.defaultReps,
                defaultDuration: m?.defaultDuration,
                equipmentSlugs: Array(equip[id] ?? [])
            )
        }
        return out
    }

    /// Batched modality / rep / duration lookup feeding `equipmentCategory`.
    private func exerciseLoggingMeta(
        forExerciseIds ids: Set<Int>
    ) -> [Int: (modality: String?, defaultReps: String?, defaultDuration: String?)] { withLock {
        guard !ids.isEmpty, let db else { return [:] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT id, modality, default_reps, default_duration FROM exercises WHERE id IN (\(placeholders))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        for (i, id) in ids.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), Int64(id))
        }
        var out: [Int: (modality: String?, defaultReps: String?, defaultDuration: String?)] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let exId = Int(sqlite3_column_int64(stmt, 0))
            out[exId] = (text(stmt, 1), text(stmt, 2), text(stmt, 3))
        }
        return out
    } }

    /// Union of required equipment slugs across every exercise in a bundled
    /// routine. Used to vet a routine before recommending it to a user with
    /// a constrained equipment set.
    func requiredEquipmentSlugs(forRoutineId routineId: Int) -> Set<String> { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT DISTINCT eq.slug
        FROM routine_exercises re
        JOIN exercise_equipment ee ON ee.exercise_id = re.exercise_id
        JOIN equipment eq ON eq.id = ee.equipment_id
        WHERE re.routine_id = ?
          AND ee.is_required = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(routineId))
        var result: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let slug = text(stmt, 0) { result.insert(slug) }
        }
        return result
    } }

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

    /// Phase 2 — full-session authored routine ids for a sport + coach.db
    /// phase labels, ordered by id (deterministic). Excludes short add-ons
    /// (prehab / mobility / warm-up / rehab / recovery) and anything under
    /// 25 min, so a lift day is never served a 10-minute prehab block as its
    /// whole session. Consumed by `AuthoredRoutineSelector`.
    func authoredRoutineIds(sportSlug: String, phaseLabels: [String]) -> [Int] { withLock {
        guard let db, !phaseLabels.isEmpty else { return [] }
        let phasePlaceholders = phaseLabels.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT DISTINCT r.id
        FROM routines r
        JOIN routine_sports rs ON rs.routine_id = r.id
        JOIN sport_categories s ON s.id = rs.sport_id
        WHERE s.slug = ?
          AND r.phase IN (\(phasePlaceholders))
          AND r.goal NOT IN ('prehab','mobility','warm_up','pt_rehab','recovery')
          AND COALESCE(r.duration_minutes, 0) >= 25
          -- A routine is served VERBATIM as a day's workout, so it has to be
          -- a session. AuthoredRoutine.workout only rejected the empty case,
          -- and 5 routines clear every other filter here with one or two
          -- exercises. 3 is the season engine's own documented movement floor
          -- (targetMovementCount's `max(3, ...)`). Measured before landing:
          -- every plannable sport keeps at least 2 qualifying routines and
          -- general-fitness keeps its Easy Strength last resort, so no sport
          -- loses plannability.
          AND (SELECT COUNT(*) FROM routine_exercises re WHERE re.routine_id = r.id) >= 3
        ORDER BY r.id ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sportSlug, -1, SQLITE_TRANSIENT)
        for (i, label) in phaseLabels.enumerated() {
            sqlite3_bind_text(stmt, Int32(2 + i), label, -1, SQLITE_TRANSIENT)
        }
        var ids: [Int] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(Int(sqlite3_column_int64(stmt, 0)))
        }
        return ids
    } }

    /// Name + source attribution for a routine, for the authored workout's
    /// title + provenance line. nil when the id isn't a real routine.
    func authoredRoutineMeta(id: Int) -> (name: String, source: String?)? { withLock {
        guard let db else { return nil }
        let sql = "SELECT name, source_name FROM routines WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(id))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return (text(stmt, 0) ?? "Session", text(stmt, 1))
    } }

    /// Season-aware generator pool: every `sport_movements` row for a sport,
    /// joined with its catalog exercise for name + scheme. The pool is tiny
    /// (~44 rows), so phase/variant/demand filtering happens in Swift
    /// (SportSeasonGenerator) rather than via fragile JSON-array SQL.
    /// (exercise, injury) pairs carrying `contraindicated` AND `rehab_early`
    /// at once. The injury filter reads only `contraindicated`, so such a pair
    /// removes the very movement someone marked as the treatment for that
    /// injury. Only `rehab_early` conflicts: `prehab` means the movement
    /// prevents the injury and `rehab_late` means you progress to it, and both
    /// sit happily beside a contraindication while symptomatic.
    func contradictoryInjuryRoles() -> [String] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT e.name || " / " || ci.slug
        FROM exercise_injury_relevance a
        JOIN exercise_injury_relevance b
          ON b.exercise_id = a.exercise_id AND b.injury_id = a.injury_id
        JOIN exercises e ON e.id = a.exercise_id
        JOIN common_injuries ci ON ci.id = a.injury_id
        WHERE a.role = 'contraindicated'
          AND b.role = 'rehab_early'
        ORDER BY 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let s = text(stmt, 0) { out.append(s) } }
        return out
    } }

    /// Every sport slug that has a movement pool. Lets a test iterate the real
    /// set instead of a hardcoded list that goes stale without saying so (R3-5).
    func sportMovementSportSlugs() -> [String] { withLock {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT DISTINCT sport FROM sport_movements ORDER BY sport", -1, &stmt, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let s = text(stmt, 0) { out.append(s) } }
        return out
    } }

    func sportMovements(sport sportSlug: String) -> [SportMovement] { withLock {
        guard let db else { return [] }
        let sql = """
        SELECT sm.exercise_id, sm.name, sm.demands, sm.allowed_phases,
               sm.allowed_variants, sm.fatigue_cost, sm.min_experience,
               sm.injury_caution, e.slug, e.is_compound, e.is_unilateral
        FROM sport_movements sm
        JOIN exercises e ON e.id = sm.exercise_id
        WHERE sm.sport = ?
        ORDER BY sm.id ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sportSlug, -1, SQLITE_TRANSIENT)

        func jsonStrings(_ idx: Int32) -> [String] {
            guard let raw = text(stmt, idx), let data = raw.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }

        var out: [SportMovement] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let demands = jsonStrings(2).compactMap { Demand(rawValue: $0) }
            let phases = jsonStrings(3).compactMap { SeasonPhase(rawValue: $0) }
            let variantStrings = (sqlite3_column_type(stmt, 4) == SQLITE_NULL) ? nil : jsonStrings(4)
            let variants = variantStrings?.compactMap { SportVariant(rawValue: $0) }
            out.append(SportMovement(
                exerciseId: Int(sqlite3_column_int64(stmt, 0)),
                name: text(stmt, 1) ?? "",
                catalogSlug: text(stmt, 8) ?? "",
                demands: demands,
                allowedPhases: phases,
                allowedVariants: variants,
                fatigueCost: intOrNil(stmt, 5) ?? 2,
                minExperienceRank: ExperienceLevel.seasonRank(forSeedToken: text(stmt, 6) ?? "novice"),
                injuryCaution: text(stmt, 7),
                isCompound: (intOrNil(stmt, 9) ?? 0) == 1,
                isUnilateral: (intOrNil(stmt, 10) ?? 0) == 1))
        }
        return out
    } }

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    private func intOrNil(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        if sqlite3_column_type(stmt, idx) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(stmt, idx))
    }

    /// Phase 3 CSV import name resolution. Tries exercises.name, then slug,
    /// then exercise_aliases.alias — all case-insensitive. Also retries
    /// with any trailing "(Foo)" suffix stripped because Fitbod sometimes
    /// writes "Bench Press (Barbell)" where coach.db has "Barbell Bench
    /// Press". Returns nil if no candidate resolves; caller stores
    /// `exercise_name_raw` for later remediation. Exposed publicly for
    /// `WorkoutCSVImporter` use.
    func exerciseId(forImportName raw: String) -> Int? { withLock {
        guard let db else { return nil }
        let normalized = Self.normalizeImportName(raw)
        if normalized.isEmpty { return nil }

        let noParen = Self.stripTrailingParen(normalized)
        let candidates: [String] = noParen == normalized ? [normalized] : [normalized, noParen]

        for candidate in candidates {
            if let id = lookupExerciseIdLocked(db: db,
                sql: "SELECT id FROM exercises WHERE LOWER(name) = ? LIMIT 1",
                bind: candidate) { return id }
            if let id = lookupExerciseIdLocked(db: db,
                sql: "SELECT id FROM exercises WHERE LOWER(slug) = ? LIMIT 1",
                bind: candidate) { return id }
            if let id = lookupExerciseIdLocked(db: db,
                sql: "SELECT exercise_id FROM exercise_aliases WHERE LOWER(alias) = ? LIMIT 1",
                bind: candidate) { return id }
        }
        return nil
    } }

    private func lookupExerciseIdLocked(db: OpaquePointer, sql: String, bind value: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, value, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Normalize a CSV exercise name for matching: lowercase, trim, collapse
    /// internal whitespace. Exposed for parser tests.
    static func normalizeImportName(_ raw: String) -> String {
        let lowered = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lowered.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// "bench press (barbell)" → "bench press". Idempotent.
    static func stripTrailingParen(_ s: String) -> String {
        guard let openIdx = s.lastIndex(of: "("),
              s.last == ")" else { return s }
        return String(s[..<openIdx]).trimmingCharacters(in: .whitespaces)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
