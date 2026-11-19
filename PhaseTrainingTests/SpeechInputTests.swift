import XCTest
@testable import PhaseTraining

@MainActor
private final class FakeTranscriber: SpeechTranscribing {
    var supportsOnDevice = true
    var partials: [String] = []
    var finalResult: Result<String?, Error> = .success(nil)
    var startError: Error?

    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private(set) var lastContextualStrings: [String] = []
    private var onPartial: ((String) -> Void)?

    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {
        if let startError { throw startError }
        startCount += 1
        lastContextualStrings = contextualStrings
        self.onPartial = onPartial
        for partial in partials { onPartial(partial) }
    }

    func emit(_ partial: String) { onPartial?(partial) }

    func finish() async throws -> String? {
        finishCount += 1
        return try finalResult.get()
    }

    func cancel() { cancelCount += 1 }
}

@MainActor
private final class FakePermissions: SpeechPermissionProviding {
    var microphone: SpeechAuthorization
    var speech: SpeechAuthorization
    var microphoneAnswer: SpeechAuthorization = .granted
    var speechAnswer: SpeechAuthorization = .granted
    private(set) var requests: [String] = []

    init(microphone: SpeechAuthorization = .granted, speech: SpeechAuthorization = .granted) {
        self.microphone = microphone
        self.speech = speech
    }

    func requestMicrophone() async -> SpeechAuthorization {
        requests.append("microphone")
        microphone = microphoneAnswer
        return microphoneAnswer
    }

    func requestSpeech() async -> SpeechAuthorization {
        requests.append("speech")
        speech = speechAnswer
        return speechAnswer
    }
}

private struct ScriptedError: Error {}

@MainActor
final class SpeechInputTests: XCTestCase {

    private var transcriber: FakeTranscriber!
    private var permissions: FakePermissions!

    override func setUp() async throws {
        transcriber = FakeTranscriber()
        permissions = FakePermissions()
    }

    private func makeInput() -> SpeechInput {
        SpeechInput(transcriber: transcriber, permissions: permissions)
    }

    private func listeningInput() async -> SpeechInput {
        let input = makeInput()
        await input.pressDown(exerciseNames: ["Back Squat"])
        XCTAssertEqual(input.state, .listening(partial: ""))
        return input
    }

    // MARK: - Availability

    func testAllGrantedIsIdle() {
        XCTAssertEqual(makeInput().state, .idle)
    }

    func testMicrophoneDenied() {
        permissions.microphone = .denied
        XCTAssertEqual(makeInput().state, .unavailable(.microphoneDenied))
    }

    func testSpeechDenied() {
        permissions.speech = .denied
        XCTAssertEqual(makeInput().state, .unavailable(.speechDenied))
    }

    func testRestrictedFromEitherPermission() {
        permissions.microphone = .restricted
        XCTAssertEqual(makeInput().state, .unavailable(.restricted))
        permissions.microphone = .granted
        permissions.speech = .restricted
        XCTAssertEqual(makeInput().state, .unavailable(.restricted))
    }

    func testOnDeviceUnsupported() {
        transcriber.supportsOnDevice = false
        XCTAssertEqual(makeInput().state, .unavailable(.onDeviceUnsupported))
    }

    func testPrecedenceRestrictedThenMicThenSpeechThenOnDevice() {
        typealias U = SpeechInput
        XCTAssertEqual(U.unavailability(microphone: .denied, speech: .restricted, supportsOnDevice: false), .restricted)
        XCTAssertEqual(U.unavailability(microphone: .restricted, speech: .denied, supportsOnDevice: false), .restricted)
        XCTAssertEqual(U.unavailability(microphone: .denied, speech: .denied, supportsOnDevice: false), .microphoneDenied)
        XCTAssertEqual(U.unavailability(microphone: .granted, speech: .denied, supportsOnDevice: false), .speechDenied)
        XCTAssertEqual(U.unavailability(microphone: .granted, speech: .granted, supportsOnDevice: false), .onDeviceUnsupported)
        XCTAssertNil(U.unavailability(microphone: .granted, speech: .granted, supportsOnDevice: true))
    }

    func testBothDeniedReportsMicrophone() {
        permissions.microphone = .denied
        permissions.speech = .denied
        XCTAssertEqual(makeInput().state, .unavailable(.microphoneDenied))
    }

    func testNotDeterminedIsNotUnavailable() {
        permissions.microphone = .notDetermined
        permissions.speech = .notDetermined
        XCTAssertEqual(makeInput().state, .idle)
        XCTAssertTrue(permissions.requests.isEmpty, "refreshAvailability must not prompt")
    }

    func testMessages() {
        XCTAssertEqual(SpeechInputUnavailable.microphoneDenied.message,
                       "Microphone access is off. Turn it on in Settings > Phase Training.")
        XCTAssertEqual(SpeechInputUnavailable.speechDenied.message,
                       "Speech recognition is off. Turn it on in Settings > Phase Training.")
        XCTAssertEqual(SpeechInputUnavailable.restricted.message,
                       "Speech recognition is restricted on this device.")
        XCTAssertEqual(SpeechInputUnavailable.onDeviceUnsupported.message,
                       "This device can't recognize speech offline, so voice logging is off.")
    }

    func testRefreshPicksUpAChangedPermission() {
        permissions.microphone = .denied
        let input = makeInput()
        XCTAssertEqual(input.state, .unavailable(.microphoneDenied))
        permissions.microphone = .granted
        input.refreshAvailability()
        XCTAssertEqual(input.state, .idle)
    }

    func testRefreshLeavesListeningAlone() async {
        let input = await listeningInput()
        permissions.microphone = .denied
        input.refreshAvailability()
        XCTAssertEqual(input.state, .listening(partial: ""))
    }

    // MARK: - Prompts

    func testPromptsMicThenSpeechAndListens() async {
        permissions.microphone = .notDetermined
        permissions.speech = .notDetermined
        let input = makeInput()
        await input.pressDown(exerciseNames: [])
        XCTAssertEqual(permissions.requests, ["microphone", "speech"])
        XCTAssertEqual(input.state, .listening(partial: ""))
        XCTAssertEqual(transcriber.startCount, 1)
    }

    func testMicPromptDeniedNeverStartsOrAsksSpeech() async {
        permissions.microphone = .notDetermined
        permissions.speech = .notDetermined
        permissions.microphoneAnswer = .denied
        let input = makeInput()
        await input.pressDown(exerciseNames: [])
        XCTAssertEqual(permissions.requests, ["microphone"])
        XCTAssertEqual(input.state, .unavailable(.microphoneDenied))
        XCTAssertEqual(transcriber.startCount, 0)
    }

    func testSpeechPromptDeniedNeverStarts() async {
        permissions.speech = .notDetermined
        permissions.speechAnswer = .denied
        let input = makeInput()
        await input.pressDown(exerciseNames: [])
        XCTAssertEqual(permissions.requests, ["speech"])
        XCTAssertEqual(input.state, .unavailable(.speechDenied))
        XCTAssertEqual(transcriber.startCount, 0)
    }

    func testSpeechPromptRestrictedNeverStarts() async {
        permissions.speech = .notDetermined
        permissions.speechAnswer = .restricted
        let input = makeInput()
        await input.pressDown(exerciseNames: [])
        XCTAssertEqual(input.state, .unavailable(.restricted))
        XCTAssertEqual(transcriber.startCount, 0)
    }

    func testPressDownWhileUnavailableDoesNotPromptOrStart() async {
        permissions.microphone = .denied
        permissions.speech = .notDetermined
        let input = makeInput()
        await input.pressDown(exerciseNames: [])
        XCTAssertTrue(permissions.requests.isEmpty)
        XCTAssertEqual(transcriber.startCount, 0)
        XCTAssertEqual(input.state, .unavailable(.microphoneDenied))
    }

    func testStartErrorReturnsToIdle() async {
        transcriber.startError = ScriptedError()
        let input = makeInput()
        await input.pressDown(exerciseNames: [])
        XCTAssertEqual(input.state, .idle)
        let text = await input.release()
        XCTAssertNil(text)
        XCTAssertEqual(transcriber.finishCount, 0)
    }

    // MARK: - Listening and final result

    func testPartialsUpdateState() async {
        let input = await listeningInput()
        transcriber.emit("185 for")
        XCTAssertEqual(input.state, .listening(partial: "185 for"))
    }

    func testPassesContextualStringsToTranscriber() async {
        _ = await listeningInput()
        XCTAssertEqual(transcriber.lastContextualStrings,
                       SpeechInput.contextualStrings(exerciseNames: ["Back Squat"]))
    }

    func testFinalReturnedTrimmed() async {
        transcriber.finalResult = .success("  185 for 5 \n")
        let input = await listeningInput()
        let text = await input.release()
        XCTAssertEqual(text, "185 for 5")
        XCTAssertEqual(input.state, .idle)
        XCTAssertEqual(transcriber.finishCount, 1)
    }

    func testEmptyFinalIsNil() async {
        transcriber.finalResult = .success("")
        let input = await listeningInput()
        let text = await input.release()
        XCTAssertNil(text)
    }

    func testWhitespaceFinalIsNil() async {
        transcriber.finalResult = .success("   \n ")
        let input = await listeningInput()
        let text = await input.release()
        XCTAssertNil(text)
        XCTAssertEqual(input.state, .idle)
    }

    func testNilFinalFallsBackToLastPartial() async {
        let input = await listeningInput()
        transcriber.emit("skip")
        transcriber.emit(" skip rest ")
        transcriber.finalResult = .success(nil)
        let text = await input.release()
        XCTAssertEqual(text, "skip rest")
    }

    func testNilFinalWithNoPartialIsNil() async {
        let input = await listeningInput()
        transcriber.finalResult = .success(nil)
        let text = await input.release()
        XCTAssertNil(text)
    }

    func testThrownFinalIsNilAndIdle() async {
        let input = await listeningInput()
        transcriber.emit("185 for 5")
        transcriber.finalResult = .failure(ScriptedError())
        let text = await input.release()
        XCTAssertNil(text)
        XCTAssertEqual(input.state, .idle)
    }

    func testReleaseWhileIdleSkipsFinish() async {
        let input = makeInput()
        let text = await input.release()
        XCTAssertNil(text)
        XCTAssertEqual(transcriber.finishCount, 0)
    }

    func testReleaseWhileUnavailableSkipsFinish() async {
        permissions.speech = .denied
        let input = makeInput()
        let text = await input.release()
        XCTAssertNil(text)
        XCTAssertEqual(transcriber.finishCount, 0)
    }

    func testDoublePressDownStartsOnce() async {
        let input = await listeningInput()
        transcriber.emit("185")
        await input.pressDown(exerciseNames: ["Bench Press"])
        XCTAssertEqual(transcriber.startCount, 1)
        XCTAssertEqual(input.state, .listening(partial: "185"))
    }

    func testPartialFromAPreviousUtteranceDoesNotLeak() async {
        let input = await listeningInput()
        transcriber.emit("185 for 5")
        transcriber.finalResult = .success("185 for 5")
        _ = await input.release()
        await input.pressDown(exerciseNames: [])
        transcriber.finalResult = .success(nil)
        let text = await input.release()
        XCTAssertNil(text)
    }

    func testCancelDropsUtterance() async {
        let input = await listeningInput()
        transcriber.emit("185")
        input.cancel()
        XCTAssertEqual(transcriber.cancelCount, 1)
        XCTAssertEqual(input.state, .idle)
        let text = await input.release()
        XCTAssertNil(text)
        XCTAssertEqual(transcriber.finishCount, 0)
    }

    func testCancelWhileIdleDoesNotTouchTranscriber() {
        let input = makeInput()
        input.cancel()
        XCTAssertEqual(transcriber.cancelCount, 0)
        XCTAssertEqual(input.state, .idle)
    }

    // MARK: - micEnabled

    func testMicEnabledPerState() async {
        let input = makeInput()
        XCTAssertEqual(input.state, .idle)
        XCTAssertTrue(input.micEnabled)

        await input.pressDown(exerciseNames: [])
        XCTAssertEqual(input.state, .listening(partial: ""))
        XCTAssertTrue(input.micEnabled)
        input.cancel()

        permissions.microphone = .denied
        input.refreshAvailability()
        XCTAssertEqual(input.state, .unavailable(.microphoneDenied))
        XCTAssertFalse(input.micEnabled)

        for reason: SpeechInputUnavailable in [.speechDenied, .restricted, .onDeviceUnsupported] {
            permissions.microphone = .granted
            permissions.speech = reason == .speechDenied ? .denied : (reason == .restricted ? .restricted : .granted)
            transcriber.supportsOnDevice = reason != .onDeviceUnsupported
            input.refreshAvailability()
            XCTAssertEqual(input.state, .unavailable(reason))
            XCTAssertFalse(input.micEnabled)
        }
    }

    func testMicEnabledWhileFinishing() async {
        let gate = GatedTranscriber()
        let input = SpeechInput(transcriber: gate, permissions: permissions)
        await input.pressDown(exerciseNames: [])
        let release = Task { await input.release() }
        while input.state != .finishing { await Task.yield() }
        XCTAssertTrue(input.micEnabled)
        gate.open("done")
        let text = await release.value
        XCTAssertEqual(text, "done")
        XCTAssertEqual(input.state, .idle)
    }

    // MARK: - Contextual strings

    func testContextualStringsOrderNamesThenCommands() {
        let strings = SpeechInput.contextualStrings(exerciseNames: ["Back Squat", "Bench Press"])
        XCTAssertEqual(Array(strings.prefix(2)), ["Back Squat", "Bench Press"])
        XCTAssertEqual(Array(strings.dropFirst(2)), [
            "same again", "done", "skip rest", "undo", "what's next", "how many left",
            "RPE", "kilos", "pounds", "for", "by",
        ])
    }

    func testContextualStringsDedupeKeepsFirstCasing() {
        let strings = SpeechInput.contextualStrings(exerciseNames: ["Back Squat", "back squat", "Pull-Up", "Back Squat"])
        XCTAssertEqual(strings.filter { $0.lowercased() == "back squat" }, ["Back Squat"])
        XCTAssertEqual(strings.filter { $0 == "Pull-Up" }.count, 1)
        XCTAssertEqual(Set(strings.map { $0.lowercased() }).count, strings.count)
    }

    func testContextualStringsDropEmpties() {
        let strings = SpeechInput.contextualStrings(exerciseNames: ["", "   ", "Deadlift"])
        XCTAssertEqual(strings.first, "Deadlift")
        XCTAssertFalse(strings.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    func testContextualStringsCapAt100() {
        let names = (1...150).map { "Exercise \($0)" }
        let strings = SpeechInput.contextualStrings(exerciseNames: names)
        XCTAssertEqual(strings.count, 100)
        XCTAssertEqual(strings, Array(names.prefix(100)))

        let some = (1...95).map { "Exercise \($0)" }
        let mixed = SpeechInput.contextualStrings(exerciseNames: some)
        XCTAssertEqual(mixed.count, 100)
        XCTAssertEqual(Array(mixed.suffix(5)), ["same again", "done", "skip rest", "undo", "what's next"])
    }

    func testContextualStringsNoNamesIsCommandsOnly() {
        XCTAssertEqual(SpeechInput.contextualStrings(exerciseNames: []), SpeechInput.commandWords)
    }
}

/// Holds `finish` open until the test releases it, to observe `.finishing`.
@MainActor
private final class GatedTranscriber: SpeechTranscribing {
    var supportsOnDevice = true
    private var waiter: CheckedContinuation<String?, Never>?
    private var pending: String??

    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {}

    func finish() async -> String? {
        if let pending { return pending }
        return await withCheckedContinuation { waiter = $0 }
    }

    func open(_ text: String?) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: text)
        } else {
            pending = .some(text)
        }
    }

    func cancel() {}
}
