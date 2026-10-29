// DatabaseDerivedQueriesTests — characterization of a derived-query surface:
//
//   CoachDatabase.adjacentByDifficulty — easier/harder neighbors along
//      the difficulty axis within shared movement pattern(s). Exercised
//      read-only against the bundled coach.db via the shared singleton.
//      Probe exercises are found by scanning the catalog rather than
//      hardcoding canonical names/ids, so the tests survive coach.db
//      churn.

import XCTest
@testable import PhaseTraining

final class DatabaseDerivedQueriesTests: XCTestCase {

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
