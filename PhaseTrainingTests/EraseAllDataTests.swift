import XCTest
@testable import PhaseTraining

/// Covers the canonical full-erase path (`MemoryStore.wipeAllUserData`) used by
/// BOTH the production "Erase all my data" action and `--ui-test-reset`. The
/// regression this guards: data now lives in two layers (UserDefaults +
/// SQLite), and the old hand-kept key list silently under-deleted. The wipe
/// must clear every `pt_`-prefixed default AND the on-disk store, while leaving
/// foreign (non-`pt_`) defaults alone.
final class EraseAllDataTests: XCTestCase {

    private func freshDefaults(_ tag: String) -> UserDefaults {
        let suite = "EraseAllDataTests.\(tag).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_wipeAllUserData_sweepsEveryPtKey_keepsForeignKeys() {
        let defaults = freshDefaults("sweep")
        defaults.set("v", forKey: "pt_training_memory")
        defaults.set("v", forKey: "pt_sport_logs")
        defaults.set("v", forKey: "pt_coach_archive_2026-01-01") // prefix-keyed archive
        defaults.set("v", forKey: "pt_custom_routines_migrated_v1")
        defaults.set("keep", forKey: "SomeForeignSDKKey")         // not ours — must survive

        MemoryStore.wipeAllUserData(defaults: defaults, userDB: UserDatabase(path: ":memory:"))

        for key in ["pt_training_memory", "pt_sport_logs",
                    "pt_coach_archive_2026-01-01", "pt_custom_routines_migrated_v1"] {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be swept")
        }
        XCTAssertEqual(defaults.string(forKey: "SomeForeignSDKKey"), "keep",
                       "non-pt_ keys must not be touched")
    }

    func test_wipeAllUserData_clearsSqliteStore() {
        let defaults = freshDefaults("sqlite")
        let db = UserDatabase(path: ":memory:")
        let custom = CustomRoutineStore(defaults: defaults, userDB: db)
        custom.save(CustomRoutine(id: "r1", name: "Test", exercises: [], createdAt: Date()))
        XCTAssertEqual(custom.routines.count, 1)

        MemoryStore.wipeAllUserData(defaults: defaults, userDB: db)

        // Re-read from the now-wiped DB — the SQLite layer must be empty too.
        let reloaded = CustomRoutineStore(defaults: defaults, userDB: db)
        XCTAssertTrue(reloaded.routines.isEmpty,
                      "custom routines live in SQLite and must be gone after a full wipe")
    }

    func test_userDatabaseWipeAll_clearsRoutines() {
        let db = UserDatabase(path: ":memory:")
        db.save(CustomRoutine(id: "r1", name: "A", exercises: [], createdAt: Date()))
        XCTAssertFalse(db.listRoutines().isEmpty)
        db.wipeAll()
        XCTAssertTrue(db.listRoutines().isEmpty)
    }
}
