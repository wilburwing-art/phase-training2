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
            mem.focuses = [.hypertrophy]
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
        XCTAssertEqual(restoredMemory.memory.focuses, [.hypertrophy])
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
}
