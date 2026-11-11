import XCTest
@testable import PhaseTraining

/// Phase 15c — covers the targeted regen entry points the Today / Week /
/// Profile screens use to react to profile changes.
final class PlanStoreRegenTests: XCTestCase {

    /// Fresh in-memory PlanStore. Anchored to `Date()` because
    /// `WeekPlan.today(now:)` defaults to `Date()` — using a hard-coded
    /// anchor would put plan days outside the today() lookup window.
    private func makeStore(suiteName: String = #function) -> (PlanStore, Date) {
        let defaults = UserDefaults(suiteName: "PlanStoreRegenTests.\(suiteName)")!
        defaults.removePersistentDomain(forName: "PlanStoreRegenTests.\(suiteName)")
        let today = Date()
        return (PlanStore(defaults: defaults, today: today), today)
    }

    private func gymMemory() -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        return m
    }

    // MARK: - needsRegeneration

    func test_needsRegeneration_isTrueWhenNoPlanExists() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.needsRegeneration(for: gymMemory()))
    }

    func test_needsRegeneration_isFalseImmediatelyAfterGenerate() {
        let (store, today) = makeStore()
        let memory = gymMemory()
        _ = store.generate(from: memory, today: today)
        XCTAssertFalse(store.needsRegeneration(for: memory))
    }

    func test_needsRegeneration_isTrueAfterMemoryEdit() {
        let (store, today) = makeStore()
        var memory = gymMemory()
        _ = store.generate(from: memory, today: today)
        XCTAssertFalse(store.needsRegeneration(for: memory))

        // Simulate a Profile edit: bump experience from intermediate to advanced.
        memory.experience = .advanced
        XCTAssertTrue(store.needsRegeneration(for: memory),
                      "Experience change should drift the plan")
    }

    // MARK: - migrateIfStale (build ≤35 → 36+ schema migration)

    func test_migrateIfStale_replacesRoutineIdDaysWithGeneratedWorkouts() {
        let (store, today) = makeStore()
        let memory = gymMemory()

        // Hand-craft a build-35-style stale plan: lift days have routineId
        // set but no generatedWorkout. This mirrors what UserDefaults would
        // decode for a user upgrading from the old picker.
        let cal = Calendar.current
        let kinds: [DayKind] = [.lift, .rest, .lift, .rest, .lift, .rest, .rest]
        let staleDays = (0..<7).map { i -> DayPlan in
            DayPlan(
                date: cal.date(byAdding: .day, value: i, to: today) ?? today,
                kind: kinds[i],
                title: kinds[i] == .lift ? "Basketball Vertical Jump" : "Mobility Flow",
                routineId: kinds[i].isWorkout ? 237 : nil,    // pretend old picker landed on a sport routine
                generatedWorkout: nil,                          // <-- the schema marker
                generatedReason: "stale build-35 plan"
            )
        }
        store.setPlan(WeekPlan(days: staleDays, generatedAt: Date(), inputsHash: "stale"))

        // Sanity: plan currently has routineId-driven lift days, no generated workouts.
        XCTAssertTrue(store.plan?.days.allSatisfy {
            $0.kind == .rest || $0.kind == .sport || $0.kind == .event || $0.generatedWorkout == nil
        } ?? false)

        store.migrateIfStale(memory: memory, today: today)

        // After migration: every lift day has a generatedWorkout.
        for day in store.plan?.days ?? [] {
            if day.kind == .lift {
                XCTAssertNotNil(day.generatedWorkout,
                                "\(day.title) on \(day.date) should have a generated workout after migration")
                XCTAssertNil(day.routineId,
                             "Migrated days shouldn't carry the stale routineId reference")
            }
        }
    }

    func test_migrateIfStale_isNoopWhenPlanIsCurrent() {
        let (store, today) = makeStore()
        let memory = gymMemory()
        _ = store.generate(from: memory, today: today)

        let preTitles = store.plan?.days.map(\.title) ?? []
        store.migrateIfStale(memory: memory, today: today)
        let postTitles = store.plan?.days.map(\.title) ?? []
        XCTAssertEqual(preTitles, postTitles,
                       "A fresh plan should pass migrateIfStale untouched")
    }

    func test_migrateIfStale_isNoopWhenNoPlan() {
        let (store, today) = makeStore()
        XCTAssertNil(store.plan)
        store.migrateIfStale(memory: gymMemory(), today: today)
        XCTAssertNil(store.plan, "Migration should not synthesize a plan from nothing")
    }
}
