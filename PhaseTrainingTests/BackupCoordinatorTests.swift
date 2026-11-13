// BackupCoordinatorTests.swift — the Profile screen's erase and export/restore
// paths. BackupManagerTests covers the engine; this covers the one place that
// touches every store, so a store added later and forgotten here fails a test.
//
// Every store, defaults suite and database here is private to the test. The
// coordinator's defaults/userDB parameters default to the app's real ones.

import XCTest
@testable import PhaseTraining

@MainActor
final class BackupCoordinatorTests: XCTestCase {

    private var suites: [String] = []
    private var tempFiles: [URL] = []

    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        for f in tempFiles { try? FileManager.default.removeItem(at: f) }
        suites = []; tempFiles = []
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "backup-coord-\(UUID().uuidString)"
        suites.append(suite)
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    /// One isolated world: every store over one defaults suite and one in-memory DB.
    private struct World {
        let defaults: UserDefaults
        let db: UserDatabase
        let memory: MemoryStore
        let plan: PlanStore
        let sessions: SessionStore
        let custom: CustomRoutineStore
        let sportLog: SportLogStore
        let recentPicks: RecentPicksStore
        let conversation: CoachConversationStore
        let activity: ActivityDetectionStore
    }

    private func world() -> World {
        let d = freshDefaults()
        let db = UserDatabase(path: ":memory:")
        return World(defaults: d, db: db,
                     memory: MemoryStore(defaults: d),
                     plan: PlanStore(defaults: d, today: Date()),
                     sessions: SessionStore(defaults: d, userDB: db),
                     custom: CustomRoutineStore(defaults: d, userDB: db),
                     sportLog: SportLogStore(defaults: d),
                     recentPicks: RecentPicksStore(defaults: d),
                     conversation: CoachConversationStore(defaults: d),
                     activity: ActivityDetectionStore(defaults: d))
    }

    private func populate(_ w: World) {
        w.memory.update { m in
            m.experience = .advanced
            m.age = 31
            m.equipment = [.dumbbells, .pullUpBar]
            m.liftDaysPerWeek = 3
        }
        w.memory.completeOnboarding()
        _ = w.plan.generate(from: w.memory.memory, today: Date())
        // Staged for NEXT week: a week due now is installed on the next load,
        // which would make the round trip differ for a correct reason.
        let nextMonday = Calendar.current.date(byAdding: .day, value: 7, to: Date().startOfTrainingWeek())!
        var staged = w.plan.plan!
        staged.inputsHash = "staged"
        staged.days = staged.days.map { d in
            var d = d; d.date = Calendar.current.date(byAdding: .day, value: 7, to: d.date)!; return d
        }
        w.plan.stagePlan(staged, overrides: WeekOverrides(weekStart: nextMonday))

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        w.sessions.saveAll([SavedSession(
            templateId: "t", name: "Push", category: "c", startTime: start,
            exercises: [LoggedExercise(id: "e", name: "Bench Press", type: "Barbell", unit: "lbs",
                                       targetSets: 1, targetReps: 5, rest: 60,
                                       sets: [LoggedSet(num: 1, weight: "185", reps: "5", rpe: "8", done: true)],
                                       prevSets: [])],
            feel: nil, note: "heavy", endTime: start.addingTimeInterval(3000), duration: 3000)])
        w.sessions.saveActive(ActiveSession(templateId: "t2", name: "Pull", category: "c",
                                            startTime: Date(), exercises: [], feel: nil, note: nil))
        w.custom.save(CustomRoutine(id: "r1", name: "My push", exercises: [], createdAt: Date(timeIntervalSince1970: 1_780_000_000)))
        w.sportLog.log(sport: Sport(slug: "climbing", name: "Climbing"), on: Date(), durationMinutes: 90, intensity: .hard)
        w.recentPicks.record(exerciseIds: [11, 12])
        w.conversation.append(CoachMessage(role: "user", text: "hello"))

        w.db.insertImportedWorkouts([ImportedWorkout(id: "hk1", source: .healthKit, kind: .strength,
                                                     startTime: start, duration: 2400, energyKcal: 250)])
        w.db.insertImportedSets([
            ImportedSet(id: "s1", source: .fitbodCSV, exerciseId: nil, exerciseNameRaw: "Back Squat",
                        performedAt: start, setNum: 1, weight: 100, reps: 5, rir: nil, rpe: nil),
            ImportedSet(id: "s2", source: .fitbodCSV, exerciseId: nil, exerciseNameRaw: "Back Squat",
                        performedAt: start, setNum: 2, weight: 100, reps: 5, rir: nil, rpe: nil),
        ])
        w.db.setImportName("Mystery Lift", exerciseId: 11)
        w.db.recordExploreSession(ExploreSession(surface: .library, startedAt: start, endedAt: start,
                                                 query: "squat", resultCount: 3))
        // Two rows with a gap in the ids, so the restore has to keep ids to match.
        let dropped = try? w.db.createUserExercise(name: "Zorblax Dropped", muscleBucket: nil, notes: nil).get()
        _ = try? w.db.createUserExercise(name: "Zorblax Sled Push", muscleBucket: .quads, notes: "turf").get()
        _ = try? w.db.createUserExercise(name: "Zorblax Band Row", muscleBucket: .back, notes: nil).get()
        if let dropped { w.db.deleteUserExercise(id: dropped.id) }

        // Keys with no store API in this file, plus the unprefixed ones the sweep names.
        w.defaults.set(Data("x".utf8), forKey: "pt_coach_archive_2026-01-01")
        w.defaults.set(true, forKey: "pt_custom_routines_migrated_v1")
        w.defaults.set(true, forKey: "pt_weekly_reminder_enabled")
        w.defaults.set(["u1": 1.0], forKey: "pt_detected_activity_seen")
        for key in MemoryStore.unprefixedKeys { w.defaults.set("x", forKey: key) }
    }

    private func normalized(_ e: BackupEnvelope) throws -> Data {
        var e = e
        e.exportedAt = Date(timeIntervalSince1970: 0)
        return try BackupManager.encode(e)
    }

    private func erase(_ w: World) {
        BackupCoordinator().eraseAllData(store: w.memory, planStore: w.plan, sessionStore: w.sessions,
                                         customStore: w.custom, sportLogStore: w.sportLog,
                                         recentPicks: w.recentPicks, conversation: w.conversation,
                                         activityDetection: w.activity,
                                         defaults: w.defaults, userDB: w.db)
    }

    // MARK: - Erase

    func testFixtureActuallyFillsEveryStoreSoTheEraseTestCanFail() throws {
        let w = world()
        populate(w)
        XCTAssertTrue(w.memory.isOnboarded)
        XCTAssertNotNil(w.plan.plan)
        XCTAssertFalse(w.sessions.savedSessions.isEmpty)
        XCTAssertNotNil(w.sessions.active)
        XCTAssertFalse(w.custom.routines.isEmpty)
        XCTAssertFalse(w.sportLog.entries.isEmpty)
        XCTAssertFalse(w.recentPicks.lastPicked.isEmpty)
        XCTAssertFalse(w.conversation.messages.isEmpty)
        XCTAssertFalse(w.db.allImportedSets().isEmpty)
        XCTAssertFalse(w.db.allImportedWorkouts().isEmpty)
        XCTAssertFalse(w.db.importNameMap().isEmpty)
        XCTAssertFalse(w.db.listExploreSessions().isEmpty)
        XCTAssertEqual(w.db.listUserExercises().count, 2)
        XCTAssertTrue(w.defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("pt_") })
        let blank = world()
        XCTAssertNotEqual(try normalized(BackupManager.snapshot(defaults: w.defaults, userDB: w.db)),
                          try normalized(BackupManager.snapshot(defaults: blank.defaults, userDB: blank.db)))
    }

    func testEraseEmptiesEveryInMemoryStore() {
        let w = world()
        populate(w)
        w.defaults.set("keep", forKey: "SomeForeignSDKKey")

        erase(w)

        XCTAssertFalse(w.memory.isOnboarded)
        XCTAssertEqual(w.memory.memory.age, TrainingMemory().age)
        XCTAssertNil(w.plan.plan)
        XCTAssertTrue(w.plan.pastPlans.isEmpty)
        XCTAssertTrue(w.sessions.savedSessions.isEmpty)
        XCTAssertNil(w.sessions.active)
        XCTAssertTrue(w.custom.routines.isEmpty)
        XCTAssertTrue(w.sportLog.entries.isEmpty)
        XCTAssertTrue(w.recentPicks.lastPicked.isEmpty)
        XCTAssertTrue(w.conversation.messages.isEmpty)
        XCTAssertEqual(w.conversation.turnsToday, 0)
        XCTAssertTrue(w.activity.seenIdsForTesting.isEmpty)
        XCTAssertEqual(w.defaults.string(forKey: "SomeForeignSDKKey"), "keep", "foreign keys are not ours to delete")
    }

    func testEraseEmptiesSqliteAndEveryPtKey() {
        let w = world()
        populate(w)

        erase(w)

        XCTAssertTrue(w.db.listSavedSessions().isEmpty)
        XCTAssertTrue(w.db.listRoutines().isEmpty)
        XCTAssertTrue(w.db.allImportedWorkouts().isEmpty)
        XCTAssertTrue(w.db.allImportedSets().isEmpty)
        XCTAssertTrue(w.db.importNameMap().isEmpty)
        XCTAssertTrue(w.db.listExploreSessions().isEmpty)
        XCTAssertTrue(w.db.listUserExercises().isEmpty)
        let leftover = w.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("pt_") }.sorted()
        XCTAssertEqual(leftover, [], "pt_ keys survived the wipe")
        for key in MemoryStore.unprefixedKeys {
            XCTAssertNil(w.defaults.object(forKey: key), "\(key) survived the wipe")
        }
    }

    /// Whatever the backup knows how to carry must be gone too: a slice added to
    /// the envelope and forgotten in the wipe shows up here as a difference.
    func testErasedWorldBacksUpIdenticallyToABlankInstall() throws {
        let w = world()
        populate(w)
        erase(w)
        let blank = world()
        XCTAssertEqual(try normalized(BackupManager.snapshot(defaults: w.defaults, userDB: w.db)),
                       try normalized(BackupManager.snapshot(defaults: blank.defaults, userDB: blank.db)))
    }

    /// An app-lifetime store that keeps an in-memory copy writes it straight
    /// back on its next mutation (the sport log did exactly this). Mutate each
    /// after the erase and confirm none of the old data returns.
    func testNothingComesBackWhenStoresAreUsedAfterTheErase() {
        let w = world()
        populate(w)
        erase(w)

        w.sportLog.log(sport: Sport(slug: "running", name: "Running"), on: Date(), durationMinutes: 30, intensity: .light)
        w.recentPicks.record(exerciseIds: [99])
        w.conversation.append(CoachMessage(role: "user", text: "fresh"))
        w.memory.update { $0.age = 40 }

        XCTAssertEqual(w.sportLog.entries.count, 1)
        XCTAssertEqual(Set(w.recentPicks.lastPicked.keys), [99])
        XCTAssertEqual(w.conversation.messages.map(\.text), ["fresh"])
        XCTAssertTrue(w.sessions.savedSessions.isEmpty)
    }

    /// PlanStore.clear() resets the live week, history and logs but not the
    /// staged next week, so a staged plan from before the erase can be promoted
    /// into the fresh install on the next foreground.
    func testStagedNextWeekDoesNotSurviveTheErase() {
        let w = world()
        populate(w)
        XCTAssertNotNil(w.plan.pendingPlan)
        erase(w)
        XCTAssertNil(w.plan.pendingPlan)
    
    }

    func testEraseReEnablesActivityDetectionToTheFreshInstallDefault() {
        let w = world()
        w.activity.enabled = false
        erase(w)
        XCTAssertTrue(w.activity.enabled)
    }

    // MARK: - Export then restore

    func testExportThenRestoreRoundTripReproducesTheSameData() throws {
        let src = world()
        populate(src)
        let expected = try normalized(BackupManager.snapshot(defaults: src.defaults, userDB: src.db))

        let exporter = BackupCoordinator()
        exporter.exportBackup(defaults: src.defaults, userDB: src.db)
        XCTAssertNil(exporter.backupError)
        let url = try XCTUnwrap(exporter.exportURL)
        tempFiles.append(url)
        XCTAssertTrue(exporter.presentingShare)

        let dst = world()
        let importer = BackupCoordinator()
        importer.handleImport(.success([url]))
        XCTAssertNil(importer.backupError)
        let envelope = try XCTUnwrap(importer.pendingRestore, "decoded but not yet applied")
        XCTAssertTrue(importer.confirmingRestore)
        XCTAssertNil(dst.memory.memory.onboardedAt, "nothing is written before the user confirms")

        importer.performRestore(envelope, store: dst.memory, planStore: dst.plan,
                                sessionStore: dst.sessions, customStore: dst.custom,
                                defaults: dst.defaults, userDB: dst.db)

        XCTAssertNil(importer.backupError)
        XCTAssertTrue(importer.restoreCompleted)
        XCTAssertNil(importer.pendingRestore)
        XCTAssertEqual(try normalized(BackupManager.snapshot(defaults: dst.defaults, userDB: dst.db)), expected)

        // And the live stores reflect it without a relaunch.
        XCTAssertEqual(dst.memory.memory.experience, .advanced)
        XCTAssertEqual(dst.memory.memory.age, 31)
        XCTAssertEqual(dst.sessions.savedSessions.count, 1)
        XCTAssertEqual(dst.sessions.active?.templateId, "t2")
        XCTAssertEqual(dst.custom.routines.map(\.name), ["My push"])
        XCTAssertNotNil(dst.plan.plan)
        XCTAssertEqual(dst.db.allImportedSets().count, 2)
        XCTAssertEqual(dst.db.listUserExercises(), src.db.listUserExercises(), "same rows with the same ids")
    }

    func testRoundTripEnvelopeCarriesTheSlicesThisTestFilled() throws {
        let src = world()
        populate(src)
        let e = BackupManager.snapshot(defaults: src.defaults, userDB: src.db)
        XCTAssertNotNil(e.memory); XCTAssertNotNil(e.plan); XCTAssertNotNil(e.activeSession)
        XCTAssertEqual(e.savedSessions.count, 1)
        XCTAssertEqual(e.customRoutines.count, 1)
        XCTAssertEqual(e.sportLogs.count, 1)
        XCTAssertEqual(e.recentPicks.count, 2)
        XCTAssertEqual(e.importedWorkouts.count, 1)
        XCTAssertEqual(e.importedSets.count, 2)
        XCTAssertEqual(e.userExercises?.count, 2)
        XCTAssertNotNil(e.pendingPlan)
    }

    func testImportOfAGarbageFileReportsAnErrorAndStagesNothing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).json")
        try Data("not a backup".utf8).write(to: url)
        tempFiles.append(url)
        let c = BackupCoordinator()
        c.handleImport(.success([url]))
        XCTAssertNotNil(c.backupError)
        XCTAssertNil(c.pendingRestore)
        XCTAssertFalse(c.confirmingRestore)
    }

    func testFailedRestoreKeepsPriorDataAndReportsTheError() throws {
        let w = world()
        w.memory.update { $0.age = 50 }
        let clash = Date(timeIntervalSince1970: 9_000)
        let dup = SavedSession(templateId: "a", name: "A", category: "c", startTime: clash,
                               exercises: [], feel: nil, note: nil, endTime: clash, duration: 0)
        let envelope = BackupEnvelope(schemaVersion: BackupEnvelope.currentSchemaVersion, exportedAt: Date(),
                                      memory: TrainingMemory(), savedSessions: [dup, dup], activeSession: nil,
                                      customRoutines: [], plan: nil, overrides: nil, reminderEnabled: false)
        let c = BackupCoordinator()
        c.performRestore(envelope, store: w.memory, planStore: w.plan, sessionStore: w.sessions,
                         customStore: w.custom, defaults: w.defaults, userDB: w.db)
        XCTAssertNotNil(c.backupError)
        XCTAssertFalse(c.restoreCompleted)
        XCTAssertEqual(MemoryStore(defaults: w.defaults).memory.age, 50)
    }

    // MARK: - Last exported

    private func session(endingAt t: TimeInterval) -> SavedSession {
        let d = Date(timeIntervalSince1970: t)
        return SavedSession(templateId: "a", name: "A", category: "c", startTime: d,
                            exercises: [], feel: nil, note: nil, endTime: d, duration: 0)
    }

    func testACompletedBackupShareStampsTheExportDate() {
        let w = world()
        let c = BackupCoordinator(defaults: w.defaults)
        XCTAssertNil(c.lastBackupExport)
        c.exportBackup(defaults: w.defaults, userDB: w.db)
        if let url = c.exportURL { tempFiles.append(url) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        c.shareFinished(completed: true, defaults: w.defaults, now: now)
        XCTAssertEqual(c.lastBackupExport, now)
        XCTAssertEqual(BackupStatus.lastExport(defaults: w.defaults), now)
        XCTAssertEqual(BackupCoordinator(defaults: w.defaults).lastBackupExport, now)
    }

    func testACancelledShareAndACSVExportLeaveTheExportDateUnset() {
        let w = world()
        let c = BackupCoordinator(defaults: w.defaults)
        c.exportBackup(defaults: w.defaults, userDB: w.db)
        if let url = c.exportURL { tempFiles.append(url) }
        c.shareFinished(completed: false, defaults: w.defaults)
        XCTAssertNil(c.lastBackupExport)

        c.exportWorkoutsCSV(sessions: [session(endingAt: 1_000)], usesImperial: true)
        if let url = c.exportURL { tempFiles.append(url) }
        c.shareFinished(completed: true, defaults: w.defaults)
        XCTAssertNil(c.lastBackupExport)
        XCTAssertNil(BackupStatus.lastExport(defaults: w.defaults))
    }

    func testTheBackupFileDoesNotCarryTheExportDateAndEraseClearsIt() {
        let w = world()
        BackupStatus.recordExport(at: Date(timeIntervalSince1970: 5_000), defaults: w.defaults)
        let c = BackupCoordinator(defaults: w.defaults)
        XCTAssertNotNil(c.lastBackupExport)
        c.eraseAllData(store: w.memory, planStore: w.plan, sessionStore: w.sessions,
                       customStore: w.custom, sportLogStore: w.sportLog,
                       recentPicks: w.recentPicks, conversation: w.conversation,
                       activityDetection: w.activity, defaults: w.defaults, userDB: w.db)
        XCTAssertNil(c.lastBackupExport)
        XCTAssertNil(BackupStatus.lastExport(defaults: w.defaults))
    }

    func testDataRowReadsNeverThenADateThenTheBacklog() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_794_441_600)      // 2026-11-12 UTC
        let exported = Date(timeIntervalSince1970: 1_793_664_000) // 2026-11-03 UTC
        func row(_ last: Date?, _ sessions: [SavedSession]) -> String {
            BackupStatus.rowValue(lastExport: last, sessions: sessions, now: now,
                                  calendar: cal, locale: locale)
        }
        XCTAssertEqual(row(nil, []), "Never exported")
        XCTAssertEqual(row(exported, []), "Exported Nov 3")
        XCTAssertEqual(row(Date(timeIntervalSince1970: 1_762_128_000), []), "Exported Nov 3, 2025")

        let before = (0..<12).map { session(endingAt: exported.timeIntervalSince1970 - Double($0 + 1) * 60) }
        let after = (0..<10).map { session(endingAt: exported.timeIntervalSince1970 + Double($0 + 1) * 60) }
        XCTAssertEqual(row(exported, before + Array(after.prefix(9))), "Exported Nov 3")
        XCTAssertFalse(BackupStatus.needsNudge(lastExport: exported, sessions: before + Array(after.prefix(9))))
        XCTAssertEqual(row(exported, before + after), "10 workouts not backed up")
        XCTAssertTrue(BackupStatus.needsNudge(lastExport: exported, sessions: before + after))
        XCTAssertEqual(row(nil, before), "12 workouts not backed up")
    }
}
