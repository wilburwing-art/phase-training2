// BackupPlanStateTests.swift — a backup must carry the plan state that
// PlanStore persists beyond the live week. Before 2026-09-26 the envelope
// skipped past weeks, the dismissed plan-issue log, the staged next week and
// the deload anchor, so a phone switch lost the coach's multi-week pattern,
// "use last week's shape", rule self-suppression, the check-in's staged week,
// and the deload cooldown.

import XCTest
@testable import PhaseTraining

final class BackupPlanStateTests: XCTestCase {

    private let today = Date()

    private func freshDefaults() -> UserDefaults {
        let suite = "backup-plan-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func week(startingIn weeks: Int) -> WeekPlan {
        let cal = Calendar.current
        let monday = cal.date(byAdding: .weekOfYear, value: weeks, to: today.startOfTrainingWeek())!
        let days = (0..<7).map { i in
            DayPlan(date: cal.date(byAdding: .day, value: i, to: monday)!, kind: i < 3 ? .lift : .rest,
                    title: i < 3 ? "Lift" : "Rest", routineId: nil, generatedWorkout: nil, generatedReason: "test")
        }
        return WeekPlan(days: days, generatedAt: today, inputsHash: "test")
    }

    /// Seed every piece through PlanStore's own write paths, back up, restore
    /// into an empty store, and read it back through a fresh PlanStore.
    func test_roundTrip_carriesPastPlansOverridesPendingWeekAndDeloadAnchor() throws {
        let source = freshDefaults()
        let store = PlanStore(defaults: source, today: today)
        store.setPlan(week(startingIn: -1))
        store.snapshotCurrentPlan(now: today.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(store.pastPlans.count, 1, "fixture: one past week")
        let override = WeeklyPlanOverride(weekStart: today.startOfTrainingWeek(), rule: "push_pull_balance",
                                          pattern: "push", loggedAt: today)
        source.set(try PlanStore.encoder().encode([override]), forKey: PlanStore.planOverridesKey)
        store.stagePlan(week(startingIn: 1), overrides: WeekOverrides(weekStart: week(startingIn: 1).days[0].date))
        let deload = today.addingTimeInterval(-21 * 86_400).timeIntervalSince1970
        source.set(deload, forKey: PlanStore.lastDeloadWeekKey)

        let envelope = BackupManager.snapshot(defaults: source, userDB: UserDatabase(path: ":memory:"))
        let json = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(BackupEnvelope.self, from: json)

        let target = freshDefaults()
        try BackupManager.restore(decoded, into: target, userDB: UserDatabase(path: ":memory:"))
        let restored = PlanStore(defaults: target, today: today)

        XCTAssertEqual(restored.pastPlans.count, 1)
        XCTAssertEqual(restored.recentPlanOverrides.map(\.suppressionKey), ["push_pull_balance:push"])
        XCTAssertNotNil(restored.pendingPlan, "next week's staged plan must survive")
        XCTAssertEqual(target.object(forKey: PlanStore.lastDeloadWeekKey) as? Double, deload)
    }

    func test_restoreIntoALiveStore_isPickedUpByReload() throws {
        let source = freshDefaults()
        let seeded = PlanStore(defaults: source, today: today)
        seeded.setPlan(week(startingIn: -1))
        seeded.snapshotCurrentPlan(now: today.addingTimeInterval(-7 * 86_400))
        let envelope = BackupManager.snapshot(defaults: source, userDB: UserDatabase(path: ":memory:"))

        let target = freshDefaults()
        let live = PlanStore(defaults: target, today: today)
        XCTAssertTrue(live.pastPlans.isEmpty)
        try BackupManager.restore(envelope, into: target, userDB: UserDatabase(path: ":memory:"))
        live.reloadFromDefaults(today: today)
        XCTAssertEqual(live.pastPlans.count, 1, "reload must re-read restored history, not keep the empty copy")
    }

    func test_oldBackupsWithoutTheseFields_stillDecode() throws {
        let env = BackupEnvelope(exportedAt: today, memory: nil, savedSessions: [], activeSession: nil,
                                 customRoutines: [], plan: nil, overrides: nil, reminderEnabled: false)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(env)) as? [String: Any])
        for k in ["pastPlans", "planOverrides", "pendingPlan", "pendingOverrides", "lastDeloadWeekStart"] {
            json.removeValue(forKey: k)
        }
        let old = try JSONDecoder().decode(BackupEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.pastPlans.isEmpty)
        XCTAssertNil(old.pendingPlan)
        XCTAssertNil(old.lastDeloadWeekStart)
    }
}
