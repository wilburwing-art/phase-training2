// UserExerciseStoreTests — the user.db custom-exercise store
// (UserDatabase+UserExercises.swift): create rules, identity, delete.

import XCTest
import SQLite3
@testable import PhaseTraining

final class UserExerciseStoreTests: XCTestCase {

    private func freshDB() -> UserDatabase { UserDatabase(path: ":memory:") }

    private func create(_ db: UserDatabase, _ name: String, bucket: MuscleBucket? = nil,
                        notes: String? = nil) throws -> UserExercise {
        try db.createUserExercise(name: name, muscleBucket: bucket, notes: notes).get()
    }

    // MARK: - Create, list, find

    func test_create_thenList_thenFindByNameIgnoringCaseAndPadding() throws {
        let db = freshDB()
        let made = try create(db, "  Zorblax Sled Push ", bucket: .quads, notes: "on the turf")
        XCTAssertEqual(made.name, "Zorblax Sled Push", "name is stored trimmed")
        XCTAssertEqual(made.muscleBucket, MuscleBucket.quads.rawValue)
        XCTAssertEqual(made.notes, "on the turf")

        XCTAssertEqual(db.listUserExercises(), [made])
        XCTAssertEqual(db.userExercise(named: "zorblax SLED push"), made)
        XCTAssertEqual(db.userExercise(named: "\tZorblax Sled Push  \n"), made)
        XCTAssertEqual(db.userExercise(id: made.id), made)
        XCTAssertNil(db.userExercise(named: "Zorblax Sled"), "lookup is exact, not a prefix match")
    }

    func test_list_isOrderedByNameIgnoringCase() throws {
        let db = freshDB()
        _ = try create(db, "zorblax b")
        _ = try create(db, "Zorblax A")
        _ = try create(db, "Zorblax C")
        XCTAssertEqual(db.listUserExercises().map(\.name), ["Zorblax A", "zorblax b", "Zorblax C"])
    }

    func test_blankNotes_areStoredAsNull() throws {
        let db = freshDB()
        let made = try create(db, "Zorblax Carry", notes: "   \n ")
        XCTAssertNil(made.notes)
        XCTAssertNil(db.userExercise(id: made.id)?.notes)
        XCTAssertNil(made.exercise.description)
    }

    // MARK: - Create rules

    func test_emptyName_isRejected() {
        let db = freshDB()
        XCTAssertEqual(db.createUserExercise(name: "   ", muscleBucket: nil, notes: nil), .failure(.emptyName))
        XCTAssertEqual(db.createUserExercise(name: "", muscleBucket: nil, notes: nil), .failure(.emptyName))
        XCTAssertTrue(db.listUserExercises().isEmpty)
    }

    func test_duplicateCustomName_inAnotherCase_isTaken() throws {
        let db = freshDB()
        _ = try create(db, "Zorblax Row")
        XCTAssertEqual(db.createUserExercise(name: " ZORBLAX row", muscleBucket: .back, notes: nil),
                       .failure(.nameTaken))
        XCTAssertEqual(db.listUserExercises().count, 1)
    }

    func test_catalogName_isTaken() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db not bundled")
        let catalogName = try XCTUnwrap(CoachDatabase.shared.listExercises().first?.name)
        let db = freshDB()
        XCTAssertEqual(db.createUserExercise(name: catalogName.uppercased(), muscleBucket: nil, notes: nil),
                       .failure(.nameTaken), "\(catalogName) is a catalog exercise")
        XCTAssertTrue(db.listUserExercises().isEmpty)
    }

    func test_catalogAlias_isTaken() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db not bundled")
        let catalogNames = Set(CoachDatabase.shared.listExercises().map { $0.name.lowercased() })
        let alias = try XCTUnwrap(try aliasesFromCoachDB().first { !catalogNames.contains($0.lowercased()) },
                                  "coach.db carries no alias distinct from a canonical name")
        XCTAssertNotNil(CoachDatabase.shared.exerciseId(forImportName: alias), "fixture: \(alias) resolves")
        let db = freshDB()
        XCTAssertEqual(db.createUserExercise(name: alias, muscleBucket: nil, notes: nil), .failure(.nameTaken),
                       "\(alias) is an alias of a catalog exercise")
    }

    func test_unavailableStore_reportsIt() {
        let db = UserDatabase(path: "/nonexistent-dir-\(UUID().uuidString)/user.db")
        XCTAssertFalse(db.isOpen)
        XCTAssertEqual(db.createUserExercise(name: "Zorblax", muscleBucket: nil, notes: nil),
                       .failure(.storeUnavailable))
    }

    // MARK: - Identity

    func test_exercise_isNegativeIdAndCustom() throws {
        let db = freshDB()
        let made = try create(db, "Zorblax Press", bucket: .shoulders, notes: "seated")
        let ex = made.exercise
        XCTAssertGreaterThan(made.id, 0)
        XCTAssertEqual(ex.id, -Int(made.id))
        XCTAssertTrue(ex.isCustom)
        XCTAssertEqual(ex.name, "Zorblax Press")
        XCTAssertEqual(ex.slug, "custom-\(made.id)")
        XCTAssertEqual(ex.description, "seated")
        XCTAssertFalse(ex.isCompound)
        XCTAssertNil(ex.modality)
        XCTAssertNil(ex.thumbnailURL)
    }

    func test_catalogExercises_areNotCustom() throws {
        try XCTSkipUnless(CoachDatabase.shared.isOpen, "coach.db not bundled")
        XCTAssertFalse(CoachDatabase.shared.listExercises().contains { $0.isCustom })
    }

    /// AUTOINCREMENT: deleting the highest row and creating again must not
    /// reissue its id, or a routine saved with `-id` would rebind.
    func test_ids_areNotReusedAfterDelete() throws {
        let db = freshDB()
        let a = try create(db, "Zorblax A")
        let b = try create(db, "Zorblax B")
        db.deleteUserExercise(id: b.id)
        let c = try create(db, "Zorblax C")
        XCTAssertGreaterThan(c.id, b.id)
        db.deleteUserExercise(id: a.id)
        db.deleteUserExercise(id: c.id)
        let d = try create(db, "Zorblax A")
        XCTAssertGreaterThan(d.id, c.id, "an emptied table still continues the sequence")
    }

    // MARK: - Delete

    func test_delete_removesRow_andSessionHistoryUnderTheNameStays() throws {
        let db = freshDB()
        let made = try create(db, "Zorblax Curl", bucket: .biceps)
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        db.saveSession(SavedSession(
            templateId: "t", name: "Arms", category: "c", startTime: start,
            exercises: [LoggedExercise(id: "e", name: made.name, type: nil, unit: "lbs",
                                       targetSets: 1, targetReps: 10, rest: 60,
                                       sets: [LoggedSet(num: 1, weight: "30", reps: "10", rpe: "", done: true)],
                                       prevSets: [])],
            feel: nil, note: nil, endTime: start.addingTimeInterval(1800), duration: 1800))

        db.deleteUserExercise(id: made.id)

        XCTAssertNil(db.userExercise(id: made.id))
        XCTAssertNil(db.userExercise(named: made.name))
        XCTAssertTrue(db.listUserExercises().isEmpty)
        XCTAssertEqual(db.listSavedSessions().first?.exercises.map(\.name), [made.name],
                       "logged history keeps the name after the exercise is deleted")
        XCTAssertNotNil(db.bestWeightsByExerciseAndReps()[made.name], "PRs under the name are unchanged")
    }

    // MARK: - Restore helpers

    func test_insert_keepsExplicitId_andClearEmpties() throws {
        let db = freshDB()
        let row = UserExercise(id: 42, name: "Zorblax Restored", muscleBucket: "glutes", notes: nil,
                               createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        db.insertUserExercise(row)
        XCTAssertEqual(db.userExercise(id: 42), row)
        XCTAssertGreaterThan(try create(db, "Zorblax Next").id, 42, "a restored id advances the sequence")
        db.clearUserExercises()
        XCTAssertTrue(db.listUserExercises().isEmpty)
    }

    // MARK: - Fixtures

    private func aliasesFromCoachDB() throws -> [String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "coach", ofType: "db"))
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &raw, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(raw) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(raw, "SELECT alias FROM exercise_aliases ORDER BY id", -1, &stmt, nil),
                       SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }
}
