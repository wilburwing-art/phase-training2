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
        let (store, today) = makeStore()
        let memory = gymMemory()
        _ = store.generate(from: memory, today: today)

        store.regenerateToday(memory: memory, today: today, salt: "a")
        let pickA = store.plan?.today()?.generatedWorkout?.exercises.map(\.exerciseId)

        store.regenerateToday(memory: memory, today: today, salt: "b")
        let pickB = store.plan?.today()?.generatedWorkout?.exercises.map(\.exerciseId)

        XCTAssertNotNil(pickA)
        XCTAssertNotNil(pickB)
        XCTAssertNotEqual(pickA, pickB,
                          "Different regen salts should produce different exercise picks")
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
