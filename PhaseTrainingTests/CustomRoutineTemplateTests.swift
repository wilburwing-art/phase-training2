import XCTest
@testable import PhaseTraining

/// Characterization tests for `CustomRoutine.toWorkoutTemplate()` — the
/// bridge from user-created routines (JSON in UserDefaults) into the
/// `WorkoutTemplate` shape SessionStore.createSession consumes. Locks in:
/// the "custom-" / "cex-" id derivation (stable across calls, no fresh
/// UUIDs), the empty-name → "Custom workout" fallback, sets/reps/rest
/// defaults + the leading-number reps parser and the seconds/"min" rest
/// parser, supersetGroup passthrough, and the coach.db-driven unit pick
/// (unmapped exercise ids classify reps-only → bodyweight sentinel).
final class CustomRoutineTemplateTests: XCTestCase {

    // MARK: - Fixtures

    /// An exercise id guaranteed absent from coach.db. `equipmentCategory`
    /// classifies unmapped ids as `.repsOnly` (no equipment = bodyweight),
    /// so rows built on this id deterministically log as "bw".
    private static let unmappedExerciseId = 987_654_321

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeExercise(
        id: String = "e1",
        exerciseId: Int = CustomRoutineTemplateTests.unmappedExerciseId,
        name: String = "Test Move",
        position: Int = 0,
        sets: Int? = 3,
        reps: String? = "10",
        rest: String? = "60",
        notes: String? = nil,
        supersetGroup: Int? = nil
    ) -> CustomRoutineExercise {
        CustomRoutineExercise(
            id: id, exerciseId: exerciseId, name: name, position: position,
            sets: sets, reps: reps, rest: rest, notes: notes,
            supersetGroup: supersetGroup
        )
    }

    private func makeRoutine(
        id: String = "r1",
        name: String = "Push Day",
        exercises: [CustomRoutineExercise] = []
    ) -> CustomRoutine {
        CustomRoutine(id: id, name: name, exercises: exercises, createdAt: fixedDate)
    }

    // MARK: - Top-level mapping

    func test_toWorkoutTemplate_mapsIdNameAndCategory() {
        let t = makeRoutine(id: "abc-123", name: "Push Day").toWorkoutTemplate()
        XCTAssertEqual(t.id, "custom-abc-123")
        XCTAssertEqual(t.name, "Push Day")
        XCTAssertEqual(t.category, "Custom")
    }

    func test_toWorkoutTemplate_emptyName_fallsBackToCustomWorkout() {
        let t = makeRoutine(name: "").toWorkoutTemplate()
        XCTAssertEqual(t.name, "Custom workout")
    }

    func test_toWorkoutTemplate_idsStableAcrossCalls() {
        // Ids derive from the stored routine / exercise ids — no fresh UUIDs
        // — so re-bridging the same routine yields an identical template.
        let routine = makeRoutine(id: "fixed-routine-id", exercises: [
            makeExercise(id: "ex-a", name: "A"),
            makeExercise(id: "ex-b", name: "B"),
        ])
        let first = routine.toWorkoutTemplate()
        let second = routine.toWorkoutTemplate()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.id, "custom-fixed-routine-id")
        XCTAssertEqual(first.exercises.map(\.id), ["cex-ex-a", "cex-ex-b"])
    }

    // MARK: - Empty routine

    func test_toWorkoutTemplate_emptyRoutine_producesNoExercises() {
        let t = makeRoutine(id: "empty", name: "Nothing Yet").toWorkoutTemplate()
        XCTAssertTrue(t.exercises.isEmpty)
        XCTAssertEqual(t.id, "custom-empty")
        XCTAssertEqual(t.name, "Nothing Yet")
        XCTAssertEqual(t.category, "Custom")
    }

    func test_makeBlank_bridgesToEmptyCustomWorkout() {
        let blank = CustomRoutine.makeBlank()
        XCTAssertEqual(blank.name, "")
        XCTAssertTrue(blank.exercises.isEmpty)

        let t = blank.toWorkoutTemplate()
        XCTAssertEqual(t.name, "Custom workout")
        XCTAssertTrue(t.exercises.isEmpty)
        XCTAssertTrue(t.id.hasPrefix("custom-"))
    }

    // MARK: - Exercise field mapping

    func test_toWorkoutTemplate_mapsExerciseFields() throws {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "row-1", name: "Bird Dog",
                         sets: 4, reps: "10", rest: "60"),
        ])
        let ex = try XCTUnwrap(routine.toWorkoutTemplate().exercises.first)
        XCTAssertEqual(ex.id, "cex-row-1")
        XCTAssertEqual(ex.name, "Bird Dog")
        XCTAssertNil(ex.type)
        XCTAssertEqual(ex.targetSets, 4)
        XCTAssertEqual(ex.targetReps, 10)
        XCTAssertEqual(ex.rest, 60)
        XCTAssertNil(ex.rpe)
        XCTAssertNil(ex.tempo)
        XCTAssertNil(ex.supersetGroup)
    }

    func test_toWorkoutTemplate_preservesArrayOrder_ignoresPositionField() {
        // The bridge maps exercises in array order; the stored `position`
        // ints don't re-sort. Reversed positions stay where the array put
        // them.
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", name: "First", position: 2),
            makeExercise(id: "b", name: "Second", position: 1),
            makeExercise(id: "c", name: "Third", position: 0),
        ])
        let names = routine.toWorkoutTemplate().exercises.map(\.name)
        XCTAssertEqual(names, ["First", "Second", "Third"])
    }

    // MARK: - Sets / reps defaults

    func test_toWorkoutTemplate_nilSets_defaultsTo3() throws {
        let routine = makeRoutine(exercises: [makeExercise(sets: nil)])
        let ex = try XCTUnwrap(routine.toWorkoutTemplate().exercises.first)
        XCTAssertEqual(ex.targetSets, 3)
    }

    func test_toWorkoutTemplate_repsParsing_takesLeadingNumber() {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", reps: "8-10"),
            makeExercise(id: "b", reps: "12 each side"),
            makeExercise(id: "c", reps: "15"),
            makeExercise(id: "d", reps: "0"),
        ])
        let reps = routine.toWorkoutTemplate().exercises.map(\.targetReps)
        XCTAssertEqual(reps, [8, 12, 15, 0])
    }

    func test_toWorkoutTemplate_unparseableOrNilReps_defaultTo8() {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", reps: nil),
            makeExercise(id: "b", reps: "AMRAP"),
            makeExercise(id: "c", reps: ""),
            makeExercise(id: "d", reps: "x10"),  // leading non-digit
        ])
        let reps = routine.toWorkoutTemplate().exercises.map(\.targetReps)
        XCTAssertEqual(reps, [8, 8, 8, 8])
    }

    // MARK: - Rest parsing

    func test_toWorkoutTemplate_restParsing_plainNumbersAreSeconds() {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", rest: "60"),
            makeExercise(id: "b", rest: "90s"),
            makeExercise(id: "c", rest: "45 sec"),
        ])
        let rests = routine.toWorkoutTemplate().exercises.map(\.rest)
        XCTAssertEqual(rests, [60, 90, 45])
    }

    func test_toWorkoutTemplate_restParsing_minutesConvertToSeconds() {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", rest: "2 min"),
            makeExercise(id: "b", rest: "1.5 min"),
            makeExercise(id: "c", rest: "2 MIN"),      // case-insensitive
            makeExercise(id: "d", rest: "3 minutes"),
            makeExercise(id: "e", rest: "2min"),       // no space
        ])
        let rests = routine.toWorkoutTemplate().exercises.map(\.rest)
        XCTAssertEqual(rests, [120, 90, 120, 180, 120])
    }

    func test_toWorkoutTemplate_unparseableOrNilRest_defaultsTo90() {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", rest: nil),
            makeExercise(id: "b", rest: "as needed"),
            makeExercise(id: "c", rest: ""),
        ])
        let rests = routine.toWorkoutTemplate().exercises.map(\.rest)
        XCTAssertEqual(rests, [90, 90, 90])
    }

    func test_toWorkoutTemplate_fractionalSecondsRest_truncates() throws {
        let routine = makeRoutine(exercises: [makeExercise(rest: "45.5")])
        let ex = try XCTUnwrap(routine.toWorkoutTemplate().exercises.first)
        XCTAssertEqual(ex.rest, 45)
    }

    // MARK: - Superset metadata

    func test_toWorkoutTemplate_preservesSupersetGroups() {
        let routine = makeRoutine(exercises: [
            makeExercise(id: "a", name: "Curl", supersetGroup: 1),
            makeExercise(id: "b", name: "Pushdown", supersetGroup: 1),
            makeExercise(id: "c", name: "Plank", supersetGroup: nil),
            makeExercise(id: "d", name: "Flye", supersetGroup: 2),
        ])
        let groups = routine.toWorkoutTemplate().exercises.map(\.supersetGroup)
        XCTAssertEqual(groups, [1, 1, nil, 2])
    }

    // MARK: - Unit selection via coach.db

    func test_toWorkoutTemplate_unknownExerciseId_logsAsBodyweight() throws {
        // Sanity: the sentinel id really is absent from the bundled catalog.
        XCTAssertNil(CoachDatabase.shared.exercise(id: Self.unmappedExerciseId))

        let routine = makeRoutine(exercises: [
            makeExercise(exerciseId: Self.unmappedExerciseId),
        ])
        let ex = try XCTUnwrap(routine.toWorkoutTemplate().exercises.first)
        XCTAssertEqual(ex.unit, LoggedExercise.bodyweightUnit)
    }

    func test_toWorkoutTemplate_loadedExercise_logsInLbs() throws {
        // Pick a catalog row by coverage (its classified category), not by
        // canonical name — any non-reps-only exercise must log in lbs.
        let candidates = Array(CoachDatabase.shared.listExercises().prefix(200))
        XCTAssertFalse(candidates.isEmpty, "bundled coach.db should list exercises")
        let categories = CoachDatabase.shared.equipmentCategory(
            forExerciseIds: Set(candidates.map(\.id)))
        let loaded = try XCTUnwrap(
            candidates.first { categories[$0.id] != .repsOnly },
            "catalog should contain at least one loaded (non-reps-only) exercise"
        )

        let routine = makeRoutine(exercises: [
            makeExercise(exerciseId: loaded.id, name: loaded.name),
        ])
        let ex = try XCTUnwrap(routine.toWorkoutTemplate().exercises.first)
        XCTAssertEqual(ex.unit, "lbs")
    }
}
