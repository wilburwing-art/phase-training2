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

    // MARK: - notification fire date follows the injected clock (voice 1.6)

    func test_startSchedulesFireAtInjectedNowPlusDuration() {
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 90, now: t0)
        XCTAssertEqual(RestTimerState.lastRequestedFireAt, t0.addingTimeInterval(90))
    }

    func test_rescheduleFiresAtInjectedNowPlusRemaining() {
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 60, now: t0)
        r.duration = 75
        r.rescheduleExpiryNotification(now: t0.addingTimeInterval(20))
        XCTAssertEqual(RestTimerState.lastRequestedFireAt, t0.addingTimeInterval(75),
                       "20 s in with 55 s left fires at start plus the new duration")
    }

    func test_clearDropsTheRequestedFireDate() {
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 60, now: t0)
        r.clear()
        XCTAssertNil(RestTimerState.lastRequestedFireAt)
    }

    // MARK: - spoken rest end on a locked phone (voice 2.3)

    private var savedRender: (@MainActor (String) async throws -> URL)!
    private var savedDir: URL!
    private var dir: URL!

    override func setUp() async throws {
        savedRender = RestTimerState.renderCue
        savedDir = RestTimerState.soundsDirectory
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestTimerStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RestTimerState.soundsDirectory = dir
    }

    override func tearDown() async throws {
        await RestTimerState.pendingRender?.value
        RestTimerState.cancelExpiryNotification()
        RestTimerState.renderCue = savedRender
        RestTimerState.soundsDirectory = savedDir
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a placeholder file standing in for a rendered cue.
    private func cueFile(_ name: String) -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        return url
    }

    func test_inTimeRenderSetsTheCueSoundName() async {
        let url = cueFile("pt_speech_abc.caf")
        var rendered: [String] = []
        RestTimerState.renderCue = { line in rendered.append(line); return url }
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 90, now: t0, cue: "Rest's up. Bench, set 2 of 3.")
        XCTAssertNil(RestTimerState.lastRequestedSoundName, "armed with .default before the render lands")
        await RestTimerState.pendingRender?.value
        XCTAssertEqual(rendered, ["Rest's up. Bench, set 2 of 3."])
        XCTAssertEqual(RestTimerState.lastRequestedSoundName, "pt_speech_abc.caf")
    }

    func test_noCueKeepsTheDefaultSoundAndRendersNothing() async {
        var renders = 0
        RestTimerState.renderCue = { _ in renders += 1; return self.cueFile("pt_speech_x.caf") }
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 90, now: t0)
        await RestTimerState.pendingRender?.value
        XCTAssertEqual(renders, 0)
        XCTAssertNil(RestTimerState.lastRequestedSoundName)
    }

    func test_failedRenderFallsBackToDefault() async {
        RestTimerState.renderCue = { _ in throw SpeechOutputError.noVoice }
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 90, now: t0, cue: "Rest's up.")
        await RestTimerState.pendingRender?.value
        XCTAssertNil(RestTimerState.lastRequestedSoundName)
    }

    func test_lateRenderFallsBackToDefault() async {
        let url = cueFile("pt_speech_late.caf")
        RestTimerState.renderCue = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            return url
        }
        var r = RestTimerState()
        // 2 s rest, 0.3 s render: 1.7 s left is under the 2 s lead.
        r.start(exIdx: 0, setIdx: 0, duration: 2, now: t0, cue: "Rest's up.")
        await RestTimerState.pendingRender?.value
        XCTAssertNil(RestTimerState.lastRequestedSoundName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an unused render is deleted")
    }

    func test_plus15RerendersAndANewerScheduleWins() async {
        let first = cueFile("pt_speech_first.caf")
        let second = cueFile("pt_speech_second.caf")
        var calls = 0
        RestTimerState.renderCue = { _ in
            calls += 1
            if calls == 1 {
                try await Task.sleep(nanoseconds: 300_000_000)
                return first
            }
            return second
        }
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 60, now: t0, cue: "one")
        let slow = RestTimerState.pendingRender
        r.duration = 75
        r.rescheduleExpiryNotification(now: t0.addingTimeInterval(5), cue: "two")
        await RestTimerState.pendingRender?.value
        await slow?.value
        XCTAssertEqual(calls, 2, "+15 re-renders the line")
        XCTAssertEqual(RestTimerState.lastRequestedSoundName, "pt_speech_second.caf",
                       "the slower render for the replaced request must not win")
    }

    func test_renderDeletesStaleCueFilesAndKeepsTheOneInUse() async {
        let stale = cueFile("pt_speech_old.caf")
        let other = cueFile("unrelated.caf")
        let current = cueFile("pt_speech_new.caf")
        RestTimerState.renderCue = { _ in current }
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 90, now: t0, cue: "Rest's up.")
        await RestTimerState.pendingRender?.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "only pt_speech_ files are swept")
    }

    func test_clearDropsTheCueSoundAndItsFile() async {
        let current = cueFile("pt_speech_now.caf")
        RestTimerState.renderCue = { _ in current }
        var r = RestTimerState()
        r.start(exIdx: 0, setIdx: 0, duration: 90, now: t0, cue: "Rest's up.")
        await RestTimerState.pendingRender?.value
        r.clear()
        XCTAssertNil(RestTimerState.lastRequestedSoundName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
    }
}
