// DatabaseDerivedQueriesTests — characterization of two derived-query
// surfaces:
//
//   1. UserDatabase.importedSetsLifetimePeaks — per-exercise heaviest
//      matched imported set (Phase 3 CSV history). Exercised against an
//      in-memory UserDatabase so the real Documents/user.db is never
//      touched (same pattern as ImportedWorkoutsDatabaseTests).
//
//   2. CoachDatabase.adjacentByDifficulty — easier/harder neighbors along
//      the difficulty axis within shared movement pattern(s). Exercised
//      read-only against the bundled coach.db via the shared singleton.
//      Probe exercises are found by scanning the catalog rather than
//      hardcoding canonical names/ids, so the tests survive coach.db
//      churn.

import XCTest
@testable import PhaseTraining

final class DatabaseDerivedQueriesTests: XCTestCase {

    // MARK: - Fixtures

    /// Fixed whole-second instants — performed_at round-trips through an
    /// INTEGER column, so sub-second precision would be lost anyway.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(daysAgo: Int) -> Date {
        t0.addingTimeInterval(-Double(daysAgo) * 86_400)
    }

    /// Minimal ImportedSet builder. The id comes from the natural-key
    /// tuple via `ImportedSet.makeId`, so distinct (performedAt, name,
    /// setNum) combinations never collide on the PK.
    private func makeSet(
        exerciseId: Int?,
        weight: Double?,
        reps: Int?,
        performedAt: Date,
        setNum: Int = 1,
        name: String = "Imported Lift"
    ) -> ImportedSet {
        ImportedSet(
            id: ImportedSet.makeId(source: .fitbodCSV, performedAt: performedAt,
                                   exerciseNameRaw: name, setNum: setNum),
            source: .fitbodCSV,
            exerciseId: exerciseId,
            exerciseNameRaw: name,
            performedAt: performedAt,
            setNum: setNum,
            weight: weight,
            reps: reps,
            rir: nil,
            rpe: nil
        )
    }

    // MARK: - UserDatabase.importedSetsLifetimePeaks

    func test_lifetimePeaks_emptyDatabase_returnsEmpty() {
        let db = UserDatabase(path: ":memory:")
        XCTAssertTrue(db.isOpen)
        XCTAssertTrue(db.importedSetsLifetimePeaks().isEmpty)
    }

    func test_lifetimePeaks_singleExercise_picksHeaviestSetRow() {
        let db = UserDatabase(path: ":memory:")
        let peakDate = at(daysAgo: 30)
        db.insertImportedSets([
            makeSet(exerciseId: 42, weight: 100, reps: 8, performedAt: at(daysAgo: 60)),
            makeSet(exerciseId: 42, weight: 120, reps: 3, performedAt: peakDate),
            makeSet(exerciseId: 42, weight: 110, reps: 5, performedAt: at(daysAgo: 10))
        ])
        let peaks = db.importedSetsLifetimePeaks()
        XCTAssertEqual(peaks.count, 1)
        XCTAssertEqual(peaks.first?.exerciseId, 42)
        XCTAssertEqual(peaks.first?.weight, 120)
        // Reps + date come from the SAME row as the peak weight, not the
        // max reps / latest date across all rows.
        XCTAssertEqual(peaks.first?.reps, 3)
        XCTAssertEqual(peaks.first?.performedAt, peakDate)
    }

    func test_lifetimePeaks_multipleExercises_onePeakEach() {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets([
            makeSet(exerciseId: 1, weight: 60, reps: 10, performedAt: at(daysAgo: 5), name: "Curl"),
            makeSet(exerciseId: 1, weight: 55, reps: 12, performedAt: at(daysAgo: 4), name: "Curl"),
            makeSet(exerciseId: 2, weight: 140, reps: 5, performedAt: at(daysAgo: 3), name: "Squat"),
            makeSet(exerciseId: 2, weight: 130, reps: 8, performedAt: at(daysAgo: 2), name: "Squat")
        ])
        let peaks = db.importedSetsLifetimePeaks()
        XCTAssertEqual(peaks.count, 2)
        let byId = Dictionary(uniqueKeysWithValues: peaks.map { ($0.exerciseId, $0) })
        XCTAssertEqual(byId[1]?.weight, 60)
        XCTAssertEqual(byId[1]?.reps, 10)
        XCTAssertEqual(byId[2]?.weight, 140)
        XCTAssertEqual(byId[2]?.reps, 5)
    }

    func test_lifetimePeaks_tieOnPeakWeight_prefersMostRecentRow() {
        let db = UserDatabase(path: ":memory:")
        let older = at(daysAgo: 90)
        let newer = at(daysAgo: 9)
        db.insertImportedSets([
            makeSet(exerciseId: 7, weight: 100, reps: 8, performedAt: older),
            makeSet(exerciseId: 7, weight: 100, reps: 5, performedAt: newer)
        ])
        let peaks = db.importedSetsLifetimePeaks()
        XCTAssertEqual(peaks.count, 1)
        XCTAssertEqual(peaks.first?.weight, 100)
        // Doc comment: "Tiebreak by most recent (we prefer newer evidence
        // of the same peak)" — the newer row's reps and date win.
        XCTAssertEqual(peaks.first?.reps, 5)
        XCTAssertEqual(peaks.first?.performedAt, newer)
    }

    func test_lifetimePeaks_skipsUnmatchedAndIncompleteRows() {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets([
            // Unmatched name (nil exercise_id) — heaviest of all, must not appear.
            makeSet(exerciseId: nil, weight: 200, reps: 1, performedAt: at(daysAgo: 8), name: "Mystery Lift"),
            // exercise 9: two incomplete rows + one complete row.
            makeSet(exerciseId: 9, weight: nil, reps: 10, performedAt: at(daysAgo: 7)),
            makeSet(exerciseId: 9, weight: 50, reps: nil, performedAt: at(daysAgo: 6)),
            makeSet(exerciseId: 9, weight: 40, reps: 6, performedAt: at(daysAgo: 5)),
            // exercise 11: only incomplete rows — excluded entirely.
            makeSet(exerciseId: 11, weight: nil, reps: 12, performedAt: at(daysAgo: 4), name: "Plank")
        ])
        let peaks = db.importedSetsLifetimePeaks()
        XCTAssertEqual(peaks.map { $0.exerciseId }, [9])
        // The heavier-but-repless 50 kg row can't back priorBest; the
        // complete 40 kg row is the peak.
        XCTAssertEqual(peaks.first?.weight, 40)
        XCTAssertEqual(peaks.first?.reps, 6)
    }

    // MARK: - CoachDatabase.adjacentByDifficulty helpers

    /// Mirror of CoachDatabase's private difficultyRank — keep in
    /// lock-step with the production switch.
    private func rank(_ difficulty: String?) -> Int? {
        switch difficulty?.lowercased() {
        case "beginner":     return 1
        case "intermediate": return 2
        case "advanced":     return 3
        case "elite":        return 4
        default:             return nil
        }
    }

    /// Same skip-guard as CoachDatabaseConcurrencyTests — keeps the suite
    /// green in environments where the bundled coach.db can't load.
    private func requireCoachDB() throws {
        guard CoachDatabase.shared.isOpen else {
            throw XCTSkip("coach.db not available in this test bundle")
        }
    }

    // MARK: - CoachDatabase.adjacentByDifficulty

    func test_adjacent_knownExercise_neighborsAreCorrectSideAndSharePattern() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        // Scan intermediates (both sides reachable from rank 2) for the
        // first one that yields BOTH neighbors. The bundled DB has 150+
        // such exercises, so this must find one — fail loudly rather than
        // skip if it can't.
        let intermediates = coach.listExercises().filter { rank($0.difficulty) == 2 }
        var found: (current: Exercise, easier: Exercise, harder: Exercise)?
        for candidate in intermediates {
            let (easier, harder) = coach.adjacentByDifficulty(forExerciseId: candidate.id)
            if let easier, let harder {
                found = (candidate, easier, harder)
                break
            }
        }
        let (current, easier, harder) = try XCTUnwrap(
            found, "no intermediate exercise yielded both neighbors — coach.db data regression?")

        // Neither neighbor is the probe itself.
        XCTAssertNotEqual(easier.id, current.id)
        XCTAssertNotEqual(harder.id, current.id)

        // Easier sits strictly below the probe's tier, harder strictly above.
        let currentRank = try XCTUnwrap(rank(current.difficulty))
        XCTAssertLessThan(try XCTUnwrap(rank(easier.difficulty)), currentRank)
        XCTAssertGreaterThan(try XCTUnwrap(rank(harder.difficulty)), currentRank)

        // Both neighbors share at least one movement pattern with the probe.
        let currentPatterns = Set(coach.patternsForExercise(current.id))
        XCTAssertFalse(currentPatterns.isEmpty)
        XCTAssertFalse(currentPatterns.isDisjoint(with: coach.patternsForExercise(easier.id)),
                       "easier neighbor must share a movement pattern")
        XCTAssertFalse(currentPatterns.isDisjoint(with: coach.patternsForExercise(harder.id)),
                       "harder neighbor must share a movement pattern")
    }

    func test_adjacent_unknownExerciseId_returnsNilPair() throws {
        try requireCoachDB()
        let (easier, harder) = CoachDatabase.shared.adjacentByDifficulty(forExerciseId: 999_999)
        XCTAssertNil(easier)
        XCTAssertNil(harder)
    }

    func test_adjacent_exerciseWithoutMovementPatterns_returnsNilPair() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        // ~100 catalog exercises carry no movement-pattern rows; with no
        // shared-pattern peers there is nothing adjacent on either side.
        let unpatterned = coach.listExercises().first {
            coach.patternsForExercise($0.id).isEmpty
        }
        let probe = try XCTUnwrap(unpatterned,
                                  "expected at least one pattern-less exercise in coach.db")
        let (easier, harder) = coach.adjacentByDifficulty(forExerciseId: probe.id)
        XCTAssertNil(easier)
        XCTAssertNil(harder)
    }

    func test_adjacent_beginnerExercise_hasNoEasierNeighbor() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        // Beginner is the floor tier (rank 1) — nothing can rank below it.
        // Probe a handful to keep runtime bounded.
        let beginners = coach.listExercises().filter { rank($0.difficulty) == 1 }.prefix(10)
        XCTAssertFalse(beginners.isEmpty, "coach.db should carry beginner exercises")
        for ex in beginners {
            let (easier, _) = coach.adjacentByDifficulty(forExerciseId: ex.id)
            XCTAssertNil(easier, "\(ex.name) is beginner — no easier tier exists")
        }
    }

    func test_adjacent_eliteExercise_hasNoHarderNeighbor() throws {
        try requireCoachDB()
        let coach = CoachDatabase.shared
        // Elite is the ceiling tier (rank 4) — nothing can rank above it.
        let elites = coach.listExercises().filter { rank($0.difficulty) == 4 }
        try XCTSkipIf(elites.isEmpty, "no elite-tier exercises in this coach.db build")
        for ex in elites {
            let (_, harder) = coach.adjacentByDifficulty(forExerciseId: ex.id)
            XCTAssertNil(harder, "\(ex.name) is elite — no harder tier exists")
        }
    }
}
