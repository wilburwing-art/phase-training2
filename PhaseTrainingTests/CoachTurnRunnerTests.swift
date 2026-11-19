import XCTest
@testable import PhaseTraining

/// Fake stream: records what each turn sent and replays scripted parts.
private final class FakeCoachStream: CoachTurnStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var _userMessages: [String] = []
    private var _histories: [[CoachClient.Turn]] = []
    let parts: [CoachClient.StreamPart]
    let error: Error?

    init(parts: [CoachClient.StreamPart], error: Error? = nil) {
        self.parts = parts
        self.error = error
    }

    var userMessages: [String] { lock.withLock { _userMessages } }
    var histories: [[CoachClient.Turn]] { lock.withLock { _histories } }

    func stream(
        cachedSystem: String,
        perTurnContext: String,
        history: [CoachClient.Turn],
        userMessage: String,
        tools: [AnthropicTool]?
    ) -> AsyncThrowingStream<CoachClient.StreamPart, Error> {
        lock.withLock {
            _userMessages.append(userMessage)
            _histories.append(history)
        }
        let parts = self.parts
        let error = self.error
        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

@MainActor
final class CoachTurnRunnerTests: XCTestCase {

    private func freshStore(_ suite: String = #function) -> CoachConversationStore {
        let name = "CoachTurnRunnerTests.\(suite)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return CoachConversationStore(defaults: d)
    }

    func test_turn_appendsUserAndStreamedReply_andCountsTurn() async {
        let conv = freshStore()
        let fake = FakeCoachStream(parts: [.textDelta("Rest "), .textDelta("today."), .stopped(reason: "end_turn")])
        let runner = CoachTurnRunner(conv: conv, client: fake)

        XCTAssertTrue(runner.send("  Should I lift?  ", context: "ctx"))
        XCTAssertTrue(runner.sending)
        await runner.waitForCurrentTurn()

        XCTAssertFalse(runner.sending)
        XCTAssertNil(runner.streamingId)
        XCTAssertEqual(conv.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(conv.messages[0].text, "Should I lift?")
        XCTAssertEqual(conv.messages[1].text, "Rest today.")
        XCTAssertEqual(conv.turnsToday, 1)
        XCTAssertEqual(fake.userMessages, ["Should I lift?"])
        XCTAssertTrue(fake.histories[0].isEmpty, "The new user message is the wire message, not history")
    }

    func test_statusPrefix_goesToWireOnly() async {
        let conv = freshStore()
        var proposal = CoachProposal(ops: [], reasoning: "test")
        proposal.status = .applied
        var prior = CoachMessage(role: "assistant", text: "Moved Thursday.")
        prior.proposal = proposal
        conv.append(CoachMessage(role: "user", text: "Move Thursday"))
        conv.append(prior)

        let fake = FakeCoachStream(parts: [.textDelta("ok")])
        let runner = CoachTurnRunner(conv: conv, client: fake)
        runner.send("Thanks", context: "ctx")
        await runner.waitForCurrentTurn()

        let wire = try? XCTUnwrap(fake.userMessages.first)
        XCTAssertTrue(wire?.hasPrefix("[STATUS NOTE") == true)
        XCTAssertTrue(wire?.contains("plan-edit proposal was APPLIED") == true)
        XCTAssertTrue(wire?.hasSuffix("Thanks") == true)
        XCTAssertEqual(conv.messages[2].text, "Thanks", "The bubble shows what the user said")
        XCTAssertEqual(fake.histories[0].count, 2)
    }

    func test_noPrefix_whenPriorProposalPending() {
        var prior = CoachMessage(role: "assistant", text: "Staged.")
        prior.proposal = CoachProposal(ops: [], reasoning: "test")
        XCTAssertEqual(CoachTurnRunner.statusPrefix(for: prior), "")
        XCTAssertEqual(CoachTurnRunner.statusPrefix(for: nil), "")
    }

    func test_blankText_andHardCap_startNoTurn() {
        let conv = freshStore()
        let fake = FakeCoachStream(parts: [])
        let runner = CoachTurnRunner(conv: conv, client: fake)
        XCTAssertFalse(runner.send("   ", context: "ctx"))
        for _ in 0..<CoachConfig.hardTurnCap { conv.recordTurn() }
        XCTAssertFalse(runner.send("hello", context: "ctx"))
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertEqual(conv.turnsToday, CoachConfig.hardTurnCap)
        XCTAssertTrue(fake.userMessages.isEmpty)
    }

    func test_memoryToolCall_setsPendingProposal() async {
        let conv = freshStore()
        let json = #"{"ops":[{"op":"add_dislike","value":"burpees"}],"reasoning":"said so"}"#
        let fake = FakeCoachStream(parts: [
            .textDelta("Noted."),
            .toolCall(id: "t1", name: "propose_memory_update", input: Data(json.utf8)),
        ])
        let runner = CoachTurnRunner(conv: conv, client: fake)
        runner.send("I hate burpees", context: "ctx")
        await runner.waitForCurrentTurn()

        let reply = conv.messages[1]
        XCTAssertEqual(reply.memoryProposal?.ops.first?.value, "burpees")
        XCTAssertEqual(reply.memoryProposal?.status, .pending)
        XCTAssertTrue(conv.hasPendingProposal)
    }

    func test_undecodableToolCall_andTruncation_appendNotes() async {
        let conv = freshStore()
        let fake = FakeCoachStream(parts: [
            .textDelta("Moving it"),
            .toolCall(id: "t1", name: "propose_plan_edits", input: Data("{".utf8)),
            .stopped(reason: "max_tokens"),
        ])
        let runner = CoachTurnRunner(conv: conv, client: fake)
        runner.send("Move Friday", context: "ctx")
        await runner.waitForCurrentTurn()

        XCTAssertEqual(
            conv.messages[1].text,
            "Moving it" + CoachTurnRunner.undeliveredProposalNote + CoachTurnRunner.truncatedReplyNote
        )
        XCTAssertNil(conv.messages[1].proposal)
    }

    func test_error_appendsUserFacingMessage() async {
        let conv = freshStore()
        let fake = FakeCoachStream(parts: [.textDelta("Partial")], error: CoachClient.CoachError.missingGatewayToken)
        let runner = CoachTurnRunner(conv: conv, client: fake)
        runner.send("hi", context: "ctx")
        await runner.waitForCurrentTurn()

        XCTAssertEqual(conv.messages[1].text, "Partial\n\n⚠️ The coach isn't available in this build.")
        XCTAssertFalse(runner.sending)
    }
}
