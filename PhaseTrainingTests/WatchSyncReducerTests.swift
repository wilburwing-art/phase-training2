// WatchSyncReducerTests.swift — the three rules of the watch sync reducer
// (PLAN-watch.md, step 1): idempotent on id, ordered by time, phone wins.

import XCTest
@testable import PhaseTraining

final class WatchSyncReducerTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private func t(_ s: Double) -> Date { start.addingTimeInterval(s) }

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

    private func done(_ ex: String, _ num: Int, at: Double, weight: String? = nil, reps: String? = nil,
                      id: UUID = UUID()) -> WatchSyncEvent {
        WatchSyncEvent(id: id, sessionStart: start, exerciseId: ex, setNum: num,
                       kind: .setCompleted(weight: weight, reps: reps), at: t(at))
    }
    private func reopen(_ ex: String, _ num: Int, at: Double) -> WatchSyncEvent {
        WatchSyncEvent(sessionStart: start, exerciseId: ex, setNum: num, kind: .setReopened, at: t(at))
    }

    private func isDone(_ s: ActiveSession, _ ex: String, _ num: Int) -> Bool {
        s.exercises.first { $0.id == ex }!.sets.first { $0.num == num }!.done
    }

    func test_completesTheSet_andFillsNudgedValues() {
        let out = WatchSyncReducer.apply([done("squat", 1, at: 60, weight: "140", reps: nil)],
                                         to: session(), state: WatchSyncState())
        let set = out.session.exercises[0].sets[0]
        XCTAssertTrue(set.done)
        XCTAssertEqual(set.weight, "140")
        XCTAssertEqual(set.reps, "5", "nil leaves the phone's value alone")
        XCTAssertEqual(out.applied.count, 1)
        XCTAssertFalse(out.ended)
        XCTAssertEqual(out.state.sessionStart, start)
    }

    func test_idempotentOnEventId() {
        let e = done("squat", 1, at: 60)
        let first = WatchSyncReducer.apply([e], to: session(), state: WatchSyncState())
        let second = WatchSyncReducer.apply([e], to: first.session, state: first.state)
        XCTAssertEqual(second.session, first.session)
        XCTAssertTrue(second.applied.isEmpty, "a redelivered event changes nothing")
        // Reopened on the phone afterwards: the same event still does not come back.
        var reopened = first.session
        reopened.exercises[0].sets[0].done = false
        let third = WatchSyncReducer.apply([e], to: reopened, state: first.state)
        XCTAssertFalse(isDone(third.session, "squat", 1))
    }

    func test_orderedByTime_whateverOrderTheyArrive() {
        let a = done("squat", 1, at: 60)
        let b = reopen("squat", 1, at: 90)
        let forward = WatchSyncReducer.apply([a, b], to: session(), state: WatchSyncState())
        let backward = WatchSyncReducer.apply([b, a], to: session(), state: WatchSyncState())
        XCTAssertFalse(isDone(forward.session, "squat", 1))
        XCTAssertEqual(forward.session, backward.session)
        XCTAssertEqual(forward.applied.map(\.id), backward.applied.map(\.id))

        let c = done("squat", 1, at: 120)
        let again = WatchSyncReducer.apply([c], to: forward.session, state: forward.state)
        XCTAssertTrue(isDone(again.session, "squat", 1))
    }

    func test_phoneEditAfterTheEvent_wins() {
        var state = WatchSyncState(sessionStart: start)
        state.notePhoneEdit(exerciseId: "squat", setNum: 1, at: t(100))
        let out = WatchSyncReducer.apply([done("squat", 1, at: 60)], to: session(), state: state)
        XCTAssertFalse(isDone(out.session, "squat", 1))
        XCTAssertTrue(out.applied.isEmpty)
        XCTAssertEqual(out.state.appliedEventIds.count, 1, "consumed, so it cannot apply later")

        // An edit before the event does not block it.
        var earlier = WatchSyncState(sessionStart: start)
        earlier.notePhoneEdit(exerciseId: "squat", setNum: 1, at: t(30))
        XCTAssertTrue(isDone(WatchSyncReducer.apply([done("squat", 1, at: 60)], to: session(), state: earlier).session,
                             "squat", 1))
    }

    func test_notePhoneEdit_keepsTheLatest() {
        var state = WatchSyncState(sessionStart: start)
        state.notePhoneEdit(exerciseId: "squat", setNum: 1, at: t(100))
        state.notePhoneEdit(exerciseId: "squat", setNum: 1, at: t(50))
        XCTAssertEqual(state.phoneEdits[WatchSyncState.setKey(exerciseId: "squat", setNum: 1)], t(100))
    }

    func test_staleSessionAndUnknownTargets_areConsumedNotApplied() {
        let other = WatchSyncEvent(sessionStart: t(-3600), exerciseId: "squat", setNum: 1,
                                   kind: .setCompleted(weight: nil, reps: nil), at: t(10))
        let noSuchExercise = done("bench", 1, at: 20)
        let noSuchSet = done("squat", 9, at: 30)
        let out = WatchSyncReducer.apply([other, noSuchExercise, noSuchSet], to: session(), state: WatchSyncState())
        XCTAssertEqual(out.session, session())
        XCTAssertTrue(out.applied.isEmpty)
        XCTAssertEqual(out.state.appliedEventIds.count, 3)
    }

    func test_stateFromAnotherSession_isReplaced() {
        var old = WatchSyncState(sessionStart: t(-86_400))
        old.notePhoneEdit(exerciseId: "squat", setNum: 1, at: t(100))
        old.appliedEventIds.insert(UUID())
        let out = WatchSyncReducer.apply([done("squat", 1, at: 60)], to: session(), state: old)
        XCTAssertTrue(isDone(out.session, "squat", 1), "yesterday's phone edit does not block today's set")
        XCTAssertEqual(out.state.sessionStart, start)
        XCTAssertEqual(out.state.appliedEventIds.count, 1)
    }

    func test_sessionEnded_setsTheFlag() {
        let end = WatchSyncEvent(sessionStart: start, kind: .sessionEnded, at: t(3000))
        let out = WatchSyncReducer.apply([done("squat", 1, at: 60), end], to: session(), state: WatchSyncState())
        XCTAssertTrue(out.ended)
        XCTAssertEqual(out.applied.count, 2)
        XCTAssertFalse(WatchSyncReducer.apply([end], to: out.session, state: out.state).ended,
                       "consumed with everything else")
    }

    func test_watchWorkoutStarted_handsTheHealthWriteToTheWatch() {
        let claim = WatchSyncEvent(sessionStart: start, kind: .watchWorkoutStarted, at: t(5))
        let out = WatchSyncReducer.apply([claim], to: session(), state: WatchSyncState())
        XCTAssertEqual(out.session.healthWriter, .watch)
        XCTAssertEqual(out.applied.count, 1)
        let again = WatchSyncReducer.apply([WatchSyncEvent(sessionStart: start, kind: .watchWorkoutStarted, at: t(6))],
                                           to: out.session, state: out.state)
        XCTAssertTrue(again.applied.isEmpty, "already the watch's")
    }

    func test_eventsRoundTripThroughJSON() throws {
        let e = done("squat", 2, at: 60, weight: "140", reps: "6")
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(WatchSyncEvent.self, from: data), e)
        let ctx = WatchSyncContext(activeSession: session(), sentAt: t(1))
        XCTAssertEqual(try JSONDecoder().decode(WatchSyncContext.self, from: try JSONEncoder().encode(ctx)), ctx)
    }
}
