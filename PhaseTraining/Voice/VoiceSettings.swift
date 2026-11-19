import Foundation

/// The workout voice preferences from Profile > Voice. Three `pt_` keys, so
/// "Erase all data" clears them with the prefix sweep; the backup envelope
/// carries them as one optional value.
struct VoiceSettings: Codable, Equatable {
    enum CueLevel: String, Codable, CaseIterable {
        /// Speak only when rest ends.
        case restEnd
        /// Rest end, a 10 s warning, and a readback after a voice-logged set.
        case full

        var label: String {
            switch self {
            case .restEnd: return "Rest end only"
            case .full: return "Rest end, 10 s warning, readback"
            }
        }
    }

    static let cuesKey = "pt_voice_cues"
    static let levelKey = "pt_voice_level"
    static let voiceIdKey = "pt_voice_id"
    static let keys = [cuesKey, levelKey, voiceIdKey]

    var cuesOn: Bool = false
    var level: CueLevel = .restEnd
    /// `AVSpeechSynthesisVoice.identifier`. Nil picks the best installed
    /// voice for the device language (`SpeechVoicePicker.best`).
    var voiceId: String? = nil

    static func load(from defaults: UserDefaults = .standard) -> VoiceSettings {
        VoiceSettings(
            cuesOn: defaults.bool(forKey: cuesKey),
            level: defaults.string(forKey: levelKey).flatMap(CueLevel.init(rawValue:)) ?? .restEnd,
            voiceId: defaults.string(forKey: voiceIdKey)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(cuesOn, forKey: Self.cuesKey)
        defaults.set(level.rawValue, forKey: Self.levelKey)
        if let voiceId {
            defaults.set(voiceId, forKey: Self.voiceIdKey)
        } else {
            defaults.removeObject(forKey: Self.voiceIdKey)
        }
    }

    /// True when the user has never opened the sheet: no key is set.
    static func isUnset(in defaults: UserDefaults) -> Bool {
        keys.allSatisfy { defaults.object(forKey: $0) == nil }
    }
}
