// CoachDatabaseSearchTests — exercise-name search: separator-insensitivity
// plus character-level typo tolerance.
//
// Two layers, both pinned here:
//   1. Separator-insensitive substring match. Catalog names carry punctuation
//      lifters don't type ("Pull-Up", "Farmer's Walk"), so a plain
//      `name LIKE '%pull up%'` never matched "Pull-Up". Both the query and the
//      column are now stripped of CoachDatabase.searchSeparators before LIKE.
//   2. Fuzzy fallback. When the substring match finds nothing, the picker
//      overload (listExercises with the multi-filter signature) re-ranks the
//      catalog by per-token Optimal-String-Alignment distance, so "benhc
//      press" / "deadlfit" still surface their targets. This fires ONLY on a
//      zero-result substring search, and ONLY on the picker overload — the
//      bare listExercises(search:) used for exact-name resolution stays exact.
//
// Pure-string units (osaDistance / fuzzyNameScore / normalizeSearchTerm) run
// without the DB. Integration cases read the bundled coach.db through the
// shared singleton, behind the same skip-guard the other coach.db suites use
// so a bundle-load hiccup skips rather than flakes CI.

import XCTest
@testable import PhaseTraining

final class CoachDatabaseSearchTests: XCTestCase {

    private func requireCoachDB() throws {
        guard CoachDatabase.shared.isOpen else {
            throw XCTSkip("coach.db not available in this test bundle")
        }
    }

    // MARK: - normalizeSearchTerm / searchTokens

    func test_normalize_stripsSeparators() {
        XCTAssertEqual(CoachDatabase.normalizeSearchTerm("Pull-Up"), "PullUp")
        XCTAssertEqual(CoachDatabase.normalizeSearchTerm("pull up"), "pullup")
        XCTAssertEqual(CoachDatabase.normalizeSearchTerm("Farmer's Walk"), "FarmersWalk")
        XCTAssertEqual(CoachDatabase.normalizeSearchTerm("T-Bar Row"), "TBarRow")
    }

    func test_tokens_splitOnSeparatorsAndWhitespace() {
        XCTAssertEqual(CoachDatabase.searchTokens("Pull-Up"), ["pull", "up"])
        XCTAssertEqual(CoachDatabase.searchTokens("  Bench   Press "), ["bench", "press"])
        XCTAssertEqual(CoachDatabase.searchTokens("Farmer's Walk"), ["farmer", "s", "walk"])
        XCTAssertEqual(CoachDatabase.searchTokens(""), [])
    }

    // MARK: - osaDistance

    private func osa(_ a: String, _ b: String) -> Int {
        CoachDatabase.osaDistance(Array(a), Array(b))
    }

    func test_osa_identicalIsZero() {
        XCTAssertEqual(osa("bench", "bench"), 0)
    }

    func test_osa_singleEdits() {
        XCTAssertEqual(osa("bench", "benc"), 1)   // deletion
        XCTAssertEqual(osa("bench", "benchs"), 1) // insertion
        XCTAssertEqual(osa("bench", "bensh"), 1)  // substitution
    }

    func test_osa_adjacentTranspositionIsOne() {
        // The whole point of OSA over plain Levenshtein: a fat-finger swap of
        // two neighbours is one edit, not two.
        XCTAssertEqual(osa("benhc", "bench"), 1)
        XCTAssertEqual(osa("deadlfit", "deadlift"), 1)
    }

    func test_osa_emptyOperands() {
        XCTAssertEqual(osa("", "bench"), 5)
        XCTAssertEqual(osa("bench", ""), 5)
        XCTAssertEqual(osa("", ""), 0)
    }

    // MARK: - fuzzyNameScore

    func test_fuzzy_transposedTokenMatches() {
        XCTAssertNotNil(CoachDatabase.fuzzyNameScore(query: "benhc press", name: "Barbell Bench Press"))
        XCTAssertNotNil(CoachDatabase.fuzzyNameScore(query: "deadlfit", name: "Conventional Deadlift"))
    }

    func test_fuzzy_isOrderIndependent() {
        // Unlike the contiguous substring path, token order doesn't matter.
        XCTAssertNotNil(CoachDatabase.fuzzyNameScore(query: "press bench", name: "Barbell Bench Press"))
    }

    func test_fuzzy_rejectsUnrelatedName() {
        XCTAssertNil(CoachDatabase.fuzzyNameScore(query: "benhc press", name: "Conventional Deadlift"))
        XCTAssertNil(CoachDatabase.fuzzyNameScore(query: "zzzxqwvk", name: "Pull-Up"))
    }

    func test_fuzzy_shortTokenGetsNoSlack() {
        // 2-char tokens are too ambiguous to fuzzy-match: "rw" must NOT become
        // "row". A clean exact short token still scores.
        XCTAssertNil(CoachDatabase.fuzzyNameScore(query: "rw", name: "Cable Row"))
        XCTAssertNotNil(CoachDatabase.fuzzyNameScore(query: "row", name: "Cable Row"))
    }

    func test_fuzzy_everyQueryTokenMustMatch() {
        // "press" matches, but "zzzzz" matches nothing → whole query fails.
        XCTAssertNil(CoachDatabase.fuzzyNameScore(query: "press zzzzz", name: "Barbell Bench Press"))
    }

    func test_fuzzyMatches_ranksClosestFirst() {
        let a = Exercise.stub(name: "Bench Press")          // exact-ish
        let b = Exercise.stub(name: "Incline Bench Press")  // farther (extra token, longer)
        let ranked = CoachDatabase.fuzzyMatches(in: [b, a], query: "bench prss")
        XCTAssertEqual(ranked.map(\.name), ["Bench Press", "Incline Bench Press"])
    }

    // MARK: - separator-insensitivity against the bundled catalog

    /// First catalog exercise whose name has a hyphen flanked by letters
    /// (Pull-Up, Push-Up, Chin-Up, …), lowercased — a real separator to probe.
    private func hyphenatedProbe(_ coach: CoachDatabase) throws -> String {
        let probe = coach.listExercises().first { ex in
            guard let r = ex.name.range(of: "-") else { return false }
            let i = ex.name.index(before: r.lowerBound)
            let j = r.upperBound
            return j < ex.name.endIndex && ex.name[i].isLetter && ex.name[j].isLetter
        }
        return try XCTUnwrap(probe?.name, "expected a hyphenated exercise name in coach.db").lowercased()
    }

    func test_search_spaceFindsHyphenatedName() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        let canonical = try hyphenatedProbe(coach)               // e.g. "pull-up"
        let spaced = canonical.replacingOccurrences(of: "-", with: " ")
        let smushed = canonical.replacingOccurrences(of: "-", with: "")

        func names(_ q: String) -> Set<String> {
            Set(coach.listExercises(search: q).map { $0.name.lowercased() })
        }

        let hyphenHits = names(canonical)
        XCTAssertTrue(hyphenHits.contains(canonical),
                      "baseline: hyphenated query should find its own row")
        XCTAssertEqual(names(spaced), hyphenHits,
                       "typing a space instead of the hyphen must return the same matches")
        XCTAssertEqual(names(smushed), hyphenHits,
                       "omitting the separator entirely must return the same matches")
    }

    func test_search_separatorInsensitive_inPickerOverload() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        let canonical = try hyphenatedProbe(coach)
        let spaced = canonical.replacingOccurrences(of: "-", with: " ")
        // muscleSlugs:[] forces Swift to the multi-filter (picker) overload.
        let hyphen = Set(coach.listExercises(search: canonical, muscleSlugs: []).map { $0.name.lowercased() })
        let space = Set(coach.listExercises(search: spaced, muscleSlugs: []).map { $0.name.lowercased() })
        XCTAssertFalse(hyphen.isEmpty)
        XCTAssertEqual(space, hyphen)
    }

    func test_search_emptyAndWhitespaceQuery_unaffected() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        let all = coach.listExercises().count
        XCTAssertEqual(coach.listExercises(search: "").count, all)
        XCTAssertEqual(coach.listExercises(search: "   ").count, all)
    }

    // MARK: - fuzzy fallback against the bundled catalog

    func test_fuzzy_transposedTypoRecoversExercise() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        // "Deadlift" → "Deadlfit": one adjacent transposition. Guarded so a
        // catalog rename skips rather than fails the suite.
        let canonical = "Conventional Deadlift"
        try XCTSkipUnless(
            coach.listExercises(search: canonical, muscleSlugs: []).contains { $0.name == canonical },
            "\(canonical) not in catalog")
        let typo = "Conventional Deadlfit"

        // The picker overload's fuzzy fallback recovers it...
        let fuzzy = coach.listExercises(search: typo, muscleSlugs: [])
        XCTAssertTrue(fuzzy.contains { $0.name == canonical },
                      "fuzzy fallback should recover \(canonical) from \(typo)")

        // ...while the exact-resolution overload (no fuzzy) still misses it,
        // proving the recovery is the fuzzy layer and not stray substring luck.
        XCTAssertFalse(coach.listExercises(search: typo).contains { $0.name == canonical },
                       "bare listExercises(search:) must stay exact — no fuzzy")
    }

    func test_cleanQuery_doesNotInvokeFuzzy() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        let hits = coach.listExercises(search: "deadlift", muscleSlugs: [])
        XCTAssertFalse(hits.isEmpty)
        // Every hit literally contains the substring — fuzzy (which would allow
        // near-misses) never ran, because the substring path was non-empty.
        for ex in hits {
            XCTAssertTrue(ex.name.lowercased().contains("deadlift"),
                          "\(ex.name) is not a substring match — fuzzy leaked into a clean query")
        }
    }

    func test_fuzzy_garbageQueryReturnsEmpty() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        // No token is within edit distance of any catalog token → empty, not a
        // hallucinated "did you mean".
        XCTAssertTrue(coach.listExercises(search: "zzzxqwvk", muscleSlugs: []).isEmpty)
    }
}

private extension Exercise {
    /// Minimal name-only Exercise for pure ranking tests. Only `name` (and a
    /// unique id) matters to fuzzyMatches; everything else is inert.
    static func stub(name: String) -> Exercise {
        Exercise(
            id: abs(name.hashValue), name: name, slug: name.lowercased(),
            description: nil, instructions: nil, cues: [], difficulty: nil,
            modality: nil, environment: nil, isCompound: false, isUnilateral: false,
            defaultSets: nil, defaultReps: nil, defaultRest: nil, defaultDuration: nil,
            regression: nil, progression: nil, imageURL: nil, thumbnailURL: nil,
            videoURL: nil, sourceVideoAttribution: nil
        )
    }
}
