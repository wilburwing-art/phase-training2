import UserNotifications
import XCTest
@testable import PhaseTraining

@MainActor
final class SpokenCueTests: XCTestCase {

    private func ex(_ name: String, sets: Int = 4, unit: String = "lb", group: Int? = nil,
                    weight: String = "", reps: String = "") -> LoggedExercise {
        LoggedExercise(
            id: name, name: name, type: nil, unit: unit, targetSets: sets, targetReps: 5, rest: 90,
            sets: (1...sets).map { LoggedSet(num: $0, weight: weight, reps: reps, rpe: "", done: false) },
            prevSets: [], supersetGroup: group)
    }

    private func session(_ exercises: [LoggedExercise]) -> ActiveSession {
        ActiveSession(templateId: "t", name: "Day", category: "strength",
                      startTime: Date(timeIntervalSince1970: 0), exercises: exercises)
    }

    private func next(_ name: String = "Bench Press", exIdx: Int = 0, set: Int = 3, of total: Int = 4,
                      reps: Int = 5, weight: String? = "185") -> NextUp {
        NextUp(exIdx: exIdx, setIdx: set - 1, exerciseName: name, setNumber: set, totalSets: total,
               targetReps: reps, lastWeight: weight)
    }

    // MARK: - Lines

    func testStraightSetMidExercise() {
        XCTAssertEqual(SpokenCue.restEnd(next: next(), in: session([ex("Bench Press")])),
                       "Rest's up. Bench Press, set 3 of 4, 185 for 5.")
    }

    func testStraightLastSet() {
        XCTAssertEqual(SpokenCue.restEnd(next: next(set: 4), in: session([ex("Bench Press")])),
                       "Rest's up. Bench Press, last set, 185 for 5.")
    }

    func testSupersetRound() {
        let s = session([ex("Bench Press", sets: 3, group: 1), ex("Row", sets: 3, group: 1)])
        XCTAssertEqual(SpokenCue.restEnd(next: next(set: 2, of: 3), in: s),
                       "Rest's up. Superset, round 2 of 3. Bench Press, 185 for 5.")
    }

    func testSupersetLastRound() {
        let s = session([ex("Bench Press", sets: 3, group: 1), ex("Row", sets: 3, group: 1)])
        XCTAssertEqual(SpokenCue.restEnd(next: next(set: 3, of: 3), in: s),
                       "Rest's up. Superset, last round. Bench Press, 185 for 5.")
    }

    func testBodyweightNoWeight() {
        let s = session([ex("Pull-up", unit: "bw")])
        XCTAssertEqual(SpokenCue.restEnd(next: next("Pull-up", set: 2, of: 3, reps: 8, weight: nil), in: s),
                       "Rest's up. Pull-up, set 2 of 3, 8 reps.")
    }

    func testWeightWithUnitSuffixReadsNumber() {
        XCTAssertEqual(SpokenCue.restEnd(next: next(weight: "60kg"), in: session([ex("Bench Press")])),
                       "Rest's up. Bench Press, set 3 of 4, 60 for 5.")
    }

    func testDecimalWeight() {
        XCTAssertEqual(SpokenCue.restEnd(next: next(weight: "92.5"), in: session([ex("Bench Press")])),
                       "Rest's up. Bench Press, set 3 of 4, 92.5 for 5.")
        XCTAssertEqual(SpokenCue.restEnd(next: next(weight: "60,5"), in: session([ex("Bench Press")])),
                       "Rest's up. Bench Press, set 3 of 4, 60.5 for 5.")
    }

    func testTargetRepsZero() {
        let s = session([ex("Plank")])
        XCTAssertEqual(SpokenCue.restEnd(next: next("Plank", set: 2, of: 3, reps: 0, weight: "25"), in: s),
                       "Rest's up. Plank, set 2 of 3, 25.")
        XCTAssertEqual(SpokenCue.restEnd(next: next("Plank", set: 2, of: 3, reps: 0, weight: nil), in: s),
                       "Rest's up. Plank, set 2 of 3.")
    }

    func testWarningLine() {
        XCTAssertEqual(SpokenCue.warning(next: next(), in: session([ex("Bench Press")])),
                       "10 seconds. Bench Press next.")
    }

    func testReadback() {
        let weighted = ex("Bench Press", weight: "185", reps: "5")
        XCTAssertEqual(SpokenCue.readback(exercise: weighted, setIdx: 2), "Bench Press, set 3, 185 for 5.")
        let bw = ex("Pull-up", unit: "bw", reps: "8")
        XCTAssertEqual(SpokenCue.readback(exercise: bw, setIdx: 1), "Pull-up, set 2, 8 reps.")
    }

    // MARK: - Player

    private func player(cues: Bool, level: VoiceSettings.CueLevel = .restEnd, voiceOver: Bool = false)
        -> (VoiceCuePlayer, FakeSpeechOutput) {
        let suite = "SpokenCueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        VoiceSettings(cuesOn: cues, level: level).save(to: defaults)
        let fake = FakeSpeechOutput()
        return (VoiceCuePlayer(output: { fake }, defaults: defaults, voiceOverRunning: { voiceOver }), fake)
    }

    private var sess: ActiveSession { session([ex("Bench Press")]) }
    private var logged: LoggedExercise { ex("Bench Press", weight: "185", reps: "5") }

    func testCuesOffSpeaksNothing() {
        let (p, fake) = player(cues: false, level: .full)
        XCTAssertFalse(p.restEnded(session: sess, next: next()))
        XCTAssertFalse(p.restWarning(session: sess, next: next()))
        XCTAssertFalse(p.readback(exercise: logged, setIdx: 0))
        XCTAssertTrue(fake.spoken.isEmpty)
    }

    func testVoiceOverSpeaksNothing() {
        let (p, fake) = player(cues: true, level: .full, voiceOver: true)
        XCTAssertFalse(p.restEnded(session: sess, next: next()))
        XCTAssertFalse(p.restWarning(session: sess, next: next()))
        XCTAssertFalse(p.readback(exercise: logged, setIdx: 0))
        XCTAssertTrue(fake.spoken.isEmpty)
    }

    func testRestEndLevelSpeaksOnlyRestEnd() {
        let (p, fake) = player(cues: true, level: .restEnd)
        XCTAssertTrue(p.restEnded(session: sess, next: next()))
        XCTAssertFalse(p.restWarning(session: sess, next: next()))
        XCTAssertFalse(p.readback(exercise: logged, setIdx: 0))
        XCTAssertEqual(fake.spoken, ["Rest's up. Bench Press, set 3 of 4, 185 for 5."])
    }

    func testFullLevelSpeaksAll() {
        let (p, fake) = player(cues: true, level: .full)
        XCTAssertTrue(p.restEnded(session: sess, next: next()))
        XCTAssertTrue(p.restWarning(session: sess, next: next()))
        XCTAssertTrue(p.readback(exercise: logged, setIdx: 0))
        XCTAssertEqual(fake.spoken.count, 3)
    }

    func testLockedRestEndLineFollowsTheCueGate() {
        XCTAssertNil(player(cues: false).0.lockedRestEndLine(session: sess, next: next()))
        XCTAssertNil(player(cues: true, voiceOver: true).0.lockedRestEndLine(session: sess, next: next()))
        XCTAssertNil(player(cues: true).0.lockedRestEndLine(session: sess, next: nil))
        XCTAssertEqual(player(cues: true).0.lockedRestEndLine(session: sess, next: next()),
                       "Rest's up. Bench Press, set 3 of 4, 185 for 5.")
    }

    func testRenderUsesTheOutputsFileRender() async throws {
        let (p, fake) = player(cues: true)
        let url = URL(fileURLWithPath: "/tmp/pt_speech_1.caf")
        fake.renderResult = .success(url)
        let got = try await p.render("Rest's up.")
        XCTAssertEqual(got, url)
        XCTAssertEqual(fake.rendered, ["Rest's up."])
    }

    func testNilNextSpeaksNothing() {
        let (p, fake) = player(cues: true, level: .full)
        XCTAssertFalse(p.restEnded(session: sess, next: nil))
        XCTAssertFalse(p.restWarning(session: sess, next: nil))
        XCTAssertTrue(fake.spoken.isEmpty)
    }

    // MARK: - Notification options

    func testPresentationOptions() {
        let rest = RestTimerState.expiryNotificationId
        XCTAssertEqual(NotificationDelegate.presentationOptions(identifier: rest, speaksRestEnd: true), [.banner])
        XCTAssertEqual(NotificationDelegate.presentationOptions(identifier: rest, speaksRestEnd: false), [.banner, .sound])
        XCTAssertEqual(NotificationDelegate.presentationOptions(identifier: "weekly", speaksRestEnd: true), [.banner, .sound])
    }
}
