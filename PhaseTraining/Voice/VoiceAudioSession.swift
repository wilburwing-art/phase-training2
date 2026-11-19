import AVFoundation

/// Tracks whether a push-to-talk utterance holds the shared `AVAudioSession`.
/// `SpeechInput` sets it while listening or finishing; `SpeechOutput` reads it
/// and, while it is set, speaks inside the mic's `.playAndRecord` session
/// without changing the category or deactivating, so a cue cannot cut the mic.
@MainActor
final class VoiceAudioSessionOwner {
    static let shared = VoiceAudioSessionOwner()
    var micLive = false
}

/// The two session calls `SpeechOutput` makes, split out so tests can count them.
@MainActor
protocol SpeechOutputAudioSession: AnyObject {
    func activateForPlayback() throws
    func deactivate() throws
}

@MainActor
final class SystemSpeechOutputAudioSession: SpeechOutputAudioSession {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func activateForPlayback() throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
