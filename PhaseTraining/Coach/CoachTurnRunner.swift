// CoachTurnRunner.swift — one coach chat turn, independent of any view.
//
// The drawer used to own this logic in `CoachDrawer.send()`. Voice check-in
// (voice 3.2) runs turns with no drawer on screen, into the same per-day
// thread in `CoachConversationStore`, so the turn lives here and both
// surfaces call it.

import Foundation

/// The streaming call a turn makes. `CoachClient` conforms; tests pass a fake.
protocol CoachTurnStreaming: Sendable {
    func stream(
        cachedSystem: String,
        perTurnContext: String,
        history: [CoachClient.Turn],
        userMessage: String,
        tools: [AnthropicTool]?
    ) -> AsyncThrowingStream<CoachClient.StreamPart, Error>
}

extension CoachClient: CoachTurnStreaming {
    nonisolated func stream(
        cachedSystem: String,
        perTurnContext: String,
        history: [CoachClient.Turn],
        userMessage: String,
        tools: [AnthropicTool]?
    ) -> AsyncThrowingStream<CoachClient.StreamPart, Error> {
        stream(
            cachedSystem: cachedSystem,
            perTurnContext: perTurnContext,
            history: history,
            userMessage: userMessage,
            model: CoachConfig.defaultModel,
            tools: tools
        )
    }
}

@MainActor
final class CoachTurnRunner: ObservableObject {
    @Published private(set) var sending: Bool = false
    /// Id of the assistant message the current turn streams into.
    @Published private(set) var streamingId: UUID? = nil

    private let conv: CoachConversationStore
    private let client: CoachTurnStreaming
    private let now: () -> Date
    private var inflightTask: Task<Void, Never>? = nil

    init(
        conv: CoachConversationStore,
        client: CoachTurnStreaming = CoachClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.conv = conv
        self.client = client
        self.now = now
    }

    /// Start a turn. Returns false (and does nothing) when the text is blank,
    /// the hard daily cap is hit, or a turn is already streaming.
    /// `context` is the per-turn snapshot from `chatContext(...)`.
    @discardableResult
    func send(_ rawText: String, context: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return false }
        guard !conv.atHardCap else { return false }

        // Phase 13f: if the most recent assistant turn carried a proposal the
        // user has resolved, prepend a synthetic status note so the model
        // knows what happened to its tool call. The v4 system prompt
        // advertises this convention so the prefix is read as metadata. The
        // prefix goes only to the wire; the bubble shows what the user said.
        let wireText = Self.statusPrefix(for: conv.messages.last) + text

        let userMsg = CoachMessage(role: "user", text: text)
        let assistantMsg = CoachMessage(role: "assistant", text: "")
        conv.append(userMsg)
        conv.append(assistantMsg)
        conv.recordTurn(now: now())
        streamingId = assistantMsg.id
        sending = true

        let history = Array(conv.wireHistory().dropLast())  // exclude the new user msg itself
        let today = DayKeyFormatter.iso.string(from: now())
        let client = self.client

        inflightTask = Task { [weak self] in
            do {
                let stream = client.stream(
                    cachedSystem: CoachSystemPrompt.cachedHeader,
                    perTurnContext: CoachSystemPrompt.contextBlock(snapshot: context),
                    history: history,
                    userMessage: wireText,
                    tools: CoachTools.chat
                )
                for try await part in stream {
                    guard let self else { return }
                    self.handle(part, assistantId: assistantMsg.id, today: today)
                }
                self?.finishSuccess()
            } catch {
                self?.finishError(error)
            }
        }
        return true
    }

    /// Stop the in-flight turn. The partial reply stays in the thread.
    func cancel() {
        inflightTask?.cancel()
    }

    /// Await the in-flight turn. Tests use this; views do not.
    func waitForCurrentTurn() async {
        await inflightTask?.value
    }

    // MARK: - Context

    /// The chat surface's per-turn snapshot. Wires the blocks only chat
    /// passes (past weeks, plan issues, missed and abandoned workouts, day
    /// outcomes, open suggestions, session likelihood); the insight and
    /// refinement passes are one-shot and cost-sensitive and stay lean.
    static func chatContext(
        activeTab: AppTab,
        memoryStore: MemoryStore,
        planStore: PlanStore,
        sessionStore: SessionStore,
        sportLogStore: SportLogStore,
        now: Date = Date()
    ) -> String {
        // Sport logs window: last 21 days, capped to the most recent 30 to
        // keep the prompt bounded for a high-frequency logger.
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: now) ?? Date.distantPast
        let recentSportLogs = sportLogStore.entries
            .filter { $0.date >= cutoff }
            .suffix(30)

        return CoachContext.snapshot(
            activeTab: activeTab,
            memory: memoryStore.memory,
            plan: planStore.plan,
            recentSessions: sessionStore.savedSessions,
            recentFeedback: memoryStore.memory.feedback,
            recentSoreness: memoryStore.memory.soreness,
            recentSportLogs: Array(recentSportLogs),
            pastPlans: planStore.pastPlans,
            planIssues: planStore.currentValidationIssues(memory: memoryStore.memory),
            missedWorkouts: planStore.missedWorkouts,
            abandonedWorkouts: planStore.abandonedWorkouts,
            dayOutcomes: planStore.dayOutcomes,
            openSuggestions: planStore.currentSuggestions(),
            sessionLikelihood: planStore.todaySessionLikelihood()
        )
    }

    /// "[STATUS NOTE: ...]" prefix when the previous assistant turn had a
    /// proposal the user has resolved. "" otherwise.
    static func statusPrefix(for prior: CoachMessage?) -> String {
        guard let prior, !prior.isUser else { return "" }
        var notes: [String] = []
        if let p = prior.proposal, p.status != .pending {
            notes.append("plan-edit proposal was \(p.status.rawValue.uppercased())")
        }
        if let p = prior.workoutProposal, p.status != .pending {
            notes.append("workout-change proposal was \(p.status.rawValue.uppercased())")
        }
        if let p = prior.memoryProposal, p.status != .pending {
            notes.append("memory-update proposal was \(p.status.rawValue.uppercased())")
        }
        guard !notes.isEmpty else { return "" }
        return "[STATUS NOTE — system metadata, not user speech: your last \(notes.joined(separator: "; "))]\n\n"
    }

    // MARK: - Stream handling

    private func handle(_ part: CoachClient.StreamPart, assistantId: UUID, today: String) {
        switch part {
        case .textDelta(let chunk):
            conv.appendDelta(to: assistantId, chunk)
        case .toolCall(_, let name, let inputData):
            // A failed decode used to fall through with nothing shown: the
            // assistant said "I've proposed moving Thursday to Friday", no
            // diff card rendered, and the user had no error and no way to
            // retry. Truncation at max_tokens and malformed
            // input_json_delta both land here.
            var decoded = true
            switch name {
            case "propose_plan_edits":
                if let proposal = CoachToolDecoder.decodeProposal(from: inputData) {
                    conv.setProposal(on: assistantId, proposal)
                } else {
                    decoded = false
                }
            case "propose_workout_changes":
                // Build 99: today is the fallback. A `date` in the tool
                // input wins, so chat can edit any day in the current plan.
                if let proposal = CoachToolDecoder.decodeWorkoutProposal(from: inputData, fallbackDate: today) {
                    conv.setWorkoutProposal(on: assistantId, proposal)
                } else {
                    decoded = false
                }
            case "propose_memory_update":
                if let proposal = CoachToolDecoder.decodeMemoryProposal(from: inputData) {
                    conv.setMemoryProposal(on: assistantId, proposal)
                } else {
                    decoded = false
                }
            default:
                return
            }
            if !decoded { appendNote(Self.undeliveredProposalNote) }
        case .stopped(let reason):
            // "max_tokens" means the model was cut off mid-thought.
            if reason == "max_tokens" { appendNote(Self.truncatedReplyNote) }
        }
    }

    static let undeliveredProposalNote = "\n\n⚠️ That change didn't come through in a usable form. Ask again and I'll re-propose it."
    static let truncatedReplyNote = "\n\n… (cut off. Ask me to continue)"

    private func appendNote(_ note: String) {
        guard let id = streamingId,
              let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        if !conv.messages[idx].text.hasSuffix(note) {
            conv.messages[idx].text += note
        }
    }

    private func finishSuccess() {
        conv.flush()
        sending = false
        streamingId = nil
        inflightTask = nil
    }

    private func finishError(_ error: Error) {
        if let id = streamingId,
           let idx = conv.messages.firstIndex(where: { $0.id == id }) {
            let prefix = conv.messages[idx].text.isEmpty ? "" : conv.messages[idx].text + "\n\n"
            conv.messages[idx].text = prefix + "⚠️ " + Self.userFacingMessage(for: error)
        }
        conv.flush()
        sending = false
        streamingId = nil
        inflightTask = nil
    }

    /// User-facing error taxonomy. `error.localizedDescription` used to go
    /// straight into the assistant bubble, so the coach appeared to say things
    /// like "No Cloudflare AI Gateway token configured. Set
    /// PHASETRAINING_CF_AIG_DEV_TOKEN in ~/.config/phase-training/…" or up to
    /// 512 characters of raw gateway JSON. Three cases the user can act on;
    /// anything else is "try again".
    static func userFacingMessage(for error: Error) -> String {
        if let coachError = error as? CoachClient.CoachError {
            switch coachError {
            case .dailyCeilingReached:
                return "That's the coach's limit for today. It'll pick back up tomorrow."
            case .missingGatewayToken:
                return "The coach isn't available in this build."
            case .http(let status, _):
                if status == 429 { return "The coach is rate-limited right now. Try again in a minute." }
                if (500...599).contains(status) { return "The coach is having trouble on its end. Try again shortly." }
                return "The coach couldn't complete that. Try again."
            case .transport:
                return "Couldn't reach the coach. Check your connection and try again."
            case .decode:
                return "The coach's reply came back garbled. Try again."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the coach. Check your connection and try again."
        }
        return "Something went wrong reaching the coach. Try again."
    }
}
