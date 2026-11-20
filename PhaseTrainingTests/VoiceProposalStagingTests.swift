import XCTest
@testable import PhaseTraining

/// Plays a fixed list of stream parts for each turn.
private final class ScriptedCoachStream: CoachTurnStreaming, @unchecked Sendable {
    let parts: [CoachClient.StreamPart]
    init(_ parts: [CoachClient.StreamPart]) { self.parts = parts }

    func stream(cachedSystem: String, perTurnContext: String, history: [CoachClient.Turn],
                userMessage: String, tools: [AnthropicTool]?) -> AsyncThrowingStream<CoachClient.StreamPart, Error> {
        let parts = self.parts
        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }
}

/// Voice 3.3: a proposal made during a voice turn stays pending, the coach
/// says it is staged, and the Complete screen's list picks it up.
@MainActor
final class VoiceProposalStagingTests: XCTestCase {

    private static let planEditJSON = #"{"edits":[{"op":"move","fromDate":"2026-11-20","toDate":"2026-11-21"}],"reasoning":"knee"}"#

    private func freshStore(_ suite: String = #function) -> CoachConversationStore {
        let name = "VoiceProposalStagingTests.\(suite)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return CoachConversationStore(defaults: d)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func runVoiceTurn(_ parts: [CoachClient.StreamPart], conv: CoachConversationStore,
                              output: FakeSpeechOutput) async -> VoiceCheckInModel {
        let runner = CoachTurnRunner(conv: conv, client: ScriptedCoachStream(parts))
        let model = VoiceCheckInModel(conv: conv, runner: runner, output: output, context: { "ctx" })
        model.send("Move tomorrow's session, my knee is sore")
        await runner.waitForCurrentTurn()
        await settle()
        return model
    }

    func test_planProposalFromVoice_staysPending_andCoachSaysItIsStaged() async {
        let conv = freshStore()
        let output = FakeSpeechOutput()
        let model = await runVoiceTurn([
            .textDelta("Let's move it to Saturday."),
            .toolCall(id: "t1", name: "propose_plan_edits", input: Data(Self.planEditJSON.utf8)),
            .stopped(reason: "tool_use"),
        ], conv: conv, output: output)

        let reply = conv.messages[1]
        XCTAssertEqual(reply.proposal?.status, .pending, "voice never applies a change")
        XCTAssertEqual(reply.proposal?.ops.first?.op, "move")
        XCTAssertEqual(output.spoken, ["Let's move it to Saturday.", VoiceCheckInModel.stagedLine])
        XCTAssertEqual(model.notice, VoiceCheckInModel.stagedLine)
        XCTAssertEqual(conv.pendingProposalMessages.map(\.id), [reply.id])
    }

    func test_workoutAndMemoryProposalsFromVoice_alsoStage() async {
        let conv = freshStore()
        let output = FakeSpeechOutput()
        let memoryJSON = #"{"ops":[{"op":"add_dislike","value":"burpees"}]}"#
        _ = await runVoiceTurn([
            .textDelta("Noted."),
            .toolCall(id: "t1", name: "propose_memory_update", input: Data(memoryJSON.utf8)),
        ], conv: conv, output: output)

        XCTAssertEqual(conv.messages[1].memoryProposal?.status, .pending)
        XCTAssertEqual(output.spoken.last, VoiceCheckInModel.stagedLine)
        XCTAssertEqual(conv.pendingProposalMessages.count, 1)
    }

    func test_replyWithoutProposal_saysNothingAboutStaging() async {
        let conv = freshStore()
        let output = FakeSpeechOutput()
        let model = await runVoiceTurn([.textDelta("Rest it today.")], conv: conv, output: output)

        XCTAssertEqual(output.spoken, ["Rest it today."])
        XCTAssertNil(model.notice)
        XCTAssertTrue(conv.pendingProposalMessages.isEmpty)
    }

    func test_stoppedSpeaking_stillShowsTheStagedNotice_withoutSpeakingIt() async {
        let conv = freshStore()
        let output = FakeSpeechOutput()
        let runner = CoachTurnRunner(conv: conv, client: ScriptedCoachStream([
            .textDelta("Moving it."),
            .toolCall(id: "t1", name: "propose_plan_edits", input: Data(Self.planEditJSON.utf8)),
        ]))
        let model = VoiceCheckInModel(conv: conv, runner: runner, output: output, context: { "ctx" })
        model.send("Move tomorrow")
        model.stopSpeaking()
        await runner.waitForCurrentTurn()
        await settle()

        XCTAssertFalse(output.spoken.contains(VoiceCheckInModel.stagedLine))
        XCTAssertEqual(model.notice, VoiceCheckInModel.stagedLine)
        XCTAssertEqual(conv.messages[1].proposal?.status, .pending)
    }

    func test_pendingList_dropsResolvedProposals_andUserTurns() {
        let conv = freshStore()
        let plan = CoachMessage(role: "assistant", text: "a",
                                proposal: CoachProposal(ops: [ProposalOp(op: "move")]))
        let applied = CoachMessage(role: "assistant", text: "b",
                                   proposal: CoachProposal(ops: [ProposalOp(op: "move")]))
        let rejected = CoachMessage(role: "assistant", text: "c",
                                    proposal: CoachProposal(ops: [ProposalOp(op: "move")]))
        conv.append(CoachMessage(role: "user", text: "hi"))
        conv.append(plan)
        conv.append(applied)
        conv.append(rejected)
        conv.setProposalStatus(messageId: applied.id, .applied)
        conv.setProposalStatus(messageId: rejected.id, .rejected)

        XCTAssertEqual(conv.pendingProposalMessages.map(\.id), [plan.id])
    }
}
