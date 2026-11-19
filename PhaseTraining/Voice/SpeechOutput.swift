import AVFoundation

/// Spoken output for the workout voice layer. `speak` talks over ducked
/// music; `renderToFile` writes a `.caf` under `Library/Sounds` so a local
/// notification can play the line with the phone locked.
@MainActor
protocol SpeechOutputting: AnyObject {
    func speak(_ text: String)
    func stop()
    func renderToFile(_ text: String) async throws -> URL
}

enum SpeechOutputError: Error, Equatable {
    case noVoice
    case emptyRender
    /// Notification sounds over 30 s fall back to the default sound.
    case tooLong(seconds: Double)
}

/// The voice fields the ranking reads. `AVSpeechSynthesisVoice` cannot be
/// built with chosen values, so tests rank a fixed list of these.
struct SpeechVoiceCandidate: Equatable {
    enum Quality: Int, Comparable {
        case standard = 1, enhanced = 2, premium = 3
        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    var identifier: String
    var language: String
    var quality: Quality
    var isNovelty: Bool = false
    var isPersonal: Bool = false
}

extension SpeechVoiceCandidate {
    init(_ voice: AVSpeechSynthesisVoice) {
        let quality: Quality
        switch voice.quality {
        case .premium: quality = .premium
        case .enhanced: quality = .enhanced
        default: quality = .standard
        }
        self.init(
            identifier: voice.identifier,
            language: voice.language,
            quality: quality,
            isNovelty: voice.voiceTraits.contains(.isNoveltyVoice),
            isPersonal: voice.voiceTraits.contains(.isPersonalVoice)
        )
    }
}

enum SpeechVoicePicker {
    /// Highest quality voice for `language` (BCP 47, "en-US"). An exact
    /// region match beats a better voice from another region of the same
    /// language, so a US user keeps a US accent. Novelty and Personal Voice
    /// entries are skipped. Ties go to the lowest identifier for a stable pick.
    static func best(from voices: [SpeechVoiceCandidate], language: String) -> SpeechVoiceCandidate? {
        let wanted = normalized(language)
        let base = wanted.split(separator: "-").first.map(String.init) ?? wanted
        let usable = voices.filter { !$0.isNovelty && !$0.isPersonal }

        func pick(_ pool: [SpeechVoiceCandidate]) -> SpeechVoiceCandidate? {
            pool.max { a, b in
                a.quality != b.quality ? a.quality < b.quality : a.identifier > b.identifier
            }
        }

        let exact = usable.filter { normalized($0.language) == wanted }
        if let voice = pick(exact) { return voice }
        let sameLanguage = usable.filter {
            normalized($0.language).split(separator: "-").first.map(String.init) == base
        }
        return pick(sameLanguage)
    }

    private static func normalized(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

@MainActor
final class SpeechOutput: NSObject, SpeechOutputting {
    private let synthesizer = AVSpeechSynthesizer()
    private let session: AVAudioSession
    private let language: String
    private let soundsDirectory: URL
    private var renders: [UUID: SpeechFileRender] = [:]

    init(
        language: String = AVSpeechSynthesisVoice.currentLanguageCode(),
        session: AVAudioSession = .sharedInstance(),
        soundsDirectory: URL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    ) {
        self.language = language
        self.session = session
        self.soundsDirectory = soundsDirectory
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !text.isEmpty, let utterance = makeUtterance(text) else { return }
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[SpeechOutput] audio session activate failed: \(error)")
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func renderToFile(_ text: String) async throws -> URL {
        guard let utterance = makeUtterance(text) else { throw SpeechOutputError.noVoice }
        try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        let url = soundsDirectory.appendingPathComponent("pt_speech_\(Self.stableHash(text)).caf")
        try? FileManager.default.removeItem(at: url)

        let id = UUID()
        let render = SpeechFileRender(url: url)
        renders[id] = render
        defer { renders[id] = nil }
        try await render.run(utterance)

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        guard file.length > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw SpeechOutputError.emptyRender
        }
        guard seconds < 30 else {
            try? FileManager.default.removeItem(at: url)
            throw SpeechOutputError.tooLong(seconds: seconds)
        }
        return url
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        guard let choice = SpeechVoicePicker.best(from: installed.map(SpeechVoiceCandidate.init), language: language),
              let voice = AVSpeechSynthesisVoice(identifier: choice.identifier) else { return nil }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        return utterance
    }

    private func deactivateIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SpeechOutput] audio session deactivate failed: \(error)")
        }
    }

    /// FNV-1a, so the same line maps to the same file name across launches.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateIfIdle() }
    }
}

/// One `AVSpeechSynthesizer.write` call into a file. The synthesizer signals
/// the end with a zero-length buffer; the delegate's didFinish is a delayed
/// second end signal, and whichever arrives first resumes the caller once.
@MainActor
private final class SpeechFileRender: NSObject, AVSpeechSynthesizerDelegate {
    private let url: URL
    private let synthesizer = AVSpeechSynthesizer()
    private var file: AVAudioFile?
    private var writeError: Error?
    private var continuation: CheckedContinuation<Void, Error>?

    init(url: URL) {
        self.url = url
        super.init()
        synthesizer.delegate = self
    }

    func run(_ utterance: AVSpeechUtterance) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            synthesizer.write(utterance) { [weak self] buffer in
                Task { @MainActor in self?.receive(buffer) }
            }
        }
    }

    private func receive(_ buffer: AVAudioBuffer) {
        guard continuation != nil else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            finish()
            return
        }
        do {
            if file == nil {
                file = try AVAudioFile(
                    forWriting: url,
                    settings: pcm.format.settings,
                    commonFormat: pcm.format.commonFormat,
                    interleaved: pcm.format.isInterleaved
                )
            }
            try file?.write(from: pcm)
        } catch {
            writeError = error
            finish()
        }
    }

    private func finish() {
        guard let cont = continuation else { return }
        continuation = nil
        file = nil  // closes the file
        if let writeError {
            cont.resume(throwing: writeError)
        } else if !FileManager.default.fileExists(atPath: url.path) {
            cont.resume(throwing: SpeechOutputError.emptyRender)
        } else {
            cont.resume()
        }
    }

    /// Fallback for OS versions that skip the zero-length buffer. The wait
    /// lets buffer tasks still hopping to the main actor land first.
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.finish()
        }
    }
}

/// Records calls for tests and previews.
@MainActor
final class FakeSpeechOutput: SpeechOutputting {
    private(set) var spoken: [String] = []
    private(set) var stopCount = 0
    private(set) var rendered: [String] = []
    var renderResult: Result<URL, Error> = .failure(SpeechOutputError.noVoice)

    func speak(_ text: String) { spoken.append(text) }
    func stop() { stopCount += 1 }
    func renderToFile(_ text: String) async throws -> URL {
        rendered.append(text)
        return try renderResult.get()
    }
}
