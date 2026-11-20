import XCTest
@testable import PhaseTraining

/// Hands each turn a stream the test feeds by hand, so a reply can be held mid-sentence.
private final class ManualCoachStream: CoachTurnStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var _continuation: AsyncThrowingStream<CoachClient.StreamPart, Error>.Continuation?
    private var _userMessages: [String] = []

    var continuation: AsyncThrowingStream<CoachClient.StreamPart, Error>.Continuation? { lock.withLock { _continuation } }
    var userMessages: [String] { lock.withLock { _userMessages } }

    func stream(cachedSystem: String, perTurnContext: String, history: [CoachClient.Turn],
                userMessage: String, tools: [AnthropicTool]?) -> AsyncThrowingStream<CoachClient.StreamPart, Error> {
        let (stream, continuation) = AsyncThrowingStream<CoachClient.StreamPart, Error>.makeStream()
        lock.withLock {
            _continuation = continuation
            _userMessages.append(userMessage)
        }
        return stream
    }
}

@MainActor
private final class OneLineTranscriber: SpeechTranscribing {
    let supportsOnDevice = true
    let line: String
    init(_ line: String) { self.line = line }
    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {}
    func finish() async throws -> String? { line }
    func cancel() {}
}

@MainActor
private final class AllowAll: SpeechPermissionProviding {
    let microphone: SpeechAuthorization = .granted
    let speech: SpeechAuthorization = .granted
    func requestMicrophone() async -> SpeechAuthorization { .granted }
    func requestSpeech() async -> SpeechAuthorization { .granted }
}

@MainActor
final class VoiceCheckInTests: XCTestCase {

    // MARK: - Sentence chunking

    func test_chunker_speaksOnlyCompletedSentences_thenFlushesTheTail() {
        var chunker = SpokenSentenceChunker()
        XCTAssertEqual(chunker.feed("Nice work today. Your squat"), ["Nice work today."])
        XCTAssertEqual(chunker.feed("Nice work today. Your squat moved well! Next"), ["Your squat moved well!"])
        XCTAssertEqual(chunker.feed("Nice work today. Your squat moved well! Next"), [])
        XCTAssertEqual(chunker.flush("Nice work today. Your squat moved well! Next week we push"), ["Next week we push"])
        XCTAssertEqual(chunker.flush("Nice work today. Your squat moved well! Next week we push"), [])
    }

    func test_chunker_keepsDecimalsAndHoldsATerminatorAtTheEnd() {
        var chunker = SpokenSentenceChunker()
        XCTAssertEqual(chunker.feed("Add 2.5 kg."), [], "a final period may be mid-stream")
        XCTAssertEqual(chunker.feed("Add 2.5 kg. Then rest?"), ["Add 2.5 kg."])
        XCTAssertEqual(chunker.flush("Add 2.5 kg. Then rest?"), ["Then rest?"])
    }

    func test_chunker_splitsOnNewlines_andDropsMarkdownAndEmptyPieces() {
        var chunker = SpokenSentenceChunker()
        let text = "**Plan**\n- Squat 3x5\n\n⚠️ Ask again"
        XCTAssertEqual(chunker.flush(text), ["Plan", "Squat 3x5", "Ask again"])
    }

    // MARK: - Turn through the runner, spoken

    private func freshStore(_ suite: String = #function) -> CoachConversationStore {
        let name = "VoiceCheckInTests.\(suite)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return CoachConversationStore(defaults: d)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func test_spokenTurn_landsInTheThread_andIsSpokenSentenceBySentence() async {
        let conv = freshStore()
        let client = ManualCoachStream()
        let runner = CoachTurnRunner(conv: conv, client: client)
        let output = FakeSpeechOutput()
        let input = SpeechInput(transcriber: OneLineTranscriber("How did my week go"), permissions: AllowAll(),
                                audioOwner: VoiceAudioSessionOwner())
        let model = VoiceCheckInModel(conv: conv, runner: runner, output: output, context: { "ctx" }, input: input)

        await model.pressDown()
        await model.release()
        XCTAssertTrue(model.replying)
        XCTAssertEqual(conv.messages.first?.text, "How did my week go")
        XCTAssertEqual(conv.turnsToday, 1)
        await settle()

        client.continuation?.yield(.textDelta("Solid week. You hit"))
        await settle()
        XCTAssertEqual(output.spoken, ["Solid week."])

        client.continuation?.yield(.textDelta(" every lift. Rest tomorrow"))
        await settle()
        XCTAssertEqual(output.spoken, ["Solid week.", "You hit every lift."])

        client.continuation?.yield(.stopped(reason: "end_turn"))
        client.continuation?.finish()
        await runner.waitForCurrentTurn()
        await settle()
        XCTAssertEqual(output.spoken, ["Solid week.", "You hit every lift.", "Rest tomorrow"])
        XCTAssertEqual(conv.messages.last?.text, "Solid week. You hit every lift. Rest tomorrow")
        XCTAssertFalse(model.replying)
    }

    func test_stopSpeaking_silencesTheRestOfTheReply_butTheTextStillLands() async {
        let conv = freshStore()
        let client = ManualCoachStream()
        let runner = CoachTurnRunner(conv: conv, client: client)
        let output = FakeSpeechOutput()
        let model = VoiceCheckInModel(conv: conv, runner: runner, output: output, context: { "ctx" })

        model.send("Should I deload?")
        await settle()
        client.continuation?.yield(.textDelta("Not yet. Your bar speed"))
        await settle()
        XCTAssertEqual(output.spoken, ["Not yet."])

        model.stopSpeaking()
        XCTAssertEqual(output.stopCount, 1)
        client.continuation?.yield(.textDelta(" held up. Keep going."))
        client.continuation?.finish()
        await runner.waitForCurrentTurn()
        await settle()

        XCTAssertEqual(output.spoken, ["Not yet."])
        XCTAssertEqual(conv.messages.last?.text, "Not yet. Your bar speed held up. Keep going.")
        XCTAssertFalse(model.replying)
    }

    func test_nothingHeard_sendsNoTurn() async {
        let conv = freshStore()
        let client = ManualCoachStream()
        let runner = CoachTurnRunner(conv: conv, client: client)
        let input = SpeechInput(transcriber: OneLineTranscriber("   "), permissions: AllowAll(),
                                audioOwner: VoiceAudioSessionOwner())
        let model = VoiceCheckInModel(conv: conv, runner: runner, output: FakeSpeechOutput(), context: { "ctx" }, input: input)

        await model.pressDown()
        await model.release()
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertEqual(model.notice, "Didn't catch that")
        XCTAssertTrue(client.userMessages.isEmpty)
    }

    // MARK: - Gate

    func test_hiddenWithoutAGatewayToken() {
        XCTAssertFalse(VoiceCheckInModel.isOffered(consent: true, pro: true, requirePro: false, available: false))
        XCTAssertTrue(VoiceCheckInModel.isOffered(consent: true, pro: true, requirePro: false, available: true))
        XCTAssertFalse(VoiceCheckInModel.isOffered(consent: false, pro: true, requirePro: false, available: true))
    }
}
