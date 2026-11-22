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

// MARK: - Persistence (11c 2.5)

/// `CustomRoutineStore.migrateLegacyIfNeeded` and the `UserDatabase+Routines`
/// reads and deletes. Every test gets its own UserDefaults suite and an
/// in-memory user.db.
extension CustomRoutineTemplateTests {

    private static let legacyKey = "pt_custom_routines"
    private static let migrationFlag = "pt_custom_routines_migrated_v1"

    private func isolatedDefaults(_ tag: String = #function) -> UserDefaults {
        let suite = "CustomRoutineTemplateTests.\(tag).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    /// Same codec the pre-SQLite build wrote: secondsSince1970 dates.
    private func legacyBlob(_ routines: [CustomRoutine]) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return try e.encode(routines)
    }

    // MARK: Legacy migration

    func test_migration_importsLegacyBlob_clearsKey_setsFlag() throws {
        let defaults = isolatedDefaults()
        let db = UserDatabase(path: ":memory:")
        let legacy = makeRoutine(id: "legacy-1", name: "Old Pull", exercises: [
            makeExercise(id: "a", name: "Row", position: 0, sets: 4, reps: "8", rest: "90"),
            makeExercise(id: "b", name: "Curl", position: 1, sets: nil, reps: nil, rest: nil, notes: "slow"),
        ])
        defaults.set(try legacyBlob([legacy]), forKey: Self.legacyKey)

        let store = CustomRoutineStore(defaults: defaults, userDB: db)

        XCTAssertEqual(store.routines.map(\.id), ["legacy-1"])
        let imported = try XCTUnwrap(db.routine(id: "legacy-1"))
        XCTAssertEqual(imported.name, "Old Pull")
        XCTAssertEqual(imported.createdAt, fixedDate)
        XCTAssertEqual(imported.exercises.map(\.name), ["Row", "Curl"])
        XCTAssertEqual(imported.exercises[0].sets, 4)
        XCTAssertNil(imported.exercises[1].sets)
        XCTAssertEqual(imported.exercises[1].notes, "slow")
        XCTAssertNil(defaults.data(forKey: Self.legacyKey), "the legacy key is removed after the copy")
        XCTAssertTrue(defaults.bool(forKey: Self.migrationFlag))
    }

    func test_migration_secondLaunchIsNoop() throws {
        let defaults = isolatedDefaults()
        let db = UserDatabase(path: ":memory:")
        defaults.set(try legacyBlob([makeRoutine(id: "first")]), forKey: Self.legacyKey)
        _ = CustomRoutineStore(defaults: defaults, userDB: db)

        // A blob written after the flag (a downgrade, a restored defaults
        // file) is left alone on the next launch.
        defaults.set(try legacyBlob([makeRoutine(id: "late")]), forKey: Self.legacyKey)
        let second = CustomRoutineStore(defaults: defaults, userDB: db)

        XCTAssertEqual(second.routines.map(\.id), ["first"])
        XCTAssertNil(db.routine(id: "late"))
        XCTAssertNotNil(defaults.data(forKey: Self.legacyKey))
    }

    func test_migration_noLegacyBlob_setsFlagAndImportsNothing() {
        let defaults = isolatedDefaults()
        let db = UserDatabase(path: ":memory:")
        let store = CustomRoutineStore(defaults: defaults, userDB: db)
        XCTAssertTrue(store.routines.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: Self.migrationFlag))
    }

    /// Pins today's behavior: an undecodable blob sets the flag (the `defer`)
    /// and keeps the key, so it is never retried and never deleted.
    func test_migration_undecodableBlob_setsFlag_keepsKey_importsNothing() {
        let defaults = isolatedDefaults()
        let db = UserDatabase(path: ":memory:")
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: Self.legacyKey)

        let store = CustomRoutineStore(defaults: defaults, userDB: db)

        XCTAssertTrue(store.routines.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: Self.migrationFlag))
        XCTAssertEqual(defaults.data(forKey: Self.legacyKey), junk)
    }

    // MARK: routine(id:)

    func test_routineById_returnsExercisesInPositionOrder() throws {
        let db = UserDatabase(path: ":memory:")
        db.save(makeRoutine(id: "r-order", name: "Legs", exercises: [
            makeExercise(id: "x2", name: "Second", position: 1),
            makeExercise(id: "x0", name: "First", position: 0),
            makeExercise(id: "x5", name: "Third", position: 5),
        ]))
        let got = try XCTUnwrap(db.routine(id: "r-order"))
        XCTAssertEqual(got.name, "Legs")
        XCTAssertEqual(got.exercises.map(\.name), ["First", "Second", "Third"])
        XCTAssertEqual(got.exercises.map(\.id), ["x0", "x2", "x5"])
    }

    func test_routineById_unknownIdIsNil() {
        let db = UserDatabase(path: ":memory:")
        db.save(makeRoutine(id: "present"))
        XCTAssertNil(db.routine(id: "absent"))
    }

    func test_save_sameIdReplacesExerciseList() throws {
        let db = UserDatabase(path: ":memory:")
        db.save(makeRoutine(id: "r", name: "v1", exercises: [
            makeExercise(id: "old-a", position: 0), makeExercise(id: "old-b", position: 1),
        ]))
        db.save(makeRoutine(id: "r", name: "v2", exercises: [makeExercise(id: "new-a", position: 0)]))
        let got = try XCTUnwrap(db.routine(id: "r"))
        XCTAssertEqual(got.name, "v2")
        XCTAssertEqual(got.exercises.map(\.id), ["new-a"])
        XCTAssertEqual(db.routineCount(), 1)
    }

    // MARK: delete(routineId:)

    func test_delete_removesRoutineAndItsExercises_leavesOthers() throws {
        let db = UserDatabase(path: ":memory:")
        db.save(makeRoutine(id: "gone", exercises: [
            makeExercise(id: "g0", position: 0), makeExercise(id: "g1", position: 1),
        ]))
        db.save(makeRoutine(id: "kept", exercises: [makeExercise(id: "k0", position: 0)]))

        db.delete(routineId: "gone")

        XCTAssertNil(db.routine(id: "gone"))
        XCTAssertEqual(db.listRoutines().map(\.id), ["kept"])
        XCTAssertEqual(db.routine(id: "kept")?.exercises.map(\.id), ["k0"])
        // Exercise row ids are the table's primary key: an orphaned "g0"
        // would make this insert fail and the routine load with no rows.
        db.save(makeRoutine(id: "reuse", exercises: [makeExercise(id: "g0", position: 0)]))
        XCTAssertEqual(db.routine(id: "reuse")?.exercises.map(\.id), ["g0"])
    }

    func test_delete_unknownIdIsNoop() {
        let db = UserDatabase(path: ":memory:")
        db.save(makeRoutine(id: "kept"))
        db.delete(routineId: "never-saved")
        XCTAssertEqual(db.listRoutines().map(\.id), ["kept"])
    }

    /// A Week override names the routine by id. Deleting the routine through
    /// the store leaves the override in place and the next generate serves
    /// the planner's day.
    func test_delete_routineReferencedByPlanDay_regenServesPlannerDay() throws {
        var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 11
        let monday = try XCTUnwrap(Calendar.current.date(from: c))
        let plan = PlanStore(defaults: isolatedDefaults("plan"), today: monday)
        var memory = TrainingMemory()
        memory.equipment = [.fullGym]
        memory.experience = .intermediate
        memory.sessionMinutes = 60
        memory.liftDaysPerWeek = 3
        let baseline = plan.generate(from: memory, today: monday)
        let liftDay = try XCTUnwrap(baseline.days.first { $0.kind == .lift })

        let custom = CustomRoutineStore(defaults: isolatedDefaults("custom"),
                                        userDB: UserDatabase(path: ":memory:"))
        let routine = makeRoutine(id: "rid-plan", name: "Garage Legs",
                                  exercises: [makeExercise(id: "p0", exerciseId: 101, position: 0)])
        custom.save(routine)
        plan.customStore = custom
        plan.updateOverrides(today: monday) { $0.customRoutineByDate[liftDay.date] = routine.id }
        let withOverride = plan.generate(from: memory, today: monday)
        XCTAssertTrue(withOverride.days.contains { $0.title == "Garage Legs" })

        custom.delete(routine)

        XCTAssertEqual(plan.overrides.customRoutineId(for: liftDay.date), "rid-plan",
                       "delete does not touch the override; generate skips the dangling id")
        let regen = plan.generate(from: memory, today: monday)
        XCTAssertEqual(regen.days.map(\.title), baseline.days.map(\.title))
        XCTAssertFalse(regen.days.contains { $0.generatedReason == "Your saved workout" })
    }

    /// A finished session started from the routine keeps its own copy of the
    /// exercises in the sessions table. Deleting the routine leaves it, and
    /// the "last time" lookup by template id, intact.
    func test_delete_routineWithSavedSession_keepsSessionHistory() throws {
        let db = UserDatabase(path: ":memory:")
        let defaults = isolatedDefaults()
        let custom = CustomRoutineStore(defaults: defaults, userDB: db)
        let sessions = SessionStore(defaults: defaults, userDB: db)
        let routine = makeRoutine(id: "rid-hist", name: "Push Day",
                                  exercises: [makeExercise(id: "h0", position: 0)])
        custom.save(routine)
        let templateId = routine.toWorkoutTemplate().id
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        sessions.saveAll([SavedSession(
            templateId: templateId, name: "Push Day", category: "Custom", startTime: start,
            exercises: [LoggedExercise(
                id: "cex-h0", name: "Test Move", type: nil, unit: "bw",
                targetSets: 1, targetReps: 10, rest: 60,
                sets: [LoggedSet(num: 1, weight: "", reps: "10", rpe: "", done: true)],
                prevSets: [])],
            feel: nil, note: nil, endTime: start.addingTimeInterval(1800), duration: 1800)])

        custom.delete(routine)

        XCTAssertTrue(custom.routines.isEmpty)
        let reloaded = SessionStore(defaults: defaults, userDB: db)
        XCTAssertEqual(reloaded.savedSessions.map(\.templateId), [templateId])
        XCTAssertEqual(reloaded.getPreviousSession(templateId: templateId)?.exercises.first?.name,
                       "Test Move")
    }

    // MARK: - Persistence

    /// 11c 3.9: a saved workout with two grouped rows reloads from user.db
    /// with both groups intact, and an ungrouped row stays nil.
    func test_savedRoutine_supersetGroupsSurviveReload() throws {
        let db = UserDatabase(path: ":memory:")
        db.save(makeRoutine(id: "r-ss", exercises: [
            makeExercise(id: "a", position: 0, supersetGroup: 1),
            makeExercise(id: "b", position: 1, supersetGroup: 1),
            makeExercise(id: "c", position: 2, supersetGroup: nil),
            makeExercise(id: "d", position: 3, supersetGroup: 2),
            makeExercise(id: "e", position: 4, supersetGroup: 2),
        ]))
        let got = try XCTUnwrap(db.routine(id: "r-ss"))
        XCTAssertEqual(got.exercises.map(\.supersetGroup), [1, 1, nil, 2, 2])
        XCTAssertEqual(db.listRoutines().first?.exercises.map(\.supersetGroup), [1, 1, nil, 2, 2])
        let template = got.toWorkoutTemplate()
        XCTAssertEqual(template.exercises.map(\.supersetGroup), [1, 1, nil, 2, 2])
    }
}
