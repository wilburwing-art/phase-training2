import XCTest
@testable import PhaseTraining

/// RestTimerState had no unit tests; T1-2 added the backgrounded expiry
/// notification to it. The notification center is not unit-testable, but the
/// value type's own math is, and `remaining(at:)` drives both the in-app alert
/// and the reschedule after a "+15".
@MainActor
final class RestTimerStateTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_noRestMeansNoRemaining() {
        XCTAssertNil(RestTimerState().remaining(at: t0))
    }

    func test_startSetsEveryFieldAndCountsDown() {
        var r = RestTimerState()
        r.start(exIdx: 2, setIdx: 1, duration: 90, now: t0)
        XCTAssertEqual(r.exIdx, 2); XCTAssertEqual(r.setIdx, 1)
        XCTAssertEqual(r.startedAt, t0); XCTAssertEqual(r.duration, 90)
        XCTAssertNil(r.alertFiredFor); XCTAssertNil(r.expiredFlashUntil)
        XCTAssertEqual(r.remaining(at: t0), 90)
        XCTAssertEqual(r.remaining(at: t0.addingTimeInterval(30)), 60)
        XCTAssertEqual(r.remaining(at: t0.addingTimeInterval(89)), 1)
    }

    func test_remainingIsNilAtAndAfterExpiry() {
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 60, now: t0)
        XCTAssertNil(r.remaining(at: t0.addingTimeInterval(60)), "0 remaining reads as expired")
        XCTAssertNil(r.remaining(at: t0.addingTimeInterval(600)))
    }

    func test_plus15ExtendsInPlace() {
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 60, now: t0)
        r.duration = (r.duration ?? 0) + 15
        XCTAssertEqual(r.remaining(at: t0.addingTimeInterval(60)), 15,
                       "extending the duration must move the expiry, not restart the clock")
    }

    func test_clearResetsEverything() {
        var r = RestTimerState()
        r.start(exIdx: 3, setIdx: 2, duration: 120, now: t0)
        r.alertFiredFor = t0; r.expiredFlashUntil = t0
        r.clear()
        XCTAssertNil(r.exIdx); XCTAssertNil(r.setIdx); XCTAssertNil(r.startedAt)
        XCTAssertNil(r.duration); XCTAssertNil(r.alertFiredFor); XCTAssertNil(r.expiredFlashUntil)
        XCTAssertNil(r.remaining(at: t0))
    }

    func test_startingANewRestReplacesTheOld() {
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 60, now: t0)
        r.alertFiredFor = t0
        r.start(exIdx: 1, setIdx: 0, duration: 30, now: t0.addingTimeInterval(10))
        XCTAssertNil(r.alertFiredFor, "a new rest must re-arm the once-per-rest alert")
        XCTAssertEqual(r.remaining(at: t0.addingTimeInterval(10)), 30)
    }
}
