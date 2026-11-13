import XCTest
@testable import PhaseTraining

final class RestActivityCoordinatorTests: XCTestCase {
    enum Call: Equatable {
        case start(String, RestActivityState, Date)
        case update(RestActivityState, Date)
        case endAll

        var kind: String {
            switch self {
            case .start: return "start"
            case .update: return "update"
            case .endAll: return "end"
            }
        }
    }

    final class FakeHost: RestActivityHost {
        var isAvailable = true
        var startSucceeds = true
        var calls: [Call] = []
        func start(workoutName: String, state: RestActivityState, staleDate: Date) -> Bool {
            calls.append(.start(workoutName, state, staleDate))
            return startSucceeds
        }
        func update(state: RestActivityState, staleDate: Date) { calls.append(.update(state, staleDate)) }
        func endAll() { calls.append(.endAll) }
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snap(set: Int = 1, end: TimeInterval = 90, workout: String = "Upper A") -> RestSnapshot {
        RestSnapshot(workoutName: workout, exerciseName: "Bench press", setNumber: set,
                     totalSets: 4, endDate: t0.addingTimeInterval(end))
    }

    private func make() -> (RestActivityCoordinator, FakeHost) {
        let host = FakeHost()
        return (RestActivityCoordinator(host: host), host)
    }

    func test_restStart_startsActivityWithStaleDateAtRestEnd() {
        let (c, host) = make()
        c.sync(snap(), now: t0)
        let s = RestActivityState(exerciseName: "Bench press", setNumber: 1, totalSets: 4,
                                  restEndDate: t0.addingTimeInterval(90))
        XCTAssertEqual(host.calls, [.start("Upper A", s, t0.addingTimeInterval(90))])
    }

    func test_extend_updatesInPlace() {
        let (c, host) = make()
        c.sync(snap(end: 90), now: t0)
        c.sync(snap(end: 105), now: t0)
        XCTAssertEqual(host.calls.map(\.kind), ["start", "update"])
        guard case .update(let s, let stale) = host.calls[1] else { return XCTFail("expected update") }
        XCTAssertEqual(s.restEndDate, t0.addingTimeInterval(105))
        XCTAssertEqual(stale, t0.addingTimeInterval(105))
    }

    func test_shorten_updatesInPlace() {
        let (c, host) = make()
        c.sync(snap(end: 90), now: t0)
        c.sync(snap(end: 75), now: t0)
        guard case .update(let s, _) = host.calls[1] else { return XCTFail("expected update") }
        XCTAssertEqual(s.restEndDate, t0.addingTimeInterval(75))
    }

    func test_skip_endsActivity() {
        let (c, host) = make()
        c.sync(snap(), now: t0)
        c.sync(nil)
        XCTAssertEqual(host.calls.last, .endAll)
        XCTAssertNil(c.current)
    }

    func test_nextSet_updatesSameActivityNotANewOne() {
        let (c, host) = make()
        c.sync(snap(set: 1, end: 90), now: t0)
        c.sync(snap(set: 2, end: 200), now: t0)
        XCTAssertEqual(host.calls.map(\.kind), ["start", "update"])
        guard case .update(let s, _) = host.calls[1] else { return XCTFail("expected update") }
        XCTAssertEqual(s.setNumber, 2)
    }

    func test_identicalSnapshot_issuesNothing() {
        let (c, host) = make()
        c.sync(snap(), now: t0)
        c.sync(snap(), now: t0)
        XCTAssertEqual(host.calls.count, 1)
    }

    func test_expiry_marksFinished() {
        let (c, host) = make()
        c.sync(snap(), now: t0)
        c.restExpired()
        guard case .update(let s, _) = host.calls[1] else { return XCTFail("expected update") }
        XCTAssertTrue(s.finished)
        c.restExpired()
        XCTAssertEqual(host.calls.count, 2, "a second expiry report issues nothing")
    }

    func test_expiryThenNextRest_clearsFinished() {
        let (c, host) = make()
        c.sync(snap(set: 1, end: 90), now: t0)
        c.restExpired()
        c.sync(snap(set: 2, end: 300), now: t0)
        guard case .update(let s, _) = host.calls[2] else { return XCTFail("expected update") }
        XCTAssertFalse(s.finished)
        XCTAssertEqual(s.setNumber, 2)
    }

    func test_expiryWithNoActivity_issuesNothing() {
        let (c, host) = make()
        c.restExpired()
        XCTAssertTrue(host.calls.isEmpty)
    }

    func test_finishCancelAbandon_endActivity() {
        let (c, host) = make()
        c.sync(snap(), now: t0)
        c.sessionEnded()
        XCTAssertEqual(host.calls.last, .endAll)
        XCTAssertNil(c.current)
    }

    func test_activitiesDisabled_issuesNothing() {
        let (c, host) = make()
        host.isAvailable = false
        c.sync(snap(), now: t0)
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertNil(c.current)
    }

    func test_failedStart_leavesNoActivityAndRetriesNextTime() {
        let (c, host) = make()
        host.startSucceeds = false
        c.sync(snap(), now: t0)
        XCTAssertNil(c.current)
        host.startSucceeds = true
        c.sync(snap(end: 100), now: t0)
        XCTAssertEqual(host.calls.map(\.kind), ["start", "start"])
        XCTAssertNotNil(c.current)
    }

    func test_relaunchWithNoSession_endsLeftoverActivities() {
        let (c, host) = make()
        c.appLaunched()
        XCTAssertEqual(host.calls, [.endAll])
    }

    func test_differentWorkout_replacesLeftoverActivity() {
        let (c, host) = make()
        c.sync(snap(workout: "Upper A"), now: t0)
        c.sync(snap(workout: "Lower B"), now: t0)
        XCTAssertEqual(host.calls.map(\.kind), ["start", "end", "start"])
    }

    func test_expiryThenSameSnapshot_keepsFinished() {
        let (c, host) = make()
        c.sync(snap(), now: t0)
        c.restExpired()
        c.sync(snap(), now: t0.addingTimeInterval(91))
        c.sync(snap(), now: t0.addingTimeInterval(92))
        XCTAssertEqual(host.calls.map(\.kind), ["start", "update"])
        XCTAssertEqual(c.current?.finished, true)
    }

    func test_restAlreadyOver_doesNotStart() {
        let (c, host) = make()
        c.sync(snap(end: 90), now: t0.addingTimeInterval(91))
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertNil(c.current)
    }

    func test_restEndingExactlyNow_doesNotStart() {
        let (c, host) = make()
        c.sync(snap(end: 90), now: t0.addingTimeInterval(90))
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertNil(c.current)
    }

    func test_failedStartThenExpiredRetry_doesNotStart() {
        let (c, host) = make()
        host.startSucceeds = false
        c.sync(snap(end: 90), now: t0)
        host.startSucceeds = true
        c.sync(snap(end: 90), now: t0.addingTimeInterval(120))
        XCTAssertEqual(host.calls.map(\.kind), ["start"])
        XCTAssertNil(c.current)
    }

    func test_updateStillSentForPastEndDate() {
        let (c, host) = make()
        c.sync(snap(end: 90), now: t0)
        c.sync(snap(end: 30), now: t0.addingTimeInterval(60))
        XCTAssertEqual(host.calls.map(\.kind), ["start", "update"])
    }

    func test_stateRoundTripsThroughCodable() throws {
        let s = RestActivityState(exerciseName: "Row", setNumber: 2, totalSets: 3,
                                  restEndDate: t0, finished: true)
        let back = try JSONDecoder().decode(RestActivityState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
