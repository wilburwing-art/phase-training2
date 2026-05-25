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
        m.focuses = [.generalStrength]
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

    // MARK: - regenerateWeek

    func test_regenerateWeek_clearsDrift() {
        let (store, today) = makeStore()
        var memory = gymMemory()
        _ = store.generate(from: memory, today: today)

        memory.equipment = [.bodyweight]    // drift
        XCTAssertTrue(store.needsRegeneration(for: memory))

        _ = store.regenerateWeek(memory: memory, today: today)
        XCTAssertFalse(store.needsRegeneration(for: memory),
                       "regenerateWeek should pull the plan's inputs hash in line with memory")
    }

    func test_regenerateWeek_reflectsNewEquipment() {
        let (store, today) = makeStore()
        var memory = gymMemory()
        _ = store.generate(from: memory, today: today)

        // Pre-condition: with fullGym, plan likely has gym exercises.
        memory.equipment = [.bodyweight]
        _ = store.regenerateWeek(memory: memory, today: today)

        let allExerciseIds = store.plan?.days
            .compactMap(\.generatedWorkout)
            .flatMap(\.exercises)
            .map(\.exerciseId) ?? []
        for id in allExerciseIds {
            let env = CoachDatabase.shared.exercise(id: id)?.environment
            XCTAssertNotEqual(env, "gym",
                "After regenerateWeek with bodyweight equipment, exercise \(id) should not be gym-tagged")
        }
    }

    // MARK: - regenerateToday

    func test_regenerateToday_mutatesOnlyTodaySlot() {
        let (store, today) = makeStore()
        let memory = gymMemory()
        _ = store.generate(from: memory, today: today)

        let originalDays = store.plan?.days.map { ($0.date, $0.title) } ?? []

        // Re-roll today with a fixed salt for repeatability.
        store.regenerateToday(memory: memory, today: today, salt: "test-1")

        let newDays = store.plan?.days ?? []
        XCTAssertEqual(originalDays.count, newDays.count)

        let cal = Calendar.current
        for (idx, day) in newDays.enumerated() {
            if cal.isDate(day.date, inSameDayAs: today) {
                // Today changed — title may or may not differ depending on
                // whether the new pick happens to land on the same exercises.
                continue
            }
            XCTAssertEqual(day.title, originalDays[idx].1,
                "Non-today day at idx \(idx) should be untouched")
        }
    }

    func test_regenerateToday_differentSaltsYieldDifferentWorkouts() {
        // Pin to a Monday so the 3-lift-per-week split reliably lands a lift
        // on `today`. Without a fixed anchor, running on a rest/sport calendar
        // day makes regenerateToday early-return and both picks come back nil.
        var c = DateComponents(); c.year = 2026; c.month = 5; c.day = 11
        let today = Calendar.current.date(from: c)!
        let defaults = UserDefaults(suiteName: "PlanStoreRegenTests.\(#function)")!
        defaults.removePersistentDomain(forName: "PlanStoreRegenTests.\(#function)")
        let store = PlanStore(defaults: defaults, today: today)
        let memory = gymMemory()
        _ = store.generate(from: memory, today: today)

        store.regenerateToday(memory: memory, today: today, salt: "a")
        let pickA = store.plan?.today(now: today)?.generatedWorkout?.exercises.map(\.exerciseId)

        store.regenerateToday(memory: memory, today: today, salt: "b")
        let pickB = store.plan?.today(now: today)?.generatedWorkout?.exercises.map(\.exerciseId)

        XCTAssertNotNil(pickA)
        XCTAssertNotNil(pickB)
        XCTAssertNotEqual(pickA, pickB,
                          "Different regen salts should produce different exercise picks")
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

    func test_regenerateToday_isNoopOnRestDay() {
        let (store, today) = makeStore()
        var memory = gymMemory()
        // Force today to be rest.
        memory.liftDaysPerWeek = 0
        memory.focuses = [.generalStrength]
        _ = store.generate(from: memory, today: today)

        let originalTitle = store.plan?.today()?.title
        store.regenerateToday(memory: memory, today: today, salt: "x")
        XCTAssertEqual(store.plan?.today()?.title, originalTitle,
                       "Rest day should be untouched by regenerateToday")
    }
}
