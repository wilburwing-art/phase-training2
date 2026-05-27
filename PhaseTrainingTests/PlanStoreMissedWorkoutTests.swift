// PlanStoreMissedWorkoutTests.swift — PR 8 of the weekly-coach roadmap.
//
// Glue tests: the PlanStore-level integration between
// MissedWorkoutAutopilot, persistence, and the weekly reshuffle
// counter.

import XCTest
@testable import PhaseTraining

final class PlanStoreMissedWorkoutTests: XCTestCase {

    private func freshStore(today: Date = Date()) -> PlanStore {
        let suite = "missed-workout-tests-\(UUID().uuidString)"
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

    // MARK: - Pending detection

    func test_pendingMissedWorkouts_emptyWithNoPlan() {
        let store = freshStore()
        XCTAssertTrue(store.pendingMissedWorkouts().isEmpty)
    }

    func test_pendingMissedWorkouts_finds_pastUnloggedLift() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        // Stub SessionStore — no logged sessions yet
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))
        let pending = store.pendingMissedWorkouts(now: wed)
        XCTAssertEqual(pending.count, 1)
    }

    func test_pendingMissedWorkouts_filtersAlreadyLoggedEntries() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))
        XCTAssertEqual(store.pendingMissedWorkouts(now: wed).count, 1)

        // Dismiss it
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        store.dismissMissed(date: tue, asDropped: false)

        XCTAssertEqual(store.pendingMissedWorkouts(now: wed).count, 0,
                       "logged misses should drop out of the pending list")
    }

    // MARK: - Reshuffle counter

    func test_reshuffleCounter_startsAtZero() {
        let store = freshStore()
        XCTAssertEqual(store.midWeekReshuffleCount, 0)
    }

    func test_applyReshuffle_bumpsCounter() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))

        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        guard let diff = store.proposeMissedReshuffle(missedDate: tue, now: wed) else {
            XCTFail("expected a reshuffle proposal"); return
        }
        store.applyMissedReshuffle(diff, missedDate: tue, now: wed)
        XCTAssertEqual(store.midWeekReshuffleCount, 1)
        XCTAssertEqual(store.missedWorkouts.count, 1)
        if case .reshuffledTo = store.missedWorkouts[0].resolution {
            // success
        } else {
            XCTFail("expected reshuffledTo resolution, got \(store.missedWorkouts[0].resolution)")
        }
    }

    func test_proposeReshuffle_returnsNilWhenBudgetExhausted() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .lift, .rest, .lift, .rest]))

        // Force-set the counter to the cap
        store.midWeekReshuffleCount = PlanStore.weeklyReshuffleCap

        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        XCTAssertNil(store.proposeMissedReshuffle(missedDate: tue, now: wed),
                     "at the cap, the autopilot should return nil so the banner can drop")
    }

    // MARK: - Dismissal

    func test_dismissMissed_logsResolution() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        store.dismissMissed(date: tue, asDropped: false)
        XCTAssertEqual(store.missedWorkouts.count, 1)
        XCTAssertEqual(store.missedWorkouts[0].resolution, .userDismissed)
    }

    func test_dismissMissed_idempotent() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        store.dismissMissed(date: tue, asDropped: false)
        store.dismissMissed(date: tue, asDropped: true)
        XCTAssertEqual(store.missedWorkouts.count, 1, "second dismiss replaces, doesn't append")
        XCTAssertEqual(store.missedWorkouts[0].resolution, .dropped)
    }

    // MARK: - Persistence + clear

    func test_persistsAcrossInstances() {
        let suite = "miss-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let monday = monday()
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday)!

        do {
            let store = PlanStore(defaults: defaults, today: wed)
            store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
            store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))
            store.dismissMissed(date: tue, asDropped: false)
            XCTAssertEqual(store.missedWorkouts.count, 1)
        }
        let reopened = PlanStore(defaults: defaults, today: wed)
        XCTAssertEqual(reopened.missedWorkouts.count, 1,
                       "missed-workout log should survive a fresh PlanStore init")
    }

    func test_clearWipesMissedAndCounter() {
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: monday())!
        let store = freshStore(today: wed)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "miss-stub-\(UUID())")!)
        store.setPlan(makePlan([.rest, .lift, .rest, .rest, .rest, .rest, .rest]))
        let tue = Calendar.current.date(byAdding: .day, value: 1, to: monday())!
        store.dismissMissed(date: tue, asDropped: false)
        store.midWeekReshuffleCount = 2
        store.clear()
        XCTAssertEqual(store.missedWorkouts.count, 0)
        XCTAssertEqual(store.midWeekReshuffleCount, 0)
    }
}
