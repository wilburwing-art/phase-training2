import AVFoundation
import Speech

/// Why the mic button is off. `message` is the line shown under it.
enum SpeechInputUnavailable: Equatable {
    case microphoneDenied
    case speechDenied
    case restricted
    case onDeviceUnsupported

    var message: String {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off. Turn it on in Settings > Phase Training."
        case .speechDenied:
            return "Speech recognition is off. Turn it on in Settings > Phase Training."
        case .restricted:
            return "Speech recognition is restricted on this device."
        case .onDeviceUnsupported:
            return "This device can't recognize speech offline, so voice logging is off."
        }
    }
}

enum SpeechAuthorization: Equatable { case notDetermined, granted, denied, restricted }

enum SpeechInputError: Error, Equatable {
    case onDeviceUnavailable
    case audioFormat
}

/// Mic and speech-recognition status, split from the transcriber so tests drive it.
@MainActor
protocol SpeechPermissionProviding: AnyObject {
    var microphone: SpeechAuthorization { get }
    var speech: SpeechAuthorization { get }
    func requestMicrophone() async -> SpeechAuthorization
    func requestSpeech() async -> SpeechAuthorization
}

/// One push-to-talk utterance. `start` opens the mic; `finish` stops input and returns the
/// final transcript (nil when nothing was heard); `cancel` drops it.
@MainActor
protocol SpeechTranscribing: AnyObject {
    var supportsOnDevice: Bool { get }
    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws
    func finish() async throws -> String?
    func cancel()
}

/// Push-to-talk state for the mic button. Audio stays on the device: both live
/// transcribers run on-device recognition only and have no server path.
@MainActor
final class SpeechInput: ObservableObject {
    enum State: Equatable {
        case idle
        case listening(partial: String)
        case finishing
        case unavailable(SpeechInputUnavailable)
    }

    @Published private(set) var state: State = .idle

    var micEnabled: Bool {
        if case .unavailable = state { return false }
        return true
    }

    private let transcriber: SpeechTranscribing
    private let permissions: SpeechPermissionProviding
    private var lastPartial: String?
    /// True from `pressDown` until `release` or `cancel`. A release that lands
    /// while a permission prompt is up clears it, so the mic does not open
    /// after the prompt closes.
    private var pressHeld = false

    init(transcriber: SpeechTranscribing, permissions: SpeechPermissionProviding) {
        self.transcriber = transcriber
        self.permissions = permissions
        refreshAvailability()
    }

    /// Reads current status, no prompt. Leaves a live utterance alone.
    func refreshAvailability() {
        switch state {
        case .listening, .finishing: return
        case .idle, .unavailable: break
        }
        state = Self.unavailability(
            microphone: permissions.microphone,
            speech: permissions.speech,
            supportsOnDevice: transcriber.supportsOnDevice
        ).map(State.unavailable) ?? .idle
    }

    /// Asks for any permission still `notDetermined` (mic first, then speech),
    /// then opens the mic. A no-op while an utterance or a prompt is in flight.
    func pressDown(exerciseNames: [String]) async {
        guard !pressHeld else { return }
        switch state {
        case .listening, .finishing: return
        case .idle, .unavailable: break
        }
        pressHeld = true

        var microphone = permissions.microphone
        var speech = permissions.speech
        if Self.unavailability(microphone: microphone, speech: speech, supportsOnDevice: transcriber.supportsOnDevice) == nil {
            if microphone == .notDetermined {
                microphone = await permissions.requestMicrophone()
            }
            if microphone == .granted, speech == .notDetermined {
                speech = await permissions.requestSpeech()
            }
        }

        if let reason = Self.unavailability(microphone: microphone, speech: speech, supportsOnDevice: transcriber.supportsOnDevice) {
            pressHeld = false
            state = .unavailable(reason)
            return
        }
        guard microphone == .granted, speech == .granted else {
            pressHeld = false
            state = .idle
            return
        }
        guard pressHeld else {
            state = .idle
            return
        }

        lastPartial = nil
        do {
            try transcriber.start(contextualStrings: Self.contextualStrings(exerciseNames: exerciseNames)) { [weak self] text in
                guard let self, case .listening = self.state else { return }
                self.lastPartial = text
                self.state = .listening(partial: text)
            }
            state = .listening(partial: "")
        } catch {
            print("[SpeechInput] start failed: \(error)")
            pressHeld = false
            state = .idle
        }
    }

    /// Final transcript, trimmed. Nil for empty, error, or when not listening.
    func release() async -> String? {
        let wasHeld = pressHeld
        pressHeld = false
        guard wasHeld, case .listening = state else { return nil }
        state = .finishing
        let partial = lastPartial
        lastPartial = nil
        do {
            let final = try await transcriber.finish()
            state = .idle
            return Self.resolveTranscript(final: final, lastPartial: partial)
        } catch {
            print("[SpeechInput] finish failed: \(error)")
            state = .idle
            return nil
        }
    }

    func cancel() {
        pressHeld = false
        lastPartial = nil
        switch state {
        case .listening, .finishing:
            transcriber.cancel()
            state = .idle
        case .idle, .unavailable:
            break
        }
    }

    // MARK: - Pure helpers

    /// Precedence: restricted (either), mic denied, speech denied, no on-device
    /// recognition. `notDetermined` is not a reason: `pressDown` asks.
    static func unavailability(
        microphone: SpeechAuthorization,
        speech: SpeechAuthorization,
        supportsOnDevice: Bool
    ) -> SpeechInputUnavailable? {
        if microphone == .restricted || speech == .restricted { return .restricted }
        if microphone == .denied { return .microphoneDenied }
        if speech == .denied { return .speechDenied }
        if !supportsOnDevice { return .onDeviceUnsupported }
        return nil
    }

    /// The final, trimmed. A nil final falls back to the last partial, since the
    /// recognizer sometimes drops the final on a short utterance.
    static func resolveTranscript(final: String?, lastPartial: String?) -> String? {
        let text = (final ?? lastPartial)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// The parser's command words, copied from `VoiceCommand.swift`'s private grammar.
    static let commandWords = [
        "same again", "done", "skip rest", "undo", "what's next", "how many left",
        "RPE", "kilos", "pounds", "for", "by",
    ]

    /// Apple's guidance for `contextualStrings`.
    static let contextualStringLimit = 100

    /// Exercise names (deduped case-insensitively, first casing kept, empties
    /// dropped), then the command words, capped at 100 entries.
    static func contextualStrings(exerciseNames: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for raw in exerciseNames + commandWords {
            let entry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty, seen.insert(entry.lowercased()).inserted else { continue }
            out.append(entry)
            if out.count == contextualStringLimit { break }
        }
        return out
    }

    /// iOS 26 with the current locale's assets installed uses `SpeechAnalyzer`;
    /// anything else uses `SFSpeechRecognizer`. Never downloads assets here, so
    /// a set is not held up by a model download.
    static func makeDefault() async -> SpeechInput {
        let transcriber: SpeechTranscribing
        if #available(iOS 26, *), let locale = await AnalyzerTranscriber.installedLocale() {
            transcriber = AnalyzerTranscriber(locale: locale)
        } else {
            transcriber = LegacyTranscriber()
        }
        return SpeechInput(transcriber: transcriber, permissions: SpeechPermissions())
    }
}

// MARK: - Live permissions

@MainActor
final class SpeechPermissions: SpeechPermissionProviding {
    var microphone: SpeechAuthorization {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    var speech: SpeechAuthorization { Self.map(SFSpeechRecognizer.authorizationStatus()) }

    func requestMicrophone() async -> SpeechAuthorization {
        await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }

    func requestSpeech() async -> SpeechAuthorization {
        Self.map(await Self.requestSpeechStatus())
    }

    /// The handler runs on a background queue, so it is built outside the main actor.
    nonisolated private static func requestSpeechStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
    }

    nonisolated private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechAuthorization {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }
}

// MARK: - Audio session

private enum SpeechAudioSession {
    static func activate(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .duckOthers, .defaultToSpeaker])
        try session.setActive(true)
    }

    static func deactivate(_ session: AVAudioSession) {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SpeechInput] audio session deactivate failed: \(error)")
        }
    }
}

// MARK: - SFSpeechRecognizer

@MainActor
final class LegacyTranscriber: SpeechTranscribing {
    /// How long `finish` waits for the recognizer's final after input ends.
    private static let finalTimeout: UInt64 = 3_000_000_000

    private let recognizer: SFSpeechRecognizer?
    private let session: AVAudioSession
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onPartial: ((String) -> Void)?
    private var inputEnded = false
    private var outcome: Result<String?, Error>?
    private var waiter: CheckedContinuation<String?, Error>?
    /// Bumped per utterance so a late callback or timeout from the last one is dropped.
    private var generation = 0

    init(locale: Locale = .current, session: AVAudioSession = .sharedInstance()) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.session = session
    }

    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition == true }

    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw SpeechInputError.onDeviceUnavailable
        }
        reset()
        try SpeechAudioSession.activate(session)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(into: request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            SpeechAudioSession.deactivate(session)
            throw error
        }

        self.request = request
        self.onPartial = onPartial
        let current = generation
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, error in
            guard let self, self.generation == current else { return }
            self.receive(text: text, isFinal: isFinal, error: error)
        })
    }

    func finish() async throws -> String? {
        guard task != nil else { return nil }
        let current = generation
        stopAudio()
        if outcome == nil {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.finalTimeout)
                guard let self, self.generation == current else { return }
                self.resolve(.success(nil))
            }
        }
        defer { if generation == current { reset() } }
        if let outcome { return try outcome.get() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func cancel() {
        task?.cancel()
        stopAudio()
        resolve(.success(nil))
        reset()
    }

    private func receive(text: String?, isFinal: Bool, error: Error?) {
        if let text, !isFinal, !inputEnded { onPartial?(text) }
        if isFinal {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            resolve(.success(trimmed.isEmpty ? nil : trimmed))
        } else if let error {
            // After input ends the recognizer reports "no speech" or a dropped
            // final as an error; that is "nothing final", so the caller's last
            // partial still counts. An error while listening is a real failure.
            resolve(inputEnded ? .success(nil) : .failure(error))
        }
    }

    private func resolve(_ result: Result<String?, Error>) {
        guard outcome == nil else { return }
        outcome = result
        if let waiter {
            self.waiter = nil
            waiter.resume(with: result)
        }
    }

    private func stopAudio() {
        guard !inputEnded else { return }
        inputEnded = true
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        SpeechAudioSession.deactivate(session)
    }

    private func reset() {
        generation += 1
        task = nil
        request = nil
        onPartial = nil
        inputEnded = false
        outcome = nil
        waiter = nil
    }

    nonisolated private static func tap(into request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// The recognizer calls back on its own queue; this hops to the main actor.
    nonisolated private static func resultHandler(
        _ deliver: @escaping @MainActor (String?, Bool, Error?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in deliver(text, isFinal, error) }
        }
    }
}

// MARK: - SpeechAnalyzer

@available(iOS 26, *)
@MainActor
final class AnalyzerTranscriber: SpeechTranscribing {
    private let locale: Locale?
    private let session: AVAudioSession
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var rawInput: AsyncStream<AnalyzerInput>.Continuation?
    private var feedTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Error>?
    private var finalized = ""
    private var volatile = ""
    private var tapRunning = false
    private var generation = 0

    /// `locale` is a `SpeechTranscriber` supported locale; nil means none, so
    /// `supportsOnDevice` is false.
    init(locale: Locale?, session: AVAudioSession = .sharedInstance()) {
        self.locale = locale
        self.session = session
    }

    var supportsOnDevice: Bool { locale != nil }

    /// The supported locale for `locale` when its assets are already installed.
    static func installedLocale(for locale: Locale = .current) async -> Locale? {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let probe = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        return await AssetInventory.status(forModules: [probe]) == .installed ? supported : nil
    }

    func start(contextualStrings: [String], onPartial: @escaping (String) -> Void) throws {
        guard let locale else { throw SpeechInputError.onDeviceUnavailable }
        teardown()
        try SpeechAudioSession.activate(session)

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (rawStream, rawInput) = AsyncStream<AnalyzerInput>.makeStream()

        let input = engine.inputNode
        let naturalFormat = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: naturalFormat, block: Self.tap(into: rawInput))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            rawInput.finish()
            SpeechAudioSession.deactivate(session)
            throw error
        }
        tapRunning = true
        self.analyzer = analyzer
        self.rawInput = rawInput

        let current = generation
        resultsTask = Task { [weak self] in
            for try await result in transcriber.results {
                guard let self, self.generation == current else { return }
                self.receive(String(result.text.characters), isFinal: result.isFinal, onPartial: onPartial)
            }
        }
        feedTask = Task {
            try await Self.feed(analyzer: analyzer, transcriber: transcriber, naturalFormat: naturalFormat,
                                contextualStrings: contextualStrings, raw: rawStream)
        }
    }

    func finish() async throws -> String? {
        guard let analyzer else { return nil }
        let current = generation
        stopAudio()
        defer { if generation == current { teardown() } }
        try await feedTask?.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask?.value
        let text = finalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func cancel() {
        guard let analyzer else { return }
        stopAudio()
        Task { await analyzer.cancelAndFinishNow() }
        teardown()
    }

    private func receive(_ text: String, isFinal: Bool, onPartial: (String) -> Void) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
        if tapRunning { onPartial(finalized + volatile) }
    }

    private func stopAudio() {
        guard tapRunning else { return }
        tapRunning = false
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        rawInput?.finish()
        SpeechAudioSession.deactivate(session)
    }

    private func teardown() {
        generation += 1
        feedTask?.cancel()
        resultsTask?.cancel()
        feedTask = nil
        resultsTask = nil
        analyzer = nil
        rawInput = nil
        finalized = ""
        volatile = ""
    }

    nonisolated private static func tap(into stream: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in stream.yield(AnalyzerInput(buffer: buffer)) }
    }

    /// Sets the contextual strings, starts the analyzer, and converts the mic's
    /// buffers to the analyzer's format until the tap stream ends.
    nonisolated private static func feed(
        analyzer: SpeechAnalyzer,
        transcriber: SpeechTranscriber,
        naturalFormat: AVAudioFormat,
        contextualStrings: [String],
        raw: AsyncStream<AnalyzerInput>
    ) async throws {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: naturalFormat) else {
            throw SpeechInputError.audioFormat
        }
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)

        let (converted, output) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: converted)

        let converter = format == naturalFormat ? nil : AVAudioConverter(from: naturalFormat, to: format)
        converter?.primeMethod = .none
        defer { output.finish() }
        for await input in raw {
            if let converter {
                output.yield(AnalyzerInput(buffer: try convert(input.buffer, with: converter, to: format)))
            } else {
                output.yield(input)
            }
        }
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else {
            throw SpeechInputError.audioFormat
        }
        // The input block runs synchronously inside `convert`, on this thread.
        nonisolated(unsafe) let source = buffer
        nonisolated(unsafe) var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        if status == .error { throw conversionError ?? SpeechInputError.audioFormat }
        return out
    }
}
