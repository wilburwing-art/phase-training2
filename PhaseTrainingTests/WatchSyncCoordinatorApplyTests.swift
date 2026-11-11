// WatchSyncCoordinatorApplyTests.swift — the phone side of the watch link.
// WatchSyncReducerTests covers the pure fold; these drive WatchSyncCoordinator
// .apply against a real SessionStore (in-memory database, isolated defaults)
// to catch a result that the reducer produced and the coordinator dropped.
//
// The coordinator also activates WCSession.default and prunes MotionStore in
// its init; neither is stubbable without an app change, and neither reads or
// writes the stores under test.

import XCTest
@testable import PhaseTraining

@MainActor
final class WatchSyncCoordinatorApplyTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func t(_ s: Double) -> Date { start.addingTimeInterval(s) }

    private var suites: [String] = []
    override func tearDown() {
        for s in suites { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "watch-sync-\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func session() -> ActiveSession {
        func ex(_ id: String, _ name: String) -> LoggedExercise {
            LoggedExercise(id: id, name: name, type: nil, unit: "lb", targetSets: 3, targetReps: 5, rest: 120,
                           sets: (1...3).map { LoggedSet(num: $0, weight: "135", reps: "5", rpe: "", done: false) },
                           prevSets: [], rpe: nil, tempo: nil)
        }
        return ActiveSession(templateId: "t", name: "Lower A", category: "Generated", startTime: start,
                             exercises: [ex("squat", "Barbell Back Squat"), ex("rdl", "Romanian Deadlift")],
                             feel: nil, note: nil)
    }

    private struct Rig {
        let sessions: SessionStore
        let coordinator: WatchSyncCoordinator
        let defaults: UserDefaults
        let sessionDefaults: UserDefaults
    }

    private func rig(active: ActiveSession? = nil) -> Rig {
        let defaults = freshDefaults()
        let sessionDefaults = freshDefaults()
        let sessions = SessionStore(defaults: sessionDefaults, userDB: UserDatabase(path: ":memory:"))
        if let active { sessions.saveActive(active) }
        let plan = PlanStore(defaults: freshDefaults(), today: Date())
        return Rig(sessions: sessions,
                   coordinator: WatchSyncCoordinator(store: sessions, planStore: plan, defaults: defaults),
                   defaults: defaults, sessionDefaults: sessionDefaults)
    }

    private func done(_ ex: String, _ num: Int, at: Double, weight: String? = nil, reps: String? = nil,
                      id: UUID = UUID(), sessionStart: Date? = nil) -> WatchSyncEvent {
        WatchSyncEvent(id: id, sessionStart: sessionStart ?? start, exerciseId: ex, setNum: num,
                       kind: .setCompleted(weight: weight, reps: reps), at: t(at))
    }
    private func reopen(_ ex: String, _ num: Int, at: Double) -> WatchSyncEvent {
        WatchSyncEvent(sessionStart: start, exerciseId: ex, setNum: num, kind: .setReopened, at: t(at))
    }
    private func end(at: Double, id: UUID = UUID()) -> WatchSyncEvent {
        WatchSyncEvent(id: id, sessionStart: start, kind: .sessionEnded, at: t(at))
    }

    private func isDone(_ r: Rig, _ ex: String, _ num: Int) -> Bool {
        r.sessions.active!.exercises.first { $0.id == ex }!.sets.first { $0.num == num }!.done
    }
    private func doneCount(_ s: ActiveSession) -> Int {
        s.exercises.flatMap(\.sets).filter(\.done).count
    }

    // MARK: - Applying

    func testWatchSetsReachTheActiveSessionAndSurviveARelaunch() {
        let r = rig(active: session())
        r.coordinator.apply([done("squat", 1, at: 10, weight: "145"), done("squat", 2, at: 20)])

        XCTAssertTrue(isDone(r, "squat", 1))
        XCTAssertTrue(isDone(r, "squat", 2))
        XCTAssertFalse(isDone(r, "squat", 3))
        XCTAssertEqual(r.sessions.active?.exercises[0].sets[0].weight, "145")

        // A second SessionStore over the same defaults sees what was saved.
        let relaunched = SessionStore(defaults: r.sessionDefaults, userDB: UserDatabase(path: ":memory:"))
        XCTAssertEqual(relaunched.active.map(doneCount), 2)
    }

    func testDuplicateDeliveryOfTheSameEventsChangesNothing() {
        let r = rig(active: session())
        let events = [done("squat", 1, at: 10), done("rdl", 1, at: 20, reps: "8")]
        r.coordinator.apply(events)
        let afterFirst = r.sessions.active
        r.coordinator.apply(events)
        r.coordinator.apply([events[0]])
        XCTAssertEqual(r.sessions.active, afterFirst)
        XCTAssertEqual(r.sessions.active.map(doneCount), 2)
        XCTAssertEqual(r.sessions.active?.exercises.map { $0.sets.count }, [3, 3], "no set is added or doubled")
        XCTAssertEqual(r.coordinator.state.appliedEventIds.count, 2)
    }

    func testDuplicateDoesNotReclaimASetThePhoneReopenedAfterwards() {
        let r = rig(active: session())
        let e = done("squat", 1, at: 10)
        r.coordinator.apply([e])
        var edited = r.sessions.active!
        edited.exercises[0].sets[0].done = false
        r.sessions.saveActive(edited)
        r.coordinator.apply([e])
        XCTAssertFalse(isDone(r, "squat", 1), "a redelivered event must not undo the phone's reopen")
    }

    func testEventsInOneBatchApplyInTimeOrderNotArrivalOrder() {
        let r = rig(active: session())
        r.coordinator.apply([reopen("squat", 1, at: 90), done("squat", 1, at: 60)])
        XCTAssertFalse(isDone(r, "squat", 1), "complete@60 then reopen@90 leaves the set open")
    }

    /// The live message path and the queued userInfo path both call apply with
    /// one event, so a late queued complete can land after a newer reopen.
    /// The reducer keeps no per-set timestamp, so the older event wins.
    func testAnOlderEventArrivingInALaterBatchDoesNotOverrideANewerOne() {
        let r = rig(active: session())
        r.coordinator.apply([done("squat", 1, at: 30)])
        r.coordinator.apply([reopen("squat", 1, at: 90)])
        XCTAssertFalse(isDone(r, "squat", 1))
        r.coordinator.apply([done("squat", 1, at: 60)])   // queued earlier, delivered later
        XCTExpectFailure("reducer orders within a batch only, so complete@60 reopens-over reopen@90") {
            XCTAssertFalse(isDone(r, "squat", 1))
        }
    }

    func testEventForAnotherSessionIsDropped() {
        let r = rig(active: session())
        r.coordinator.apply([done("squat", 1, at: 10, sessionStart: start.addingTimeInterval(-86_400))])
        XCTAssertEqual(r.sessions.active.map(doneCount), 0)
    }

    func testUnknownExerciseAndUnknownSetAreDroppedWithoutHarm() {
        let r = rig(active: session())
        let before = r.sessions.active
        r.coordinator.apply([done("ghost", 1, at: 10), done("squat", 99, at: 11)])
        XCTAssertEqual(r.sessions.active, before)
    }

    func testPhoneEditAfterTheWatchTapWinsThroughTheCoordinatorLedger() {
        let r = rig(active: session())
        // The phone edits set 1 now (reps 6). The ledger records that via the
        // $active subscription, and a watch tap stamped earlier must lose.
        var edited = r.sessions.active!
        edited.exercises[0].sets[0].reps = "6"
        r.sessions.saveActive(edited)
        r.coordinator.apply([done("squat", 1, at: -3600, reps: "5")])
        XCTAssertFalse(isDone(r, "squat", 1))
        XCTAssertEqual(r.sessions.active?.exercises[0].sets[0].reps, "6")
    }

    func testWatchTapStampedAfterThePhoneEditStillApplies() {
        let r = rig(active: session())
        var edited = r.sessions.active!
        edited.exercises[0].sets[0].reps = "6"
        r.sessions.saveActive(edited)
        let later = WatchSyncEvent(sessionStart: start, exerciseId: "squat", setNum: 1,
                                   kind: .setCompleted(weight: nil, reps: nil),
                                   at: Date().addingTimeInterval(3600))
        r.coordinator.apply([later])
        XCTAssertTrue(isDone(r, "squat", 1))
    }

    // MARK: - Ending and starting

    func testSessionEndedCompletesTheSessionOnceWithItsSets() {
        let r = rig(active: session())
        let endEvent = end(at: 300)
        r.coordinator.apply([done("squat", 1, at: 10), done("squat", 2, at: 20), endEvent])

        XCTAssertNil(r.sessions.active)
        XCTAssertEqual(r.sessions.savedSessions.count, 1)
        XCTAssertEqual(r.sessions.savedSessions[0].exercises.flatMap(\.sets).filter(\.done).count, 2)

        r.coordinator.apply([endEvent])   // redelivery
        XCTAssertEqual(r.sessions.savedSessions.count, 1, "a redelivered end must not save a second session")
        XCTAssertFalse(r.sessions.persistenceFailed)
    }

    func testEventsWithNoActiveSessionAreDropped() {
        let r = rig()
        r.coordinator.apply([done("squat", 1, at: 10), end(at: 20)])
        XCTAssertNil(r.sessions.active)
        XCTAssertTrue(r.sessions.savedSessions.isEmpty)
    }

    func testWatchStartIsAdoptedWithTheWatchsStartTimeSoLaterSetsLineUp() {
        let r = rig()
        let started = WatchSyncEvent(sessionStart: start, kind: .sessionStarted(session()), at: t(0))
        r.coordinator.apply([started])
        XCTAssertEqual(r.sessions.active?.startTime, start)
        r.coordinator.apply([done("squat", 1, at: 10)])
        XCTAssertTrue(isDone(r, "squat", 1))
    }

    func testRedeliveredStartAfterTheSessionEndedDoesNotResurrectIt() {
        let r = rig()
        let started = WatchSyncEvent(sessionStart: start, kind: .sessionStarted(session()), at: t(0))
        r.coordinator.apply([started, done("squat", 1, at: 10), end(at: 60)])
        XCTAssertNil(r.sessions.active)
        XCTAssertEqual(r.sessions.savedSessions.count, 1)

        r.coordinator.apply([started])   // transferUserInfo redelivery
        XCTAssertNil(r.sessions.active)
        XCTAssertEqual(r.sessions.savedSessions.count, 1)
    }

    func testWatchWorkoutStartedMarksTheWatchAsHealthWriter() {
        let r = rig(active: session())
        r.coordinator.apply([WatchSyncEvent(sessionStart: start, kind: .watchWorkoutStarted, at: t(1))])
        XCTAssertEqual(r.sessions.active?.healthWriter, .watch)
    }

    func testAppliedStatePersistsSoARelaunchedCoordinatorStillIgnoresDuplicates() {
        let r = rig(active: session())
        let e = done("squat", 1, at: 10)
        r.coordinator.apply([e])
        XCTAssertNotNil(r.defaults.data(forKey: WatchSyncCoordinator.stateKey))

        let plan = PlanStore(defaults: freshDefaults(), today: Date())
        let second = WatchSyncCoordinator(store: r.sessions, planStore: plan, defaults: r.defaults)
        XCTAssertTrue(second.state.appliedEventIds.contains(e.id))
    }
}
