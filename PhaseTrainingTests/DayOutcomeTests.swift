// DayOutcomeTests.swift — A2: planned-vs-actual per saved session.
//
// Covers DayOutcome.derive (one fixture per classification plus the diff
// cases), PlanStore's log (dedupe, 90-day trim, persistence, restore reload),
// and SessionStore.onSessionSaved firing exactly once per save.

import XCTest
@testable import PhaseTraining

final class DayOutcomeTests: XCTestCase {

    // MARK: - Fixtures

    private let day = Date(timeIntervalSince1970: 1_758_499_200) // a Monday, 2025-09-22 UTC

    private func gex(_ id: String, _ name: String, sets: Int = 3) -> GeneratedExercise {
        GeneratedExercise(id: id, exerciseId: abs(id.hashValue % 10_000), name: name,
                          pattern: nil, isCompound: false,
                          sets: sets, reps: "8", restSeconds: 90)
    }

    private var plannedWorkout: GeneratedWorkout {
        GeneratedWorkout(title: "Lower A", summary: "test",
                         exercises: [gex("a", "Back Squat"), gex("b", "Romanian Deadlift"),
                                     gex("c", "Walking Lunge", sets: 2)],
                         estimatedMinutes: 50, provenance: "test")
    }

    private func liftDay(_ workout: GeneratedWorkout? = nil, kind: DayKind = .lift) -> DayPlan {
        DayPlan(date: day, kind: kind, title: "Lower A", routineId: nil,
                generatedWorkout: kind == .lift ? (workout ?? plannedWorkout) : nil,
                generatedReason: "test")
    }

    private func sets(done: Int, total: Int, warmups: Int = 0) -> [LoggedSet] {
        var out: [LoggedSet] = []
        for i in 0..<warmups {
            var s = LoggedSet(num: i + 1, weight: "45", reps: "10", rpe: "", done: true)
            s.isWarmup = true
            out.append(s)
        }
        for i in 0..<total {
            out.append(LoggedSet(num: warmups + i + 1, weight: "100", reps: "8", rpe: "", done: i < done))
        }
        return out
    }

    private func logged(_ id: String, _ name: String, done: Int, total: Int, warmups: Int = 0) -> LoggedExercise {
        LoggedExercise(id: id, name: name, type: nil, unit: "lbs",
                       targetSets: total, targetReps: 8, rest: 90,
                       sets: sets(done: done, total: total, warmups: warmups), prevSets: [])
    }

    private func session(_ exercises: [LoggedExercise], templateId: String = "gen-x",
                         offset: TimeInterval = 18 * 3600) -> SavedSession {
        let start = day.addingTimeInterval(offset)
        return SavedSession(templateId: templateId, name: "Lower A", category: "Generated",
                            startTime: start, exercises: exercises, feel: nil, note: nil,
                            endTime: start.addingTimeInterval(2700), duration: 2700)
    }

    /// The session exactly as planned: every planned row, all sets done.
    private var faithfulRows: [LoggedExercise] {
        [logged("gex-a", "Back Squat", done: 3, total: 3),
         logged("gex-b", "Romanian Deadlift", done: 3, total: 3),
         logged("gex-c", "Walking Lunge", done: 2, total: 2)]
    }

    private func derive(_ s: SavedSession, plannedDay: DayPlan? = nil,
                        displaced: DisplacedPlan? = nil, abandoned: Bool = false) -> DayOutcome {
        DayOutcome.derive(session: s, plannedDay: plannedDay ?? liftDay(), displaced: displaced,
                          abandoned: abandoned, targetMinutes: 45, now: day)
    }

    // MARK: - Classification

    func test_asPlanned() {
        let o = derive(session(faithfulRows))
        XCTAssertEqual(o.kind, .asPlanned)
        XCTAssertEqual(o.plannedWorkingSets, 8)
        XCTAssertEqual(o.completedWorkingSets, 8)
        XCTAssertEqual(o.plannedExercises, ["Back Squat", "Romanian Deadlift", "Walking Lunge"])
        XCTAssertEqual(o.durationMinutes, 45)
        XCTAssertEqual(o.plannedMinutes, 50)
        XCTAssertEqual(o.targetMinutes, 45)
    }

    func test_swap_isModifiedWithThePair() {
        var rows = faithfulRows
        rows[1].name = "Single-Leg RDL"   // LogScreen.swapExercise renames in place, id kept
        let o = derive(session(rows))
        XCTAssertEqual(o.kind, .modified)
        XCTAssertEqual(o.swaps, [ExerciseSwapPair(planned: "Romanian Deadlift", logged: "Single-Leg RDL")])
        XCTAssertTrue(o.dropped.isEmpty)
    }

    func test_removedRowAndZeroSetRow_bothCountAsDropped() {
        let rows = [logged("gex-a", "Back Squat", done: 3, total: 3),
                    logged("gex-b", "Romanian Deadlift", done: 0, total: 3)]
        let o = derive(session(rows))
        XCTAssertEqual(o.kind, .modified)
        XCTAssertEqual(Set(o.dropped), ["Romanian Deadlift", "Walking Lunge"])
    }

    func test_addedExercise_isModified() {
        let o = derive(session(faithfulRows + [logged("ad-hoc-1", "Nordic Curl", done: 2, total: 2)]))
        XCTAssertEqual(o.kind, .modified)
        XCTAssertEqual(o.added, ["Nordic Curl"])
    }

    func test_addedRowWithNoWorkDone_isIgnored() {
        let o = derive(session(faithfulRows + [logged("ad-hoc-1", "Nordic Curl", done: 0, total: 2)]))
        XCTAssertEqual(o.kind, .asPlanned)
    }

    func test_fewerSets_isModified() {
        var rows = faithfulRows
        rows[0] = logged("gex-a", "Back Squat", done: 2, total: 3)
        let o = derive(session(rows))
        XCTAssertEqual(o.kind, .modified)
        XCTAssertEqual(o.completedWorkingSets, 7)
    }

    func test_warmupSets_doNotCountAsWorkingSets() {
        var rows = faithfulRows
        rows[0] = logged("gex-a", "Back Squat", done: 2, total: 3, warmups: 2)
        let o = derive(session(rows))
        XCTAssertEqual(o.completedWorkingSets, 7, "two done warmups must not cover the missing working set")
        XCTAssertEqual(o.kind, .modified)
    }

    func test_displacedDay_isSwitched_andRecordsThePlannersOriginal() {
        let custom = GeneratedWorkout(title: "My Pull Day", summary: "custom",
                                      exercises: [gex("z", "Pull-Up")], estimatedMinutes: 30, provenance: "test")
        let displaced = DisplacedPlan(kind: .lift, title: "Lower A", workout: plannedWorkout,
                                      reason: nil, routineId: nil)
        let o = derive(session([logged("custom-row", "Pull-Up", done: 3, total: 3)],
                               templateId: "custom-abc"),
                       plannedDay: liftDay(custom), displaced: displaced)
        XCTAssertEqual(o.kind, .switched)
        XCTAssertEqual(o.plannedExercises, ["Back Squat", "Romanian Deadlift", "Walking Lunge"],
                       "a switched day must record what the PLANNER wanted, not the switch")
        XCTAssertTrue(o.swaps.isEmpty && o.dropped.isEmpty && o.added.isEmpty)
    }

    func test_routineStartedDirectly_isSwitched() {
        let o = derive(session([logged("lib-1", "Deadlift", done: 3, total: 3)], templateId: "routine-42"))
        XCTAssertEqual(o.kind, .switched)
    }

    func test_restDay_isUnplanned() {
        let o = derive(session(faithfulRows), plannedDay: liftDay(kind: .rest))
        XCTAssertEqual(o.kind, .unplanned)
        XCTAssertEqual(o.plannedDayKind, .rest)
    }

    func test_noPlan_isUnplanned() {
        let o = DayOutcome.derive(session: session(faithfulRows), plannedDay: nil, displaced: nil,
                                  abandoned: false, targetMinutes: nil, now: day)
        XCTAssertEqual(o.kind, .unplanned)
        XCTAssertNil(o.plannedDayKind)
    }

    func test_abandoned_overridesClassificationButKeepsTheDiff() {
        let rows = [logged("gex-a", "Back Squat", done: 1, total: 3)]
        let o = derive(session(rows), abandoned: true)
        XCTAssertEqual(o.kind, .abandoned)
        XCTAssertEqual(Set(o.dropped), ["Romanian Deadlift", "Walking Lunge"])
    }

    // MARK: - PlanStore log

    private func freshDefaults() -> UserDefaults {
        let suite = "day-outcome-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_insert_isIdempotentPerSession() {
        let store = PlanStore(defaults: freshDefaults(), today: day)
        let s = session(faithfulRows)
        store.insertOutcome(derive(s), now: day)
        store.insertOutcome(derive(s, abandoned: true), now: day)
        XCTAssertEqual(store.dayOutcomes.count, 1)
        XCTAssertEqual(store.dayOutcomes.first?.kind, .abandoned, "a re-record replaces")
    }

    func test_insert_trimsToRetentionWindow() {
        let store = PlanStore(defaults: freshDefaults(), today: day)
        var old = derive(session(faithfulRows, offset: 0))
        old.recordedAt = day.addingTimeInterval(-Double(PlanStore.planOverridesRetentionDays + 1) * 86_400)
        store.insertOutcome(old, now: day)
        store.insertOutcome(derive(session(faithfulRows, offset: 3600)), now: day)
        XCTAssertEqual(store.dayOutcomes.count, 1)
    }

    func test_log_persistsAcrossRelaunch_andReloadsAfterRestore() {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: day)
        store.insertOutcome(derive(session(faithfulRows)), now: day)
        XCTAssertEqual(PlanStore(defaults: defaults, today: day).dayOutcomes.count, 1)

        // Simulate a restore writing a different log underneath a live store.
        let restored = [derive(session(faithfulRows, offset: 3600)), derive(session(faithfulRows, offset: 7200))]
        defaults.set(try? PlanStore.encoder().encode(restored), forKey: PlanStore.dayOutcomesKey)
        store.reloadFromDefaults(today: day)
        XCTAssertEqual(store.dayOutcomes.count, 2)
    }

    func test_clear_removesTheLog() {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: day)
        store.insertOutcome(derive(session(faithfulRows)), now: day)
        store.clear()
        XCTAssertTrue(store.dayOutcomes.isEmpty)
        XCTAssertNil(defaults.object(forKey: PlanStore.dayOutcomesKey))
    }

    // MARK: - SessionStore hook fires once per save

    private func active(done: Int, total: Int) -> ActiveSession {
        ActiveSession(templateId: "t1", name: "Lower A", category: "lift", startTime: day,
                      exercises: [logged("gex-a", "Back Squat", done: done, total: total)],
                      feel: nil, note: nil)
    }

    func test_saveCompleted_firesHookOnce_notAbandoned() {
        let store = SessionStore(defaults: freshDefaults())
        var calls: [Bool] = []
        store.onSessionSaved = { _, abandoned in calls.append(abandoned) }
        _ = store.saveCompleted(active(done: 3, total: 3), feel: nil, note: nil,
                                endTime: day.addingTimeInterval(1800))
        XCTAssertEqual(calls, [false])
    }

    func test_saveAbandoned_firesHookOnce_withVerdict() {
        let store = SessionStore(defaults: freshDefaults())
        var calls: [Bool] = []
        store.onSessionSaved = { _, abandoned in calls.append(abandoned) }
        store.saveAbandoned(active(done: 1, total: 4), reason: .timeOut, note: nil,
                            endTime: day.addingTimeInterval(900))
        store.saveAbandoned(active(done: 4, total: 4), reason: .timeOut, note: nil,
                            endTime: day.addingTimeInterval(86_400))
        XCTAssertEqual(calls, [true, false], "below threshold is abandoned; a full stop-early save is not")
    }

    // MARK: - Backup

    func test_backupEnvelope_roundTripsOutcomes_andOldBackupsStillDecode() throws {
        let env = BackupEnvelope(exportedAt: day, memory: nil, savedSessions: [], activeSession: nil,
                                 customRoutines: [], plan: nil, overrides: nil, reminderEnabled: false,
                                 dayOutcomes: [derive(session(faithfulRows))])
        let data = try JSONEncoder().encode(env)
        XCTAssertEqual(try JSONDecoder().decode(BackupEnvelope.self, from: data).dayOutcomes.count, 1)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "dayOutcomes")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(BackupEnvelope.self, from: old).dayOutcomes.count, 0)
    }
}
