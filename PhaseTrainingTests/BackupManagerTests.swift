import XCTest
@testable import PhaseTraining

final class BackupManagerTests: XCTestCase {

    private func freshDefaults(_ suite: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: "BackupManagerTests.\(suite)")!
        d.removePersistentDomain(forName: "BackupManagerTests.\(suite)")
        return d
    }

    // MARK: - Round-trip

    func test_emptyDefaults_roundTripCleanly() throws {
        let defaults = freshDefaults()
        let envelope = BackupManager.snapshot(defaults: defaults)
        let data = try BackupManager.encode(envelope)
        let decoded = try BackupManager.decode(data)
        XCTAssertEqual(decoded.schemaVersion, BackupEnvelope.currentSchemaVersion)
        XCTAssertNil(decoded.memory)
        XCTAssertTrue(decoded.savedSessions.isEmpty)
        XCTAssertTrue(decoded.customRoutines.isEmpty)
        XCTAssertNil(decoded.plan)
        XCTAssertNil(decoded.overrides)
        XCTAssertFalse(decoded.reminderEnabled)
    }

    func test_fullDataRoundTrip_preservesEverything() throws {
        let original = freshDefaults("original")
        // Customs + saved sessions live in user.db. Each world (original vs.
        // restored) gets its own isolated in-memory UserDatabase that's
        // threaded through both the stores AND BackupManager so snapshot /
        // restore see the same data the stores wrote.
        let originalDB = UserDatabase(path: ":memory:")
        let restoredDB = UserDatabase(path: ":memory:")

        // Populate every store
        let memoryStore = MemoryStore(defaults: original)
        memoryStore.update { mem in
            mem.experience = .advanced
            mem.age = 28
            mem.equipment = [.fullGym]
        }
        memoryStore.completeOnboarding()

        let sessionStore = SessionStore(defaults: original, userDB: originalDB)
        let active = ActiveSession(
            templateId: "t1", name: "Push", category: "cat",
            startTime: Date(),
            exercises: [],
            feel: nil, note: nil
        )
        sessionStore.saveActive(active)

        let customStore = CustomRoutineStore(defaults: original, userDB: originalDB)
        customStore.save(CustomRoutine(
            id: "abc", name: "My push", exercises: [], createdAt: Date()
        ))

        let planStore = PlanStore(defaults: original)
        _ = planStore.generate(from: memoryStore.memory)

        // Snapshot + encode + decode + restore into a FRESH defaults bucket
        let envelope = BackupManager.snapshot(defaults: original, userDB: originalDB)
        let data = try BackupManager.encode(envelope)
        let decoded = try BackupManager.decode(data)

        let restored = freshDefaults("restored")
        try BackupManager.restore(decoded, into: restored, userDB: restoredDB)

        let restoredMemory = MemoryStore(defaults: restored)
        let restoredSession = SessionStore(defaults: restored, userDB: restoredDB)
        let restoredCustom = CustomRoutineStore(defaults: restored, userDB: restoredDB)
        let restoredPlan = PlanStore(defaults: restored)

        XCTAssertEqual(restoredMemory.memory.experience, .advanced)
        XCTAssertEqual(restoredMemory.memory.age, 28)
        XCTAssertEqual(restoredMemory.memory.equipment, [.fullGym])
        XCTAssertTrue(restoredMemory.isOnboarded)

        XCTAssertNotNil(restoredSession.active)
        XCTAssertEqual(restoredSession.active?.templateId, "t1")

        XCTAssertEqual(restoredCustom.routines.count, 1)
        XCTAssertEqual(restoredCustom.routines.first?.name, "My push")

        XCTAssertNotNil(restoredPlan.plan)
        XCTAssertEqual(restoredPlan.plan?.days.count, 7)
    }

    // MARK: - Schema version guard

    func test_decode_rejectsNewerSchema() throws {
        // Build a JSON envelope claiming schemaVersion+1 — we should refuse.
        let future = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion + 1,
            exportedAt: Date(),
            memory: nil, savedSessions: [], activeSession: nil,
            customRoutines: [], plan: nil, overrides: nil,
            reminderEnabled: false
        )
        let data = try BackupManager.encode(future)
        XCTAssertThrowsError(try BackupManager.decode(data)) { err in
            guard case BackupError.schemaUnsupported(let v) = err else {
                return XCTFail("Expected schemaUnsupported, got \(err)")
            }
            XCTAssertEqual(v, BackupEnvelope.currentSchemaVersion + 1)
        }
    }

    func test_decode_rejectsGarbageJSON() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try BackupManager.decode(garbage)) { err in
            guard case BackupError.decode = err else {
                return XCTFail("Expected decode error, got \(err)")
            }
        }
    }

    // MARK: - Restore is destructive

    func test_restore_overwritesExistingData() throws {
        let defaults = freshDefaults()

        // Seed with old data
        let memoryStore = MemoryStore(defaults: defaults)
        memoryStore.update { $0.age = 50 }

        // Build a backup with different data
        var fresh = TrainingMemory()
        fresh.age = 25
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            exportedAt: Date(),
            memory: fresh,
            savedSessions: [], activeSession: nil,
            customRoutines: [], plan: nil, overrides: nil,
            reminderEnabled: false
        )

        try BackupManager.restore(envelope, into: defaults)

        let restored = MemoryStore(defaults: defaults)
        XCTAssertEqual(restored.memory.age, 25,
                       "Restore should overwrite the pre-existing age")
    }

    // MARK: - Restore is atomic

    func test_restore_failingMidway_keepsPriorData() throws {
        let defaults = freshDefaults()
        let userDB = UserDatabase(path: ":memory:")

        // Seed prior data the failed restore must not destroy.
        let memoryStore = MemoryStore(defaults: defaults)
        memoryStore.update { $0.age = 50 }
        userDB.save(CustomRoutine(
            id: "keep", name: "Old push", exercises: [], createdAt: Date()
        ))
        userDB.saveSession(SavedSession(
            templateId: "t1", name: "Push", category: "cat",
            startTime: Date(timeIntervalSince1970: 1_000),
            exercises: [], feel: nil, note: nil,
            endTime: Date(timeIntervalSince1970: 4_000), duration: 3_000
        ))

        // Two sessions colliding on the start_time primary key can't both
        // land, so the repopulate comes up short mid-way.
        let clash = Date(timeIntervalSince1970: 9_000)
        let dup = SavedSession(
            templateId: "a", name: "A", category: "c",
            startTime: clash, exercises: [], feel: nil, note: nil,
            endTime: clash, duration: 0
        )
        var fresh = TrainingMemory()
        fresh.age = 25
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            exportedAt: Date(),
            memory: fresh,
            savedSessions: [dup, dup], activeSession: nil,
            customRoutines: [], plan: nil, overrides: nil,
            reminderEnabled: false
        )

        XCTAssertThrowsError(try BackupManager.restore(envelope, into: defaults, userDB: userDB)) { err in
            guard case BackupError.restoreIncomplete = err else {
                return XCTFail("Expected restoreIncomplete, got \(err)")
            }
        }

        // Prior rows survived the failed restore, and defaults were never
        // touched — the DB stage aborts before any UserDefaults write.
        XCTAssertEqual(userDB.listRoutines().map(\.id), ["keep"])
        XCTAssertEqual(userDB.listSavedSessions().map(\.templateId), ["t1"])
        XCTAssertEqual(MemoryStore(defaults: defaults).memory.age, 50,
                       "A failed restore must not overwrite UserDefaults")
    }

    func test_restore_failingUserDefaultsWrite_rollsBackBothStores() throws {
        let defaults = freshDefaults()
        let userDB = UserDatabase(path: ":memory:")

        // Seed prior state in BOTH stores, plus a legacy key the restore
        // would otherwise wipe at the end of the sequence.
        let memoryStore = MemoryStore(defaults: defaults)
        memoryStore.update { $0.age = 50 }
        defaults.set(true, forKey: "pt_weekly_reminder_enabled")
        defaults.set(Data("legacy".utf8), forKey: "pt_sessions")
        userDB.save(CustomRoutine(
            id: "keep", name: "Old push", exercises: [], createdAt: Date()
        ))

        // An ActiveSession whose startTime encodes to a non-finite Double:
        // jsonEncoder() (default .throw non-conforming-float strategy)
        // rejects it. The memory write (first in the sequence) has already
        // landed by then, so this exercises the mid-sequence rollback.
        let poisoned = ActiveSession(
            templateId: "t", name: "T", category: "c",
            startTime: Date(timeIntervalSince1970: .infinity),
            exercises: [], feel: nil, note: nil
        )
        var fresh = TrainingMemory()
        fresh.age = 25
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            exportedAt: Date(),
            memory: fresh,
            savedSessions: [], activeSession: poisoned,
            customRoutines: [CustomRoutine(
                id: "new", name: "New", exercises: [], createdAt: Date()
            )],
            plan: nil, overrides: nil,
            reminderEnabled: false
        )

        XCTAssertThrowsError(try BackupManager.restore(envelope, into: defaults, userDB: userDB)) { err in
            guard case BackupError.restoreIncomplete = err else {
                return XCTFail("Expected restoreIncomplete, got \(err)")
            }
        }

        // pt_training_memory was already overwritten (age 25) before the
        // active-session encode threw — the rollback must put age 50 back,
        // restore every other touched key, and undo the SQLite populate.
        XCTAssertEqual(MemoryStore(defaults: defaults).memory.age, 50,
                       "Memory written before the failure must be rolled back")
        XCTAssertNil(defaults.data(forKey: "pt_active_session"))
        XCTAssertTrue(defaults.bool(forKey: "pt_weekly_reminder_enabled"))
        XCTAssertEqual(defaults.data(forKey: "pt_sessions"), Data("legacy".utf8),
                       "Legacy keys must survive a failed restore")
        XCTAssertEqual(userDB.listRoutines().map(\.id), ["keep"],
                       "The already-populated SQLite half must be rolled back too")
    }

    // MARK: - Memory schema fingerprint

    func test_snapshot_pinsMemorySchemaVersion() throws {
        let defaults = freshDefaults()
        let memoryStore = MemoryStore(defaults: defaults)
        memoryStore.update { $0.age = 30 }

        let envelope = BackupManager.snapshot(defaults: defaults)
        XCTAssertEqual(envelope.memorySchemaVersion, BackupEnvelope.currentMemorySchemaVersion)

        let decoded = try BackupManager.decode(try BackupManager.encode(envelope))
        XCTAssertEqual(decoded.memorySchemaVersion, BackupEnvelope.currentMemorySchemaVersion)
        XCTAssertFalse(decoded.isMemorySchemaStale)
    }

    func test_decode_oldBackupWithoutFingerprint_isStaleButAccepted() throws {
        // A backup written before memorySchemaVersion existed: the field is
        // absent from the JSON and the embedded memory carries an old schema
        // version. It must decode fine — old backups are never rejected —
        // and read as stale via the payload-version fallback.
        var old = TrainingMemory()
        old.schemaVersion = 2
        old.age = 40
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            exportedAt: Date(),
            memory: old,
            savedSessions: [], activeSession: nil,
            customRoutines: [], plan: nil, overrides: nil,
            reminderEnabled: false
        )
        let decoded = try BackupManager.decode(try BackupManager.encode(envelope))
        XCTAssertNil(decoded.memorySchemaVersion)
        XCTAssertTrue(decoded.isMemorySchemaStale)
        XCTAssertEqual(decoded.memory?.age, 40)
    }

    func test_envelopeWithoutMemory_isNeverStale() {
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            exportedAt: Date(),
            memory: nil, savedSessions: [], activeSession: nil,
            customRoutines: [], plan: nil, overrides: nil,
            reminderEnabled: false
        )
        XCTAssertFalse(envelope.isMemorySchemaStale,
                       "No memory payload means nothing can be stale")
    }
}
