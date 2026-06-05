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

    // MARK: - Consolidation apply (D3)

    /// A lift day carrying an explicit persisted focus (makePlan leaves focus
    /// nil, which consolidateWeek can't recover).
    private func focusedLiftDay(_ offset: Int, _ focus: WorkoutFocus) -> DayPlan {
        let cal = Calendar.current
        return DayPlan(
            date: cal.date(byAdding: .day, value: offset, to: monday())!,
            kind: .lift, title: focus.title, routineId: nil,
            generatedWorkout: GeneratedWorkout(
                title: focus.title, summary: "", exercises: [],
                estimatedMinutes: 60, provenance: "", focus: focus))
    }

    private func restDay(_ offset: Int) -> DayPlan {
        let cal = Calendar.current
        return DayPlan(date: cal.date(byAdding: .day, value: offset, to: monday())!,
                       kind: .rest, title: "Rest", routineId: nil, generatedWorkout: nil)
    }

    private func hypertrophyMemory() -> TrainingMemory {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.equipment = [.fullGym]
        m.focuses = [.hypertrophy]
        m.sessionMinutes = 60
        return m
    }

    func test_consolidateWeek_dropsOneLiftDayAndMerges() {
        let mon = monday()
        let store = freshStore(today: mon)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "consol-stub-\(UUID())")!)
        let days = [focusedLiftDay(0, .push), restDay(1), focusedLiftDay(2, .pull),
                    restDay(3), focusedLiftDay(4, .legs), restDay(5), restDay(6)]
        store.setPlan(WeekPlan(days: days, generatedAt: Date(), inputsHash: "test"))

        let applied = store.consolidateWeek(memory: hypertrophyMemory(), today: mon)
        XCTAssertTrue(applied, "3 future lift days → consolidation applies")
        XCTAssertEqual(store.plan?.days.filter { $0.kind == .lift }.count, 2,
                       "one future lift day drops to rest")
        XCTAssertEqual(store.midWeekConsolidationCount, 1)
    }

    /// Reproduces the ConsolidateFlowTests XCUITest seed at the PlanStore level
    /// (fast): 4 lifts incl a PAST missed push → the banner should offer
    /// Consolidate. Splits "does the logic offer it" from "does the UI render it".
    func test_seedScenario_offersConsolidate() {
        let mon = monday()
        let store = freshStore(today: mon)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "seed-stub-\(UUID())")!)
        let days = [focusedLiftDay(-2, .push), restDay(-1), focusedLiftDay(0, .pull),
                    restDay(1), focusedLiftDay(2, .legs), focusedLiftDay(3, .upper), restDay(4)]
        store.setPlan(WeekPlan(days: days, generatedAt: Date(), inputsHash: "seed"))

        let pending = store.pendingMissedWorkouts(now: mon)
        XCTAssertEqual(pending.count, 1, "GATE 1 — the past push is the only pending miss")
        guard let miss = pending.last else { return XCTFail("no pending miss detected") }

        XCTAssertNil(store.proposeMissedReshuffle(missedDate: miss.date, now: mon),
                     "GATE 2 — 4-lift week trips the drop rule → reshuffle [] → nil")
        XCTAssertTrue(store.shouldOfferConsolidation(missedDate: miss.date, now: mon),
                      "GATE 3 — no clean slot + 3 future focus-tagged lifts → offer consolidate")
    }

    func test_consolidateWeek_respectsOneWeekCap() {
        let mon = monday()
        let store = freshStore(today: mon)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "consol-stub-\(UUID())")!)
        let days = [focusedLiftDay(0, .push), restDay(1), focusedLiftDay(2, .pull),
                    restDay(3), focusedLiftDay(4, .legs), restDay(5), restDay(6)]
        store.setPlan(WeekPlan(days: days, generatedAt: Date(), inputsHash: "test"))

        XCTAssertTrue(store.consolidateWeek(memory: hypertrophyMemory(), today: mon))
        XCTAssertFalse(store.consolidateWeek(memory: hypertrophyMemory(), today: mon),
                       "1/week cap blocks a second consolidation")
    }

    func test_consolidateWeek_noopWithFewerThanTwoFutureLifts() {
        let mon = monday()
        let store = freshStore(today: mon)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "consol-stub-\(UUID())")!)
        let days = [focusedLiftDay(0, .push), restDay(1), restDay(2),
                    restDay(3), restDay(4), restDay(5), restDay(6)]
        store.setPlan(WeekPlan(days: days, generatedAt: Date(), inputsHash: "test"))
        XCTAssertFalse(store.consolidateWeek(memory: hypertrophyMemory(), today: mon),
                       "need ≥2 future lift days to consolidate")
    }

    // MARK: - Typical-week prefill (PR 6 gap)

    func test_adoptLastWeekShape_copiesKindsAndFocus() {
        let mon = monday()
        let cal = Calendar.current
        let store = freshStore(today: mon)
        store.sessionStore = SessionStore(defaults: UserDefaults(suiteName: "shape-stub-\(UUID())")!)

        // Last week (Mon-7): push Mon, pull Wed, rest otherwise.
        let lw = cal.date(byAdding: .day, value: -7, to: mon)!
        func ld(_ off: Int, _ f: WorkoutFocus) -> DayPlan {
            DayPlan(date: cal.date(byAdding: .day, value: off, to: lw)!, kind: .lift,
                    title: f.title, routineId: nil,
                    generatedWorkout: GeneratedWorkout(title: f.title, summary: "",
                        exercises: [], estimatedMinutes: 60, provenance: "", focus: f))
        }
        func rd(_ off: Int) -> DayPlan {
            DayPlan(date: cal.date(byAdding: .day, value: off, to: lw)!, kind: .rest, title: "Rest")
        }
        let lastWeek = WeekPlan(days: [ld(0, .push), rd(1), ld(2, .pull), rd(3), rd(4), rd(5), rd(6)],
                                generatedAt: Date(), inputsHash: "lw")
        store.pastPlans = [WeekPlanSnapshot(weekStart: lw, plan: lastWeek,
                                            actualSessionIDs: [], capturedAt: Date())]

        XCTAssertTrue(store.hasPriorWeekShape)
        XCTAssertTrue(store.adoptLastWeekShape(memory: hypertrophyMemory(), today: mon))

        XCTAssertEqual(store.overrides.override(on: mon)?.liftFocus, .push,
                       "this week's Mon should adopt last week's push focus")
        let wed = cal.date(byAdding: .day, value: 2, to: mon)!
        XCTAssertEqual(store.overrides.override(on: wed)?.liftFocus, .pull)
        let tue = cal.date(byAdding: .day, value: 1, to: mon)!
        XCTAssertEqual(store.overrides.override(on: tue)?.asKind, .rest)
    }

    func test_adoptLastWeekShape_falseWithNoPriorWeek() {
        let store = freshStore(today: monday())
        XCTAssertFalse(store.hasPriorWeekShape)
        XCTAssertFalse(store.adoptLastWeekShape(memory: hypertrophyMemory(), today: monday()))
    }
}
