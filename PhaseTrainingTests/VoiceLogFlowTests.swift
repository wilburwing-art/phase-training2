import XCTest
import UIKit
@testable import PhaseTraining

@MainActor
private final class FakeTranscriber: SpeechTranscribing {
    var supportsOnDevice = true
    var finalResult: Result<String?, Error> = .success(nil)

    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {}
    func finish() async throws -> String? { try finalResult.get() }
    func cancel() {}
}

@MainActor
private final class FakePermissions: SpeechPermissionProviding {
    var microphone: SpeechAuthorization = .granted
    var speech: SpeechAuthorization = .granted
    func requestMicrophone() async -> SpeechAuthorization { microphone }
    func requestSpeech() async -> SpeechAuthorization { speech }
}

@MainActor
final class VoiceLogFlowTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var readbacks: [(String, Int)] = []
    private var transcriber: FakeTranscriber!
    private var permissions: FakePermissions!

    override func setUp() {
        super.setUp()
        transcriber = FakeTranscriber()
        permissions = FakePermissions()
        readbacks = []
    }

    // MARK: - Fixtures

    private func defaults() -> UserDefaults {
        let suite = "VoiceLogFlowTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func exercise(_ name: String, sets: Int, unit: String = "lbs",
                          group: Int? = nil, weight: String = "") -> LoggedExercise {
        LoggedExercise(id: "ex-\(name)", name: name, type: nil, unit: unit,
                       targetSets: sets, targetReps: 8, rest: 90,
                       sets: (0..<sets).map {
                           LoggedSet(num: $0 + 1, weight: weight, reps: "", rpe: "", done: false)
                       },
                       prevSets: [], supersetGroup: group)
    }

    private func make(_ exercises: [LoggedExercise]) -> (VoiceLogModel, ActiveWorkoutController) {
        let store = SessionStore(defaults: defaults())
        let session = ActiveSession(templateId: "t", name: "Test", category: "Custom",
                                    startTime: Date(), exercises: exercises,
                                    feel: nil, note: nil)
        store.saveActive(session)
        let workout = ActiveWorkoutController(store: store, session: session,
                                              haptic: { _ in },
                                              now: { [unowned self] in clock })
        let input = SpeechInput(transcriber: transcriber, permissions: permissions)
        let model = VoiceLogModel(workout: workout, input: input,
                                  readback: { [unowned self] in readbacks.append(($0.name, $1)) },
                                  now: { [unowned self] in clock })
        return (model, workout)
    }

    // MARK: - Logging

    func test_185For5LogsNextUpSetAndReadsBackOnce() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("185 for 5")
        let set = workout.session.exercises[0].sets[0]
        XCTAssertEqual(set.weight, "185")
        XCTAssertEqual(set.reps, "5")
        XCTAssertTrue(set.done)
        XCTAssertEqual(readbacks.count, 1)
        XCTAssertEqual(readbacks.first?.0, "Bench")
        XCTAssertEqual(readbacks.first?.1, 0)
        XCTAssertEqual(model.card?.kind, .applied)
        XCTAssertEqual(model.card?.message, "Bench, set 1: 185 × 5")
        XCTAssertEqual(model.card?.target, SetTarget(exIdx: 0, setIdx: 0))
        XCTAssertEqual(model.card?.undoable, true)
    }

    func test_sameAgainCopiesPreviousDoneSet() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("185 for 5")
        model.handle("same again")
        let set = workout.session.exercises[0].sets[1]
        XCTAssertEqual(set.weight, "185")
        XCTAssertEqual(set.reps, "5")
        XCTAssertTrue(set.done)
        XCTAssertEqual(model.card?.kind, .applied)
    }

    func test_sameAgainWithNoDoneSetIsInfoAndChangesNothing() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        let before = workout.session
        model.handle("same again")
        XCTAssertEqual(workout.session, before)
        XCTAssertEqual(model.card?.kind, .info)
        XCTAssertEqual(model.card?.message, "Nothing to repeat yet")
        XCTAssertTrue(readbacks.isEmpty)
    }

    func test_unparsedShowsDidntCatchAndLeavesSession() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        let before = workout.session
        model.handle("pizza")
        XCTAssertEqual(workout.session, before)
        XCTAssertEqual(model.card?.kind, .unparsed)
        XCTAssertEqual(model.card?.message, "Didn't catch that")
        XCTAssertEqual(model.card?.heard, "pizza")
    }

    func test_nilTranscriptShowsDidntCatch() {
        let (model, _) = make([exercise("Bench", sets: 3)])
        model.handle(nil)
        XCTAssertEqual(model.card?.kind, .unparsed)
        XCTAssertEqual(model.card?.message, "Didn't catch that")
        XCTAssertEqual(model.card?.heard, "")
    }

    func test_kgSpokenOnLbExerciseChangesNothing() {
        let (model, workout) = make([exercise("Bench", sets: 3, unit: "lbs")])
        let before = workout.session
        model.handle("100 kilos for 5")
        XCTAssertEqual(workout.session, before)
        XCTAssertEqual(model.card?.kind, .unparsed)
        XCTAssertEqual(model.card?.message, "Heard kg. Bench logs in lb")
        XCTAssertTrue(readbacks.isEmpty)
    }

    func test_lbSpokenOnKgExerciseChangesNothing() {
        let (model, workout) = make([exercise("Bench", sets: 3, unit: "kg")])
        let before = workout.session
        model.handle("100 pounds for 5")
        XCTAssertEqual(workout.session, before)
        XCTAssertEqual(model.card?.message, "Heard lb. Bench logs in kg")
    }

    func test_supersetLandsOnMemberNextUpNames() {
        let (model, workout) = make([
            exercise("Bench", sets: 2, group: 1),
            exercise("Row", sets: 2, group: 1),
        ])
        model.handle("100 for 8")
        XCTAssertTrue(workout.session.exercises[0].sets[0].done)
        model.handle("100 for 8")
        XCTAssertTrue(workout.session.exercises[1].sets[0].done)
        XCTAssertEqual(model.card?.target, SetTarget(exIdx: 1, setIdx: 0))
        XCTAssertFalse(workout.session.exercises[0].sets[1].done)
    }

    func test_allLoggedIsInfo() {
        let (model, _) = make([exercise("Bench", sets: 1)])
        model.handle("100 for 8")
        model.handle("100 for 8")
        XCTAssertEqual(model.card?.kind, .info)
        XCTAssertEqual(model.card?.message, "All sets are logged")
    }

    // MARK: - Rest

    func test_skipRestWithRunningRestClearsIt() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("185 for 5")
        XCTAssertNotNil(workout.rest.startedAt)
        model.handle("skip rest")
        XCTAssertNil(workout.rest.startedAt)
        XCTAssertEqual(model.card?.message, "Rest skipped")
    }

    func test_skipRestWithoutRestSaysSo() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("skip rest")
        XCTAssertNil(workout.rest.startedAt)
        XCTAssertEqual(model.card?.kind, .info)
        XCTAssertEqual(model.card?.message, "No rest running")
    }

    func test_addRestExtendsRunningRest() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("185 for 5")
        model.handle("add 15 seconds")
        XCTAssertEqual(workout.rest.duration, 105)
        XCTAssertEqual(model.card?.message, "+15 s rest")
    }

    // MARK: - Undo

    func test_undoButtonRestoresSetAndClearsRestItStarted() {
        let (model, workout) = make([exercise("Bench", sets: 3, weight: "135")])
        let before = workout.session
        model.handle("185 for 5")
        XCTAssertNotNil(workout.rest.startedAt)
        model.undo()
        XCTAssertEqual(workout.session, before)
        XCTAssertNil(workout.rest.startedAt)
        XCTAssertEqual(model.card?.message, "Undid Bench, set 1")
    }

    func test_undoAfterManualEditDoesNothing() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("185 for 5")
        workout.session.exercises[0].sets[0].weight = "190"
        let edited = workout.session
        model.undo()
        XCTAssertEqual(workout.session, edited)
        XCTAssertEqual(model.card?.message, "Nothing to undo")
    }

    func test_spokenUndoRevertsLastVoiceChange() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        let before = workout.session
        model.handle("185 for 5")
        model.handle("undo")
        XCTAssertEqual(workout.session, before)
        XCTAssertEqual(model.card?.kind, .info)
        XCTAssertEqual(model.card?.undoable, false)
    }

    func test_undoWithNothingRecordedSaysSo() {
        let (model, _) = make([exercise("Bench", sets: 3)])
        model.handle("undo")
        XCTAssertEqual(model.card?.message, "Nothing to undo")
    }

    func test_undoIsOneLevel() {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        model.handle("185 for 5")
        model.undo()
        let after = workout.session
        model.undo()
        XCTAssertEqual(workout.session, after)
        XCTAssertEqual(model.card?.message, "Nothing to undo")
    }

    // MARK: - Card

    func test_cardExpiry() throws {
        let (model, _) = make([exercise("Bench", sets: 3)])
        model.handle("pizza")
        let shown = try XCTUnwrap(model.card).shownAt
        XCTAssertTrue(model.cardIsLive(at: shown.addingTimeInterval(4.9)))
        XCTAssertFalse(model.cardIsLive(at: shown.addingTimeInterval(5.1)))
    }

    func test_newCardReplacesOld() {
        let (model, _) = make([exercise("Bench", sets: 3)])
        model.handle("pizza")
        model.handle("how many left")
        XCTAssertEqual(model.card?.message, "3 sets left")
    }

    func test_whatsNextUsesUpNextLine() {
        let (model, _) = make([exercise("Bench", sets: 4, weight: "185")])
        model.handle("what's next")
        XCTAssertEqual(model.card?.message, "Bench, set 1 of 4, 185 for 8")
    }

    // MARK: - Mic

    func test_pressDownThenReleaseAppliesTranscript() async {
        let (model, workout) = make([exercise("Bench", sets: 3)])
        transcriber.finalResult = .success("185 for 5")
        await model.pressDown()
        if case .listening = model.inputState {} else { XCTFail("expected listening") }
        await model.release()
        XCTAssertTrue(workout.session.exercises[0].sets[0].done)
        XCTAssertEqual(workout.session.exercises[0].sets[0].weight, "185")
    }

    func test_releaseWithNothingHeardShowsDidntCatch() async {
        let (model, _) = make([exercise("Bench", sets: 3)])
        transcriber.finalResult = .success(nil)
        await model.pressDown()
        await model.release()
        XCTAssertEqual(model.card?.message, "Didn't catch that")
    }

    func test_unavailableMicShowsInfoCard() async {
        permissions.microphone = .denied
        let (model, _) = make([exercise("Bench", sets: 3)])
        await model.pressDown()
        XCTAssertEqual(model.card?.kind, .info)
        XCTAssertEqual(model.card?.message, SpeechInputUnavailable.microphoneDenied.message)
        await model.release()
        XCTAssertEqual(model.card?.kind, .info)
    }
}
