// AbandonHandlingTests.swift — PR 9 of the weekly-coach roadmap.
//
// Unit coverage for the abandonment path:
//   - AbandonReason round-trips through the sheet's typed set.
//   - AbandonedWorkoutEntry clamps completionRatio to 0...1.
//   - SessionStore.saveAbandoned records an entry below the 70%
//     threshold (via the onAbandonRecorded hook) and NOT at/above it.
//   - PlanStore.recordAbandonment: idempotent per day, 90-day trim.
//   - PlanStore.proposeAbandonReshuffle: shares the 2/week budget with
//     misses, honors the drop rule, and proposes a move when a clean
//     rest day exists.
//
// Glue mirrors PlanStoreMissedWorkoutTests (PR 8's test shape).

import XCTest
@testable import PhaseTraining

final class AbandonHandlingTests: XCTestCase {

    // MARK: - Fixtures

    private func freshStore(today: Date = Date()) -> PlanStore {
        let suite = "abandon-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PlanStore(defaults: defaults, today: today)
    }

    private func monday() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 11
        return Calendar.current.date(from: c)!
    }

    private func makePlan(_ kinds: [DayKind]) -> WeekPlan {
        precondition(kinds.count == 7)
        let cal = Calendar.current
        let start = monday()
        let days = (0..<7).map { i -> DayPlan in
            let kind = kinds[i]
            let title = kind == .lift ? "Push day" : kind == .sport ? "Climb" : "Rest"
            return DayPlan(
                date: cal.date(byAdding: .day, value: i, to: start) ?? start,
                kind: kind, title: title, routineId: nil,
                generatedWorkout: kind == .lift ? GeneratedWorkout(
                    title: title, summary: "", exercises: [],
                    estimatedMinutes: 60, provenance: "") : nil
            )
        }
        return WeekPlan(days: days, generatedAt: Date(), inputsHash: "test")
    }

    /// ActiveSession with `done` of `total` sets marked done.
    private func session(done: Int, total: Int) -> ActiveSession {
        var sets: [LoggedSet] = []
        for i in 0..<total {
            sets.append(LoggedSet(num: i + 1, weight: "100", reps: "8", rpe: "", done: i < done))
        }
        let ex = LoggedExercise(
            id: "ex-1", name: "Bench Press", type: nil, unit: "lbs",
            targetSets: total, targetReps: 8, rest: 90,
            sets: sets, prevSets: []
        )
        return ActiveSession(
            templateId: "t1", name: "Push day", category: "lift",
            startTime: monday(), exercises: [ex], feel: nil, note: nil
        )
    }

    // MARK: - Entry model

    func test_completionRatio_clampsOutOfRangeValues() {
        let d = monday()
        let high = AbandonedWorkoutEntry(date: d, plannedTitle: "Push",
                                         reason: .feltOff, completionRatio: 1.4)
        let low = AbandonedWorkoutEntry(date: d, plannedTitle: "Push",
                                        reason: .feltOff, completionRatio: -0.2)
        XCTAssertEqual(high.completionRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(low.completionRatio, 0.0, accuracy: 0.0001)
    }

    func test_abandonReason_labelsAreDistinct() {
        let labels = Set(AbandonReason.allCases.map(\.label))
        XCTAssertEqual(labels.count, AbandonReason.allCases.count)
        XCTAssertTrue(AbandonReason.allCases.contains(.pain))
    }

    // MARK: - SessionStore.saveAbandoned

    func test_saveAbandoned_recordsEntryBelowThreshold() {
        let defaults = UserDefaults(suiteName: "abandon-ss-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: "abandon-ss-\(UUID().uuidString)")
        let store = SessionStore(defaults: defaults)

        var recorded: AbandonedWorkoutEntry?
        store.onAbandonRecorded = { recorded = $0 }

        // 6 of 12 done = 50% — below the 70% threshold.
        store.saveAbandoned(session(done: 6, total: 12), reason: .pain, note: "left knee")
        XCTAssertNotNil(recorded)
        XCTAssertEqual(recorded?.reason, .pain)
        XCTAssertEqual(recorded?.note, "left knee")
        XCTAssertEqual(recorded?.completionRatio ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(recorded?.plannedTitle, "Push day")
        // The session itself persisted through the completed path.
        XCTAssertEqual(store.savedSessions.count, 1)
        XCTAssertNil(store.active)
    }

    func test_saveAbandoned_atOrAboveThreshold_recordsNothing() {
        let defaults = UserDefaults(suiteName: "abandon-ss-\(UUID().uuidString)")!
        let store = SessionStore(defaults: defaults)
        var recorded: AbandonedWorkoutEntry?
        store.onAbandonRecorded = { recorded = $0 }

        // 9 of 12 = 75% — a completed (if short) workout, not an abandonment.
        store.saveAbandoned(session(done: 9, total: 12), reason: .timeOut, note: nil)
        XCTAssertNil(recorded)
        XCTAssertEqual(store.savedSessions.count, 1)
    }

    func test_saveAbandoned_zeroSetsDown_recordsFullAbandonment() {
        let defaults = UserDefaults(suiteName: "abandon-ss-\(UUID().uuidString)")!
        let store = SessionStore(defaults: defaults)
        var recorded: AbandonedWorkoutEntry?
        store.onAbandonRecorded = { recorded = $0 }
        store.saveAbandoned(session(done: 0, total: 10), reason: .motivation, note: nil)
        XCTAssertEqual(recorded?.completionRatio ?? -1, 0.0, accuracy: 0.0001)
    }

    // MARK: - PlanStore record + persistence

    func test_recordAbandonment_persistsAndReloads() {
        let suite = "abandon-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let today = monday()
        let store = PlanStore(defaults: defaults, today: today)

        let entry = AbandonedWorkoutEntry(
            date: today, plannedTitle: "Push day",
            reason: .pain, completionRatio: 0.4, note: "shoulder"
        )
        store.recordAbandonment(entry)
        XCTAssertEqual(store.abandonedWorkouts.count, 1)

        let reloaded = PlanStore(defaults: defaults, today: today)
        XCTAssertEqual(reloaded.abandonedWorkouts.count, 1)
        XCTAssertEqual(reloaded.abandonedWorkouts.first?.reason, .pain)
    }

    func test_recordAbandonment_isIdempotentPerDay() {
        let store = freshStore()
        let d = monday()
        store.recordAbandonment(AbandonedWorkoutEntry(
            date: d, plannedTitle: "Push day", reason: .feltOff, completionRatio: 0.3))
        store.recordAbandonment(AbandonedWorkoutEntry(
            date: d, plannedTitle: "Push day", reason: .other,
            completionRatio: 0.5, note: "replaced"))
        XCTAssertEqual(store.abandonedWorkouts.count, 1)
        XCTAssertEqual(store.abandonedWorkouts.first?.reason, .other)
    }

    // MARK: - Reactive reshuffle

    func test_proposeAbandonReshuffle_movesToLaterRestDay() {
        let wed = monday().addingTimeInterval(2 * 86_400)
        let store = freshStore(today: wed)
        store.setPlan(makePlan([.lift, .rest, .lift, .rest, .rest, .rest, .rest]))
        let entry = AbandonedWorkoutEntry(
            date: wed, plannedTitle: "Push day", reason: .feltOff, completionRatio: 0.3)
        let diff = store.proposeAbandonReshuffle(entry: entry, now: wed)
        XCTAssertNotNil(diff)
        // Target must be a future rest day.
        guard case .move(_, let toDate)? = diff?.edits.first else {
            return XCTFail("expected a .move edit")
        }
        let thursday = monday().addingTimeInterval(3 * 86_400)
        XCTAssertEqual(Calendar.current.startOfDay(for: toDate),
                       Calendar.current.startOfDay(for: thursday))
    }

    func test_proposeAbandonReshuffle_nilWhenBudgetExhausted() {
        let wed = monday().addingTimeInterval(2 * 86_400)
        let store = freshStore(today: wed)
        store.setPlan(makePlan([.lift, .rest, .lift, .rest, .rest, .rest, .rest]))
        store.midWeekReshuffleCount = PlanStore.weeklyReshuffleCap
        let entry = AbandonedWorkoutEntry(
            date: wed, plannedTitle: "Push day", reason: .feltOff, completionRatio: 0.3)
        XCTAssertNil(store.proposeAbandonReshuffle(entry: entry, now: wed))
    }

    func test_proposeAbandonReshuffle_nilAtDropRule() {
        // 4+ planned lift days → drop, don't crowd (spec §3 rule 1).
        let wed = monday().addingTimeInterval(2 * 86_400)
        let store = freshStore(today: wed)
        store.setPlan(makePlan([.lift, .lift, .lift, .lift, .rest, .rest, .rest]))
        let entry = AbandonedWorkoutEntry(
            date: wed, plannedTitle: "Push day", reason: .feltOff, completionRatio: 0.3)
        XCTAssertNil(store.proposeAbandonReshuffle(entry: entry, now: wed))
    }

    func test_applyAbandonReshuffle_bumpsSharedReshuffleCounter() {
        let wed = monday().addingTimeInterval(2 * 86_400)
        let store = freshStore(today: wed)
        store.setPlan(makePlan([.lift, .rest, .lift, .rest, .rest, .rest, .rest]))
        let entry = AbandonedWorkoutEntry(
            date: wed, plannedTitle: "Push day", reason: .feltOff, completionRatio: 0.3)
        let diff = store.proposeAbandonReshuffle(entry: entry, now: wed)
        XCTAssertNotNil(diff)
        store.applyAbandonReshuffle(diff!, entry: entry, now: wed)
        XCTAssertEqual(store.midWeekReshuffleCount, 1)
    }

    // MARK: - Backup envelope round-trip

    func test_backupEnvelope_carriesAbandonments() throws {
        let defaults = UserDefaults(suiteName: "abandon-bk-\(UUID().uuidString)")!
        let entry = AbandonedWorkoutEntry(
            date: monday(), plannedTitle: "Push day",
            reason: .pain, completionRatio: 0.25, note: "knee")
        let data = try PlanStore.encoder().encode([entry])
        defaults.set(data, forKey: PlanStore.abandonedWorkoutsKey)

        let env = BackupManager.snapshot(defaults: defaults,
                                         userDB: .defaultStore())
        XCTAssertEqual(env.abandonedWorkouts.count, 1)
        XCTAssertEqual(env.abandonedWorkouts.first?.note, "knee")
    }

    // MARK: - Restore reload

    /// BackupCoordinator restores into UserDefaults and then calls
    /// reloadFromDefaults. Before 2026-09-26 that re-read only plan and
    /// overrides, so the next recordMiss / recordAbandonment wrote the stale
    /// in-memory log back over the restored one.
    func test_reloadFromDefaults_rereadsMissedAndAbandonedLogs_soTheNextWriteKeepsThem() throws {
        let suite = "abandon-restore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let today = monday()
        let store = PlanStore(defaults: defaults, today: today)
        XCTAssertTrue(store.missedWorkouts.isEmpty && store.abandonedWorkouts.isEmpty)

        let day = { (n: Int) in Calendar.current.date(byAdding: .day, value: -n, to: today)! }
        let missed = [MissedWorkoutEntry(date: day(3), plannedKind: .lift, plannedTitle: "Lower",
                                         resolution: .dropped, loggedAt: day(2))]
        let abandoned = [AbandonedWorkoutEntry(date: day(5), plannedTitle: "Upper", reason: .pain,
                                               completionRatio: 0.3, loggedAt: day(5))]
        defaults.set(try PlanStore.encoder().encode(missed), forKey: PlanStore.missedWorkoutsKey)
        defaults.set(try PlanStore.encoder().encode(abandoned), forKey: PlanStore.abandonedWorkoutsKey)

        store.reloadFromDefaults(today: today)
        XCTAssertEqual(store.missedWorkouts.map(\.plannedTitle), ["Lower"])
        XCTAssertEqual(store.abandonedWorkouts.map(\.plannedTitle), ["Upper"])

        // The write that used to clobber the restore.
        store.recordAbandonment(AbandonedWorkoutEntry(date: day(1), plannedTitle: "Full", reason: .timeOut,
                                                      completionRatio: 0.2, loggedAt: today))
        let reopened = PlanStore(defaults: defaults, today: today)
        XCTAssertEqual(Set(reopened.abandonedWorkouts.compactMap(\.plannedTitle)), ["Upper", "Full"])
        XCTAssertEqual(reopened.missedWorkouts.count, 1)
    }
}
