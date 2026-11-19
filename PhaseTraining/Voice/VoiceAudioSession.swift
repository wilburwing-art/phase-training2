import AVFoundation

/// Tracks who holds the shared `AVAudioSession`, so the mic and the speaker
/// never deactivate it under each other.
///
/// `micLive`: `SpeechInput` sets it while listening or finishing; `SpeechOutput`
/// reads it and, while it is set, speaks inside the mic's `.playAndRecord`
/// session without changing the category or deactivating, so a cue cannot cut
/// the mic.
///
/// `speaking`: `SpeechOutput` sets it from `speak` until its synthesizer goes
/// idle. A transcriber closing the mic while it is set leaves the session up
/// and hands the deactivate to `SpeechOutput.deactivateIfIdle`, so releasing
/// the mic cannot cut a cue mid-sentence.
@MainActor
final class VoiceAudioSessionOwner {
    static let shared = VoiceAudioSessionOwner()
    var micLive = false
    var speaking = false
    /// Set when the mic closed during a cue; the cue's end deactivates.
    private(set) var deactivateHandedToSpeech = false

    /// A transcriber activated the session for recording; it owns it again.
    func micAudioStarted() {
        deactivateHandedToSpeech = false
    }

    /// A transcriber stopped recording. Runs `deactivate` now, or, while a cue
    /// is speaking, leaves the session active for the cue to finish.
    func micAudioStopped(deactivate: () -> Void) {
        if speaking {
            deactivateHandedToSpeech = true
        } else {
            deactivate()
        }
    }

    /// Called by `SpeechOutput` once its synthesizer is idle. True when the
    /// session should be deactivated now: the mic handed it over, or the mic
    /// is not live.
    func speechEnded() -> Bool {
        speaking = false
        if deactivateHandedToSpeech {
            deactivateHandedToSpeech = false
            return true
        }
        return !micLive
    }
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
