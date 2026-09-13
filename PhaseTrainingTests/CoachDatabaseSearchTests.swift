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

    // MARK: - Library global search

    /// The Library tab's global search calls the picker overload with every
    /// filter cleared. `compoundOnly` is a tri-state: nil = no filter, false =
    /// isolation only. It shipped as `false`, so the global search could never
    /// return a compound lift (every deadlift, squat, press). Pins the call
    /// shape LibraryScreen.searchResults uses.
    func test_librarySearch_findsCompoundLifts() throws {
        try requireCoachDB()
        let rows = CoachDatabase.shared.listExercises(
            search: "romanian deadlift",
            muscleSlugs: [],
            patternSlugs: [],
            modality: nil,
            difficulty: nil,
            environment: nil,
            compoundOnly: nil,
            userSportSlugs: []
        )
        XCTAssertTrue(rows.contains { $0.slug == "romanian-deadlift" },
                      "global search must reach compound lifts; got \(rows.map(\.name))")
    }

    func test_compoundOnlyFalse_isIsolationFilter_notNoFilter() throws {
        try requireCoachDB()
        let isolation = CoachDatabase.shared.listExercises(
            search: "deadlift", compoundOnly: false)
        XCTAssertTrue(isolation.isEmpty, "every deadlift is compound, so compoundOnly:false must exclude them all")
    }

    // MARK: - singularStem / plural queries

    func test_singularStem_stripsPlurals() {
        XCTAssertEqual(CoachDatabase.singularStem("pullups"), "pullup")
        XCTAssertEqual(CoachDatabase.singularStem("squats"), "squat")
        XCTAssertEqual(CoachDatabase.singularStem("lunges"), "lunge")
        XCTAssertEqual(CoachDatabase.singularStem("rows"), "row")
    }

    func test_singularStem_stripsSibilantES() {
        XCTAssertEqual(CoachDatabase.singularStem("presses"), "press")
        XCTAssertEqual(CoachDatabase.singularStem("crunches"), "crunch")
    }

    func test_singularStem_leavesSingularsAlone() {
        // "-ss" is not a plural, and short terms must not be truncated: "abs"
        // becoming "ab" would match "stability", "cable", "abduction"...
        XCTAssertEqual(CoachDatabase.singularStem("press"), "press")
        XCTAssertEqual(CoachDatabase.singularStem("abs"), "abs")
        XCTAssertEqual(CoachDatabase.singularStem("deadlift"), "deadlift")
    }

    /// The reported bug: typing the name the way a lifter says it found
    /// nothing. Catalog names are singular and hyphenated ("Pull-Up"), so
    /// "pull ups" normalized to "pullups" — which is not a substring of
    /// "pullup" — and the picker looked empty.
    func test_pluralQuery_findsSingularCatalogName() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        for query in ["pull ups", "pullups", "pull-ups", "Pull Ups"] {
            let hits = coach.listExercises(search: query, muscleSlugs: [])
            XCTAssertTrue(hits.contains { $0.name == "Pull-Up" },
                          "\(query) must find Pull-Up; got \(hits.map(\.name))")
        }
    }

    func test_pluralQuery_findsOtherStaples() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        XCTAssertTrue(coach.listExercises(search: "push ups", muscleSlugs: [])
            .contains { $0.name == "Push-Up" })
        XCTAssertTrue(coach.listExercises(search: "chin ups", muscleSlugs: [])
            .contains { $0.name == "Chin-Up" })
        XCTAssertFalse(coach.listExercises(search: "squats", muscleSlugs: []).isEmpty)
    }

    // MARK: - Vocabulary (abbreviations, irregular plurals, synonyms)

    func test_rewrite_expandsAbbreviations() {
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("db shoulder press"), "dumbbell shoulder press")
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("ohp"), "overhead press")
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("kb swing"), "kettlebell swing")
    }

    func test_rewrite_fixesIrregularPlurals() {
        // singularStem would give "calve" / "flie" — neither is in any name.
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("calves"), "calf")
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("chest flies"), "chest fly")
    }

    func test_rewrite_leavesOrdinaryWordsAlone() {
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("bench press"), "bench press")
        XCTAssertEqual(ExerciseSearchVocabulary.rewrite("Barbell Row"), "barbell row")
    }

    func test_aliases_areSymmetric() {
        XCTAssertTrue(ExerciseSearchVocabulary.aliases(for: "shoulder").contains("overhead"))
        XCTAssertTrue(ExerciseSearchVocabulary.aliases(for: "overhead").contains("shoulder"))
        XCTAssertTrue(ExerciseSearchVocabulary.aliases(for: "side").contains("lateral"))
    }

    func test_aliases_defaultToTheWordItself() {
        XCTAssertEqual(ExerciseSearchVocabulary.aliases(for: "row"), ["row"])
    }

    /// The reported bug: the catalog calls it "Dumbbell Overhead Press", the
    /// user calls it a dumbbell shoulder press. Not a typo — "shoulder" is six
    /// edits from "overhead" — so only the synonym layer finds it.
    func test_synonym_shoulderPressFindsOverheadPress() throws {
        try requireCoachDB()
        for query in ["dumbbell shoulder press", "db shoulder press"] {
            let hits = CoachDatabase.shared.listExercises(search: query, muscleSlugs: [])
            XCTAssertTrue(hits.contains { $0.name == "Dumbbell Overhead Press" },
                          "\(query) must find Dumbbell Overhead Press; got \(hits.map(\.name))")
        }
    }

    func test_synonym_worksInBothDirections() throws {
        try requireCoachDB()
        // "side raises" must reach the Lateral Raises.
        let hits = CoachDatabase.shared.listExercises(search: "side raises", muscleSlugs: [])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.name.lowercased().contains("lateral") },
                      "got \(hits.map(\.name))")
    }

    func test_abbreviations_resolveToTheRightLift() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        XCTAssertTrue(coach.listExercises(search: "ohp", muscleSlugs: [])
            .contains { $0.name == "Barbell Overhead Press (Strict)" })
        XCTAssertTrue(coach.listExercises(search: "rdl", muscleSlugs: [])
            .allSatisfy { $0.name.lowercased().contains("romanian") })
        XCTAssertTrue(coach.listExercises(search: "kb swing", muscleSlugs: [])
            .contains { $0.name == "Kettlebell Swing" })
    }

    func test_irregularPlural_calvesFindsCalfWork() throws {
        try requireCoachDB()
        let hits = CoachDatabase.shared.listExercises(search: "calves", muscleSlugs: [])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.name.lowercased().contains("calf") },
                      "got \(hits.map(\.name))")
    }

    // MARK: - partialNameScore (the last tier)

    func test_partial_allowsAWordTheCatalogLacks() {
        // The catalog has no "weighted" dip variant; the dips are still the
        // right answer.
        XCTAssertNotNil(CoachDatabase.partialNameScore(query: "weighted dips", name: "Dips (Parallel Bar)"))
    }

    func test_partial_needsASubstantialWord() {
        // Matching on "up" alone must not qualify, or every Push-Up answers a
        // search for pull-ups.
        XCTAssertNil(CoachDatabase.partialNameScore(query: "pull ups", name: "Push-Up"))
        XCTAssertNotNil(CoachDatabase.partialNameScore(query: "pull ups", name: "Pull-Up"))
    }

    func test_partial_singleTokenQueryStaysStrict() {
        // Half of one word rounds up to one, so a one-word miss stays a miss.
        XCTAssertNil(CoachDatabase.partialNameScore(query: "zzzxqwvk", name: "Pull-Up"))
    }

    func test_partialMatches_ranksTheMovementWordFirst() {
        let dip = Exercise.stub(name: "Chest Dip")
        let pullUp = Exercise.stub(name: "Weighted Pull-Up")
        let ranked = CoachDatabase.partialMatches(in: [pullUp, dip], query: "weighted dips")
        XCTAssertEqual(ranked.first?.name, "Chest Dip",
                       "the dips answer \"weighted dips\"; Weighted Pull-Up only shares the qualifier")
    }

    // MARK: - Search tiers

    func test_tier_reportsWhichLayerAnswered() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        XCTAssertEqual(coach.searchExercises(search: "bench press").tier, .substring)
        XCTAssertEqual(coach.searchExercises(search: "benhc press").tier, .fuzzy)
        XCTAssertEqual(coach.searchExercises(search: "weighted dips").tier, .partial)
    }

    func test_tier_ordersStrongestFirst() {
        XCTAssertLessThan(CoachDatabase.SearchTier.substring, CoachDatabase.SearchTier.fuzzy)
        XCTAssertLessThan(CoachDatabase.SearchTier.fuzzy, CoachDatabase.SearchTier.partial)
    }

    // MARK: - ExerciseSearch broadening

    /// The swap picker opens pre-filtered to "similar exercises". A typed name
    /// the filter excludes must still be findable — otherwise the library
    /// looks like it doesn't have the exercise.
    func test_search_broadensPastFiltersWhenQueryDeadEnds() throws {
        try requireCoachDB()
        var filters = ExerciseFilters()
        filters.bucket = .chest
        filters.category = .push
        let outcome = ExerciseSearch.run(query: "pull ups", filters: filters)
        XCTAssertTrue(outcome.broadenedPastFilters,
                      "a dead-end query under filters must fall back to the full catalog")
        XCTAssertTrue(outcome.exercises.contains { $0.name == "Pull-Up" },
                      "got \(outcome.exercises.map(\.name))")
    }

    /// Broadening is a last resort: it must not fire, or reorder anything,
    /// when the filtered query already has results.
    func test_search_keepsFiltersWhenQueryMatches() throws {
        try requireCoachDB()
        var filters = ExerciseFilters()
        filters.bucket = .chest
        let outcome = ExerciseSearch.run(query: "bench press", filters: filters)
        XCTAssertFalse(outcome.exercises.isEmpty)
        XCTAssertFalse(outcome.broadenedPastFilters)
    }

    /// A filtered query that only half-matches is still a dead end: the
    /// exercise the user named is in the catalog, one filter away. Swapping a
    /// squat, "dumbbell shoulder press" partial-matches the dumbbell leg work;
    /// the right answer is Dumbbell Overhead Press.
    func test_search_broadensPastAPartialFilteredMatch() throws {
        try requireCoachDB()
        var filters = ExerciseFilters()
        filters.bucket = .quads
        filters.category = .legs
        let outcome = ExerciseSearch.run(query: "dumbbell shoulder press", filters: filters)
        XCTAssertTrue(outcome.broadenedPastFilters)
        XCTAssertTrue(outcome.exercises.contains { $0.name == "Dumbbell Overhead Press" },
                      "got \(outcome.exercises.map(\.name))")
    }

    /// ...but a partial match the filters actually fit is kept. Dips are chest
    /// push work, so a chest-filtered "weighted dips" stays narrow.
    func test_search_keepsAPartialMatchTheFiltersFit() throws {
        try requireCoachDB()
        var filters = ExerciseFilters()
        filters.bucket = .chest
        filters.category = .push
        let outcome = ExerciseSearch.run(query: "weighted dips", filters: filters)
        XCTAssertFalse(outcome.broadenedPastFilters)
        XCTAssertTrue(outcome.exercises.contains { $0.name.lowercased().contains("dip") })
    }

    /// An empty search box with tight filters is the filters' own story — the
    /// chips are on screen and the user set them. No silent broadening.
    func test_search_emptyQueryNeverBroadens() throws {
        try requireCoachDB()
        var filters = ExerciseFilters()
        filters.bucket = .chest
        filters.category = .core
        let outcome = ExerciseSearch.run(query: "   ", filters: filters)
        XCTAssertFalse(outcome.broadenedPastFilters)
    }

    /// Nothing to broaden past: an unfiltered miss stays a miss rather than
    /// re-running the same query and claiming it widened the search.
    func test_search_unfilteredMissDoesNotClaimBroadening() throws {
        try requireCoachDB()
        let outcome = ExerciseSearch.run(query: "zzzxqwvk", filters: ExerciseFilters())
        XCTAssertTrue(outcome.exercises.isEmpty)
        XCTAssertFalse(outcome.broadenedPastFilters)
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
