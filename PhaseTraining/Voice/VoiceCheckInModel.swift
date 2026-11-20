import Combine
import Foundation

/// Splits a streamed reply into whole sentences for the speaker. `feed` takes
/// the reply's full text so far and returns the sentences that completed since
/// the last call; `flush` returns whatever is left once the stream ends.
struct SpokenSentenceChunker {
    /// Characters of the reply already handed out.
    private(set) var consumed = 0

    mutating func feed(_ fullText: String) -> [String] {
        let chars = Array(fullText)
        guard consumed < chars.count else { return [] }
        var out: [String] = []
        var start = consumed
        var i = consumed
        while i < chars.count {
            let c = chars[i]
            let isTerminator = c == "." || c == "!" || c == "?" || c == "\n"
            // A terminator counts once the next character is whitespace, so
            // "2.5 kg" and a sentence still streaming stay whole.
            if isTerminator, i + 1 < chars.count, chars[i + 1].isWhitespace || c == "\n" {
                if let s = Self.speakable(String(chars[start...i])) { out.append(s) }
                start = i + 1
            }
            i += 1
        }
        consumed = start
        return out
    }

    mutating func flush(_ fullText: String) -> [String] {
        var out = feed(fullText)
        let chars = Array(fullText)
        if consumed < chars.count, let s = Self.speakable(String(chars[consumed...])) {
            out.append(s)
        }
        consumed = chars.count
        return out
    }

    /// Drops markdown marks and the warning glyph the runner adds to notes,
    /// trims, and returns nil when nothing is left to say.
    static func speakable(_ raw: String) -> String? {
        var text = raw
        for mark in ["**", "__", "`", "#", "⚠️"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("- ") || text.hasPrefix("* ") { text.removeFirst(2) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return text
    }
}

/// Voice check-in with the coach: push-to-talk into `CoachTurnRunner`, the
/// streamed reply spoken sentence by sentence through `SpeechOutputting`, and a
/// stop that silences the rest of the reply. The turn lands in the same per-day
/// thread the drawer shows.
@MainActor
final class VoiceCheckInModel: ObservableObject {
    @Published private(set) var inputState: SpeechInput.State = .idle
    /// True from a sent turn until its reply is fully spoken or stopped.
    @Published private(set) var replying = false
    /// Last line shown under the mic: an unavailable reason or a refused send.
    @Published private(set) var notice: String?

    let runner: CoachTurnRunner
    private let conv: CoachConversationStore
    private let output: SpeechOutputting
    private let context: @MainActor () -> String
    private let makeInput: @MainActor (SpeechOutputting) async -> SpeechInput
    private var input: SpeechInput?
    private var chunker = SpokenSentenceChunker()
    private var replyId: UUID?
    private var muted = false
    private var sinks: Set<AnyCancellable> = []
    private var inputSink: AnyCancellable?
    private var speakingWatch: Task<Void, Never>?

    init(conv: CoachConversationStore,
         runner: CoachTurnRunner,
         output: SpeechOutputting,
         context: @escaping @MainActor () -> String,
         input: SpeechInput? = nil,
         makeInput: @escaping @MainActor (SpeechOutputting) async -> SpeechInput = { await SpeechInput.makeDefault(output: $0) }) {
        self.conv = conv
        self.runner = runner
        self.output = output
        self.context = context
        self.makeInput = makeInput
        if let input { attach(input) }

        conv.$messages
            .sink { [weak self] messages in self?.messagesChanged(messages) }
            .store(in: &sinks)
        runner.$sending
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] sending in
                // @Published fires before the store updates, so read on the next turn of the loop.
                guard !sending else { return }
                Task { @MainActor in self?.turnEnded() }
            }
            .store(in: &sinks)
    }

    /// The screen and its entry points show only where the coach can answer.
    static func isOffered(consent: Bool, pro: Bool,
                          requirePro: Bool = CoachEntitlement.proRequired,
                          available: Bool = CoachEntitlement.coachAvailable) -> Bool {
        CoachEntitlement.unlocked(consent: consent, pro: pro, requirePro: requirePro, available: available)
    }

    private func attach(_ input: SpeechInput) {
        self.input = input
        inputState = input.state
        inputSink = input.$state.sink { [weak self] in self?.inputState = $0 }
    }

    // MARK: - Mic

    func pressDown() async {
        if input == nil { attach(await makeInput(output)) }
        guard let input else { return }
        stopSpeaking()
        notice = nil
        await input.pressDown(exerciseNames: [])
        if case .unavailable(let reason) = input.state { notice = reason.message }
    }

    func release() async {
        guard let input, case .listening = input.state else { return }
        guard let transcript = await input.release() else {
            notice = "Didn't catch that"
            return
        }
        send(transcript)
    }

    func cancel() {
        input?.cancel()
        stopSpeaking()
        runner.cancel()
    }

    /// Runs a turn with `transcript`. Public so tests skip the mic.
    func send(_ transcript: String) {
        guard runner.send(transcript, context: context()) else {
            notice = conv.atHardCap ? "That's the coach's limit for today." : "The coach is still answering."
            return
        }
        replyId = runner.streamingId
        chunker = SpokenSentenceChunker()
        muted = false
        replying = true
        notice = nil
    }

    // MARK: - Speaking

    /// Tap to stop: silences the current sentence and the rest of this reply.
    /// The text keeps streaming into the thread.
    func stopSpeaking() {
        guard replying else { return }
        muted = true
        output.stop()
        if !runner.sending { finishReply() }
        // Still streaming: `turnEnded` clears `replying` once the stream closes.
    }

    private func messagesChanged(_ messages: [CoachMessage]) {
        guard let id = replyId, !muted,
              let reply = messages.first(where: { $0.id == id }) else { return }
        for sentence in chunker.feed(reply.text) { output.speak(sentence) }
    }

    private func turnEnded() {
        guard let id = replyId, !runner.sending else { return }
        if !muted, let reply = conv.messages.first(where: { $0.id == id }) {
            for sentence in chunker.flush(reply.text) { output.speak(sentence) }
        }
        replyId = nil
        // The stop control stays up until the queued sentences finish playing.
        speakingWatch?.cancel()
        speakingWatch = Task { [weak self] in
            while let model = self, !model.muted, model.output.isSpeaking {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
            }
            self?.finishReply()
        }
    }

    private func finishReply() {
        speakingWatch?.cancel()
        speakingWatch = nil
        replyId = nil
        replying = false
    }
}
