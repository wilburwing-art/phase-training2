// PlanStoreRefreshTests.swift: the foreground refresh gate (refreshForCurrentWeek).
// It regenerates an aged-out plan, leaves a current one alone, waits for
// onboarding and for any active session, and installs a staged week.

import XCTest
@testable import PhaseTraining

final class PlanStoreRefreshTests: XCTestCase {

    private var suites: [String] = []

    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let name = "PlanStoreRefreshTests-\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func gymMemory(onboarded: Bool = true) -> TrainingMemory {
        var m = TrainingMemory()
        m.equipment = [.fullGym]
        m.experience = .intermediate
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        if onboarded { m.onboardedAt = Date() }
        return m
    }

    /// A store holding a freshly generated plan for this week.
    private func seededStore(_ defaults: UserDefaults, memory: TrainingMemory) -> (PlanStore, Date)? {
        let store = PlanStore(defaults: defaults, today: Date())
        store.generate(from: memory, today: Date())
        guard store.plan != nil else { return nil }
        return (store, Date())
    }

    // MARK: - refreshForCurrentWeek

    private func stalePlan(weeksAgo: Int) -> WeekPlan {
        let cal = Calendar.current
        let monday = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date().startOfTrainingWeek())!
        let days = (0..<7).map { i in
            DayPlan(date: cal.date(byAdding: .day, value: i, to: monday)!, kind: .rest,
                    title: "Rest", routineId: nil, generatedWorkout: nil, generatedReason: "stale")
        }
        return WeekPlan(days: days, generatedAt: monday, inputsHash: "stale")
    }

    func testRefreshRegeneratesAnAgedOutPlanAndSnapshotsTheOldWeek() throws {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: Date())
        store.setPlan(stalePlan(weeksAgo: 2))
        XCTAssertFalse(store.planCoversCurrentWeek())

        store.refreshForCurrentWeek(memory: gymMemory())

        XCTAssertTrue(store.planCoversCurrentWeek())
        XCTAssertEqual(store.plan?.days.filter { $0.kind == .lift }.count, 3)
        XCTAssertFalse(store.pastPlans.isEmpty, "the outgoing week is captured before it is replaced")
    }

    func testRefreshIsANoOpWhenThePlanCoversThisWeek() throws {
        let memory = gymMemory()
        let (store, _) = try XCTUnwrap(seededStore(freshDefaults(), memory: memory))
        let before = try XCTUnwrap(store.plan)
        store.refreshForCurrentWeek(memory: memory)
        XCTAssertEqual(store.plan, before, "same week: no reroll under the user")
    }

    func testRefreshDoesNothingBeforeOnboarding() {
        let store = PlanStore(defaults: freshDefaults(), today: Date())
        let old = stalePlan(weeksAgo: 2)
        store.setPlan(old)
        store.refreshForCurrentWeek(memory: gymMemory(onboarded: false))
        XCTAssertEqual(store.plan, old)
    }

    func testRefreshDoesNothingMidSession() {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: Date())
        let sessions = SessionStore(defaults: freshDefaults(), userDB: UserDatabase(path: ":memory:"))
        sessions.saveActive(sessions.createSession(templateId: "upper-1"))
        XCTAssertNotNil(sessions.active)
        store.sessionStore = sessions
        let old = stalePlan(weeksAgo: 2)
        store.setPlan(old)

        store.refreshForCurrentWeek(memory: gymMemory())

        XCTAssertEqual(store.plan, old, "a rollover during a workout must not swap the template")
    }

    func testRefreshInstallsAStagedWeekInsteadOfGenerating() throws {
        let defaults = freshDefaults()
        let store = PlanStore(defaults: defaults, today: Date())
        store.setPlan(stalePlan(weeksAgo: 1))
        var staged = stalePlan(weeksAgo: 0)
        staged.inputsHash = "staged-by-check-in"
        store.stagePlan(staged, overrides: WeekOverrides(weekStart: Date().startOfTrainingWeek()))

        store.refreshForCurrentWeek(memory: gymMemory())

        XCTAssertEqual(store.plan?.inputsHash, "staged-by-check-in", "the check-in's answers win over a fresh generate")
    }
}
