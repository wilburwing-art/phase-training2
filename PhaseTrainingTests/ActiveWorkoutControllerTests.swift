import XCTest
import UIKit
@testable import PhaseTraining

@MainActor
final class ActiveWorkoutControllerTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var haptics: [UIImpactFeedbackGenerator.FeedbackStyle] = []

    // MARK: - Fixtures

    private func defaults() -> UserDefaults {
        let suite = "ActiveWorkoutControllerTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func exercise(_ name: String, sets: Int, rest: Int = 90,
                          group: Int? = nil, weight: String = "") -> LoggedExercise {
        LoggedExercise(id: "ex-\(name)", name: name, type: nil, unit: "lbs",
                       targetSets: sets, targetReps: 8, rest: rest,
                       sets: (0..<sets).map {
                           LoggedSet(num: $0 + 1, weight: weight, reps: "", rpe: "", done: false)
                       },
                       prevSets: [], supersetGroup: group)
    }

    private func make(_ exercises: [LoggedExercise],
                      suppressAutoRest: Bool = false) -> (ActiveWorkoutController, SessionStore) {
        let store = SessionStore(defaults: defaults())
        let session = ActiveSession(templateId: "t", name: "Test", category: "Custom",
                                    startTime: Date(), exercises: exercises,
                                    feel: nil, note: nil)
        store.saveActive(session)
        let c = ActiveWorkoutController(store: store, session: session,
                                        suppressAutoRest: suppressAutoRest,
                                        haptic: { [unowned self] in haptics.append($0) },
                                        now: { [unowned self] in clock })
        return (c, store)
    }

    // MARK: - logSet

    func test_logSetWritesValuesMarksDoneAndSaves() {
        let (c, store) = make([exercise("Bench", sets: 3)])
        c.logSet(exIdx: 0, setIdx: 0, weight: "135", reps: "8", rpe: "7")
        let set = c.session.exercises[0].sets[0]
        XCTAssertEqual(set.weight, "135")
        XCTAssertEqual(set.reps, "8")
        XCTAssertEqual(set.rpe, "7")
        XCTAssertTrue(set.done)
        XCTAssertEqual(store.active, c.session)
        XCTAssertEqual(c.rest.duration, 90)
        XCTAssertEqual(c.rest.exIdx, 0); XCTAssertEqual(c.rest.setIdx, 0)
    }

    func test_logSetNilParamsKeepCellValues() {
        let (c, store) = make([exercise("Bench", sets: 3, weight: "100")])
        c.logSet(exIdx: 0, setIdx: 1, weight: nil, reps: "10", rpe: nil)
        let set = c.session.exercises[0].sets[1]
        XCTAssertEqual(set.weight, "100")
        XCTAssertEqual(set.reps, "10")
        XCTAssertEqual(set.rpe, "")
        XCTAssertTrue(set.done)
        XCTAssertEqual(store.active, c.session)
    }

    func test_logSetOnDoneSetUpdatesValuesWithoutRestartingRest() {
        let (c, store) = make([exercise("Bench", sets: 3)])
        c.logSet(exIdx: 0, setIdx: 0, weight: "135", reps: "8", rpe: nil)
        let startedAt = c.rest.startedAt
        clock.addTimeInterval(30)
        c.logSet(exIdx: 0, setIdx: 0, weight: "140", reps: nil, rpe: nil)
        XCTAssertEqual(c.session.exercises[0].sets[0].weight, "140")
        XCTAssertEqual(c.session.exercises[0].sets[0].reps, "8")
        XCTAssertEqual(c.rest.startedAt, startedAt, "rest keeps its original anchor")
        XCTAssertEqual(store.active, c.session)
    }

    func test_logSetOutOfRangeIsNoOp() {
        let (c, store) = make([exercise("Bench", sets: 2)])
        let before = c.session
        c.logSet(exIdx: 5, setIdx: 0, weight: "1", reps: "1", rpe: "1")
        c.logSet(exIdx: 0, setIdx: 9, weight: "1", reps: "1", rpe: "1")
        XCTAssertEqual(c.session, before)
        XCTAssertEqual(store.active, before)
        XCTAssertNil(c.rest.startedAt)
    }

    // MARK: - toggle / rest rules

    func test_toggleCompleteStartsRestWithExerciseRest() {
        let (c, store) = make([exercise("Row", sets: 3, rest: 120)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertTrue(c.session.exercises[0].sets[0].done)
        XCTAssertEqual(c.rest.duration, 120)
        XCTAssertEqual(c.rest.startedAt, clock)
        XCTAssertEqual(c.rest.remaining(at: clock), 120)
        XCTAssertEqual(haptics, [.light])
        XCTAssertEqual(store.active, c.session)
    }

    func test_zeroRestRowStartsNoRest() {
        let (c, _) = make([exercise("Crawl", sets: 3, rest: 0)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertTrue(c.session.exercises[0].sets[0].done)
        XCTAssertNil(c.rest.startedAt, "a row written with no rest starts no timer")
        XCTAssertNil(c.rest.duration)
    }

    func test_finalSetOfExerciseGetsNoRest() {
        let (c, _) = make([exercise("Row", sets: 2), exercise("Curl", sets: 2)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertNotNil(c.rest.startedAt)
        c.toggleSet(exIdx: 0, setIdx: 1)
        XCTAssertNil(c.rest.startedAt, "final set clears the earlier rest and starts none")
        XCTAssertNil(c.rest.duration)
    }

    func test_toggleOffClearsAnchoredRest() {
        let (c, store) = make([exercise("Row", sets: 3)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertNotNil(c.rest.startedAt)
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertFalse(c.session.exercises[0].sets[0].done)
        XCTAssertNil(c.rest.startedAt)
        XCTAssertEqual(store.active, c.session)
    }

    func test_toggleOffOtherSetKeepsRest() {
        let (c, _) = make([exercise("Row", sets: 4)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        c.toggleSet(exIdx: 0, setIdx: 1)
        XCTAssertEqual(c.rest.setIdx, 1)
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertEqual(c.rest.setIdx, 1, "un-ticking a different set leaves the anchored rest")
    }

    func test_suppressAutoRestBlocksRest() {
        let (c, _) = make([exercise("Row", sets: 3)], suppressAutoRest: true)
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertTrue(c.session.exercises[0].sets[0].done)
        XCTAssertNil(c.rest.startedAt)
        c.logSet(exIdx: 0, setIdx: 1, weight: "50", reps: "8", rpe: nil)
        XCTAssertNil(c.rest.startedAt)
    }

    func test_reopenSetClearsAnchoredRestAndKeepsValues() {
        let (c, store) = make([exercise("Row", sets: 3)])
        c.logSet(exIdx: 0, setIdx: 0, weight: "95", reps: "8", rpe: nil)
        c.reopenSet(exIdx: 0, setIdx: 0)
        XCTAssertFalse(c.session.exercises[0].sets[0].done)
        XCTAssertEqual(c.session.exercises[0].sets[0].weight, "95")
        XCTAssertNil(c.rest.startedAt)
        XCTAssertEqual(store.active, c.session)
    }

    func test_addSetCopiesLastSetAndSaves() {
        let (c, store) = make([exercise("Row", sets: 2, weight: "60")])
        c.addSet(exIdx: 0)
        let sets = c.session.exercises[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[2].num, 3)
        XCTAssertEqual(sets[2].weight, "60")
        XCTAssertFalse(sets[2].done)
        XCTAssertEqual(store.active, c.session)
    }

    func test_setRIRWritesAndSaves() {
        let (c, store) = make([exercise("Row", sets: 2)])
        c.setRIR(exIdx: 0, setIdx: 1, value: "2")
        XCTAssertEqual(c.session.exercises[0].sets[1].rir, "2")
        XCTAssertEqual(store.active, c.session)
        c.setRIR(exIdx: 3, setIdx: 0, value: "2")
        XCTAssertEqual(store.active, c.session)
    }

    // MARK: - skip / addRest

    func test_skipRestClears() {
        let (c, _) = make([exercise("Row", sets: 3)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        c.skipRest()
        XCTAssertNil(c.rest.startedAt)
        XCTAssertNil(c.rest.duration)
        XCTAssertNil(c.rest.exIdx)
    }

    func test_addRest15ExtendsDuration() {
        let (c, _) = make([exercise("Row", sets: 3, rest: 60)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        clock.addTimeInterval(20)
        c.addRest(seconds: 15)
        XCTAssertEqual(c.rest.duration, 75)
        XCTAssertEqual(c.rest.startedAt, Date(timeIntervalSince1970: 1_000_000),
                       "extending keeps the clock running from the original start")
        XCTAssertEqual(c.rest.remaining(at: clock), 55)
    }

    func test_addRestNegativeShortensWhileTimeRemains() {
        let (c, _) = make([exercise("Row", sets: 3, rest: 90)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        clock.addTimeInterval(10)
        c.addRest(seconds: -15)
        XCTAssertEqual(c.rest.duration, 75)
        XCTAssertNotNil(c.rest.startedAt)
    }

    func test_addRestNegativePastElapsedClears() {
        let (c, _) = make([exercise("Row", sets: 3, rest: 60)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        clock.addTimeInterval(50)
        c.addRest(seconds: -15)
        XCTAssertNil(c.rest.startedAt)
        XCTAssertNil(c.rest.duration)
    }

    func test_addRestNegativeExactlyToElapsedClears() {
        let (c, _) = make([exercise("Row", sets: 3, rest: 60)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        clock.addTimeInterval(45)
        c.addRest(seconds: -15)
        XCTAssertNil(c.rest.startedAt, "new duration equal to elapsed ends the rest")
    }

    func test_addRestWithNoActiveRestIsNoOp() {
        let (c, _) = make([exercise("Row", sets: 3)])
        c.addRest(seconds: 15)
        XCTAssertEqual(c.rest, RestTimerState())
        c.addRest(seconds: -15)
        XCTAssertEqual(c.rest, RestTimerState())
    }

    func test_restNotificationFiresAtInjectedClock() {
        let (c, _) = make([exercise("Row", sets: 3, rest: 60)])
        let t0 = clock
        c.toggleSet(exIdx: 0, setIdx: 0)
        XCTAssertEqual(RestTimerState.lastRequestedFireAt, t0.addingTimeInterval(60))
        clock.addTimeInterval(20)
        c.addRest(seconds: 15)
        XCTAssertEqual(RestTimerState.lastRequestedFireAt, t0.addingTimeInterval(75))
    }

    func test_setRestDurationRunsFromInjectedNow() {
        let (c, _) = make([exercise("Row", sets: 3, rest: 120)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        clock.addTimeInterval(30)
        c.setRestDuration(45)
        XCTAssertEqual(c.rest.startedAt, clock)
        XCTAssertEqual(c.rest.alertFiredFor, clock)
        XCTAssertEqual(c.rest.remaining(at: clock), 45)
        XCTAssertEqual(RestTimerState.lastRequestedFireAt, clock.addingTimeInterval(45))
    }

    func test_setRestDurationWithNoRestIsNoOp() {
        let (c, _) = make([exercise("Row", sets: 3)])
        c.setRestDuration(45)
        XCTAssertEqual(c.rest, RestTimerState())
    }

    // MARK: - nextUp

    func test_nextUpPlainSession() {
        let (c, _) = make([exercise("Squat", sets: 2), exercise("Curl", sets: 3)])
        XCTAssertEqual(c.nextUp(), NextUp(exIdx: 0, setIdx: 0, exerciseName: "Squat",
                                          setNumber: 1, totalSets: 2, targetReps: 8,
                                          lastWeight: nil))
        c.logSet(exIdx: 0, setIdx: 0, weight: "225", reps: "8", rpe: nil)
        XCTAssertEqual(c.nextUp()?.setIdx, 1)
        XCTAssertEqual(c.nextUp()?.lastWeight, "225")
        c.logSet(exIdx: 0, setIdx: 1, weight: nil, reps: "8", rpe: nil)
        let next = c.nextUp()
        XCTAssertEqual(next?.exIdx, 1)
        XCTAssertEqual(next?.setIdx, 0)
        XCTAssertEqual(next?.exerciseName, "Curl")
        XCTAssertEqual(next?.setNumber, 1)
        XCTAssertEqual(next?.totalSets, 3)
        XCTAssertNil(next?.lastWeight, "no done set and no own weight in the next exercise")
    }

    func test_nextUpFallsBackToOwnWeight() {
        let (c, _) = make([exercise("Press", sets: 2, weight: "45")])
        XCTAssertEqual(c.nextUp()?.lastWeight, "45")
    }

    func test_nextUpSkipsOutOfOrderDoneSet() {
        let (c, _) = make([exercise("Press", sets: 3)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        c.toggleSet(exIdx: 0, setIdx: 2)
        XCTAssertEqual(c.nextUp()?.setIdx, 1)
    }

    func test_nextUpAcrossSupersetRound() {
        let (c, _) = make([
            exercise("Warmup", sets: 1),
            exercise("A", sets: 2, group: 1),
            exercise("B", sets: 2, group: 1),
        ])
        c.logSet(exIdx: 0, setIdx: 0, weight: nil, reps: "10", rpe: nil)
        XCTAssertEqual(c.nextUp()?.exerciseName, "A")
        XCTAssertEqual(c.nextUp()?.setIdx, 0)

        // A1 done -> B1, with no rest mid-round.
        c.logSet(exIdx: 1, setIdx: 0, weight: "50", reps: "8", rpe: nil)
        XCTAssertTrue(c.isMidSupersetRound(exIdx: 1, setIdx: 0))
        XCTAssertNil(c.rest.startedAt, "no rest while B still owes set 1")
        XCTAssertEqual(c.nextUp()?.exIdx, 2)
        XCTAssertEqual(c.nextUp()?.setIdx, 0)

        // B1 done -> rest starts on B's rest, then A2.
        c.logSet(exIdx: 2, setIdx: 0, weight: "30", reps: "8", rpe: nil)
        XCTAssertFalse(c.isMidSupersetRound(exIdx: 2, setIdx: 0))
        XCTAssertEqual(c.rest.exIdx, 2)
        XCTAssertEqual(c.rest.duration, 90)
        let next = c.nextUp()
        XCTAssertEqual(next?.exIdx, 1)
        XCTAssertEqual(next?.setIdx, 1)
        XCTAssertEqual(next?.setNumber, 2)
        XCTAssertEqual(next?.lastWeight, "50")
    }

    func test_nextUpSupersetMemberWithFewerSets() {
        let (c, _) = make([
            exercise("A", sets: 3, group: 2),
            exercise("B", sets: 1, group: 2),
        ])
        c.toggleSet(exIdx: 0, setIdx: 0)
        c.toggleSet(exIdx: 1, setIdx: 0)
        XCTAssertEqual(c.nextUp()?.exIdx, 0)
        XCTAssertEqual(c.nextUp()?.setIdx, 1)
        c.toggleSet(exIdx: 0, setIdx: 1)
        XCTAssertFalse(c.isMidSupersetRound(exIdx: 0, setIdx: 1),
                       "a sibling with no set at this index does not gate rest")
        XCTAssertNotNil(c.rest.startedAt)
        XCTAssertEqual(c.nextUp()?.setIdx, 2)
    }

    func test_nextUpNilWhenAllDone() {
        let (c, _) = make([exercise("A", sets: 1), exercise("B", sets: 2, group: 1)])
        c.toggleSet(exIdx: 0, setIdx: 0)
        c.toggleSet(exIdx: 1, setIdx: 0)
        c.toggleSet(exIdx: 1, setIdx: 1)
        XCTAssertNil(c.nextUp())
    }

    func test_nextUpNilForEmptySession() {
        let (c, _) = make([])
        XCTAssertNil(c.nextUp())
    }
}
