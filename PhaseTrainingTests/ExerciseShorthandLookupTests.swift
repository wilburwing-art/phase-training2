//
//  ExerciseShorthandLookupTests.swift
//  PhaseTrainingTests
//
//  The UI shows short exercise names and coach.db stores specific ones, so
//  every row's photo, muscle bucket and substitution list depends on the
//  shorthand resolving. When it does not, the row renders a muscle-chip
//  placeholder that looks designed rather than broken, so nothing reports it.
//

import XCTest
@testable import PhaseTraining

final class ExerciseShorthandLookupTests: XCTestCase {

    /// Every shorthand in db/aliases_shorthand.sql, with the canonical row it
    /// must land on. Targets are hand-picked: an alias pointing at the wrong
    /// variant shows a plausible photo and reads as correct.
    private let shorthand: [(String, String)] = [
        ("Bench Press",      "Barbell Bench Press"),
        ("Pull Up",          "Pull-Up"),
        ("Overhead Press",   "Barbell Overhead Press (Strict)"),
        ("Incline Row",      "Incline Row (Dumbbell)"),
        ("Skullcrusher",     "Skull Crusher (Lying Triceps Extension)"),
        ("Face Pull",        "Face Pull (Cable or Band)"),
        ("Incline DB Press", "Incline Dumbbell Bench Press"),
        ("Lateral Raise",    "Dumbbell Lateral Raise"),
    ]

    private var savedUserDB: UserDatabase?

    override func setUp() {
        super.setUp()
        savedUserDB = ExerciseLookupCache.shared.userDB
        ExerciseLookupCache.shared.reset()
    }

    override func tearDown() {
        ExerciseLookupCache.shared.userDB = savedUserDB
        super.tearDown()
    }

    func testShorthandResolvesToItsCanonicalExercise() {
        for (short, canonical) in shorthand {
            let id = ExerciseLookupCache.shared.exerciseID(forName: short)
            XCTAssertNotNil(id, "\(short) did not resolve; its row renders a placeholder")
            let name = id.flatMap { CoachDatabase.shared.exercise(id: $0)?.name }
            XCTAssertEqual(name, canonical, "\(short) resolved to the wrong variant")
        }
    }

    /// The built-in fallback template and the plan generator both feed this
    /// path, so every name either side writes has to resolve.
    func testBuiltInTemplateNamesAllResolve() {
        for ex in WorkoutTemplate.upper1.exercises {
            XCTAssertNotNil(ExerciseLookupCache.shared.exerciseID(forName: ex.name),
                            "upper1 exercise '\(ex.name)' does not resolve")
        }
    }

    /// Canonical names must keep working; the fallback is additive.
    func testCanonicalNamesStillResolve() {
        let id = ExerciseLookupCache.shared.exerciseID(forName: "Barbell Bench Press")
        XCTAssertEqual(id, 900)
    }

    /// A name that means nothing must stay nil rather than fuzzy-matching
    /// onto a plausible neighbour.
    func testUnknownNameDoesNotResolve() {
        XCTAssertNil(ExerciseLookupCache.shared.exerciseID(forName: "Zorble Press"))
    }

    /// The cache stores misses. A custom exercise created after its name was
    /// looked up must still resolve, with its own bucket and no photo.
    func testCustomExerciseResolvesAfterAnEarlierMiss() throws {
        let db = UserDatabase(path: ":memory:")
        ExerciseLookupCache.shared.userDB = db
        let name = "Zorblax Sled Drag"
        XCTAssertNil(ExerciseLookupCache.shared.exercise(forName: name), "fixture: a miss gets cached first")

        let made = try db.createUserExercise(name: name, muscleBucket: .glutes, notes: nil).get()

        let hit = ExerciseLookupCache.shared.lookup(name: name.lowercased())
        XCTAssertEqual(hit.exercise?.id, -Int(made.id))
        XCTAssertEqual(hit.exercise?.isCustom, true)
        XCTAssertEqual(hit.bucket, .glutes)
        XCTAssertNil(hit.thumbnailURL)
        XCTAssertEqual(ExerciseNameLookup.anyId(name), -Int(made.id))

        db.deleteUserExercise(id: made.id)
        XCTAssertNil(ExerciseLookupCache.shared.exercise(forName: name), "a deleted custom stops resolving")
        XCTAssertNil(ExerciseNameLookup.anyId(name))
    }

    /// Catalog names keep resolving to the catalog with a custom store attached.
    func testCatalogStillWinsWithACustomStoreAttached() throws {
        let db = UserDatabase(path: ":memory:")
        _ = try db.createUserExercise(name: "Zorblax Sled Drag", muscleBucket: .glutes, notes: nil).get()
        ExerciseLookupCache.shared.userDB = db
        XCTAssertEqual(ExerciseLookupCache.shared.exerciseID(forName: "Barbell Bench Press"), 900)
        XCTAssertEqual(ExerciseNameLookup.anyId("Barbell Bench Press"), 900)
    }

    /// A wipe empties user_exercises; the cached hit must go with it.
    func testEraseDropsACachedCustomHit() throws {
        let db = UserDatabase(path: ":memory:")
        ExerciseLookupCache.shared.userDB = db
        _ = try db.createUserExercise(name: "Zorblax Sled Drag", muscleBucket: .glutes, notes: nil).get()
        XCTAssertEqual(ExerciseLookupCache.shared.exercise(forName: "Zorblax Sled Drag")?.isCustom, true)
        db.wipeAll()
        XCTAssertNil(ExerciseLookupCache.shared.exercise(forName: "Zorblax Sled Drag"))
    }

    /// Restore resets the cache once after its insert loop, so a cached miss
    /// for a restored name resolves afterwards.
    func testRestoreMakesARestoredCustomNameResolve() throws {
        let db = UserDatabase(path: ":memory:")
        ExerciseLookupCache.shared.userDB = db
        XCTAssertNil(ExerciseLookupCache.shared.exercise(forName: "Zorblax Restored"), "fixture: cached miss")
        let row = UserExercise(id: 9, name: "Zorblax Restored", muscleBucket: "back", notes: nil,
                               createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let envelope = BackupEnvelope(exportedAt: Date(), memory: nil, savedSessions: [], activeSession: nil,
                                      customRoutines: [], plan: nil, overrides: nil, reminderEnabled: false,
                                      userExercises: [row])
        let suite = "ExerciseShorthandLookupTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        try BackupManager.restore(envelope, into: UserDefaults(suiteName: suite)!, userDB: db)
        XCTAssertEqual(ExerciseLookupCache.shared.exercise(forName: "Zorblax Restored")?.id, -9)
        XCTAssertEqual(ExerciseLookupCache.shared.bucket(forName: "Zorblax Restored"), .back)
    }
}
