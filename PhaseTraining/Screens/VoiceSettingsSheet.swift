// VoiceSettingsSheet.swift — Profile > Voice: spoken cues, cue level, voice
// picker with a sample, and the push-to-talk hint. Values persist through
// VoiceSettings (three pt_voice_* keys).

import AVFoundation
import SwiftUI

struct VoiceSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = VoiceSettings.load()
    @State private var voices: [VoiceOption] = []
    @State private var speaker: SpeechOutput?

    static let sampleLine = "Rest's up. Bench, set 3 of 4, 185 for 5."

    struct VoiceOption: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("SPOKEN CUES")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        Toggle(isOn: $settings.cuesOn) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spoken cues")
                                    .styled(.body)
                                    .foregroundStyle(Color.ink)
                                Text("Says the next set when rest ends · music ducks while it talks")
                                    .font(.monoXS)
                                    .foregroundStyle(Color.ink3)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Color.accent)
                        .accessibilityIdentifier("voice.cues")

                        if settings.cuesOn {
                            Text("CUE LEVEL")
                                .styled(.micro)
                                .foregroundStyle(Color.ink3)
                                .padding(.top, 8)
                            ForEach(VoiceSettings.CueLevel.allCases, id: \.self) { level in
                                choiceRow(title: level.label,
                                          detail: nil,
                                          selected: settings.level == level,
                                          identifier: "voice.level.\(level.rawValue)") {
                                    settings.level = level
                                }
                            }
                        }

                        Text("VOICE")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 8)
                        choiceRow(title: "Automatic",
                                  detail: "Best installed voice for your language",
                                  selected: settings.voiceId == nil,
                                  identifier: "voice.pick.automatic") {
                            settings.voiceId = nil
                        }
                        ForEach(voices) { voice in
                            choiceRow(title: voice.name,
                                      detail: voice.detail,
                                      selected: settings.voiceId == voice.id,
                                      identifier: "voice.pick.\(voice.id)") {
                                settings.voiceId = voice.id
                            }
                        }
                        Button(action: playSample) {
                            Label("Play sample", systemImage: "play.circle")
                                .styled(.body)
                                .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Speaks a rest cue in the chosen voice")
                        .accessibilityIdentifier("voice.sample")
                        Text("More voices: Settings > Accessibility > Spoken Content > Voices")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)

                        Text("PUSH TO TALK")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                            .padding(.top, 8)
                        Text("During a workout, hold the mic on the log screen and say \"185 for 5\", \"same again\" or \"skip rest\". The mic is on only while you hold it, and speech is recognized on the phone.")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            settings = VoiceSettings.load()
            voices = Self.installedVoices()
        }
        .onChange(of: settings) { _, new in new.save() }
        .onDisappear { speaker?.stop() }
    }

    private func choiceRow(title: String, detail: String?, selected: Bool,
                           identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    if let detail {
                        Text(detail)
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .scaledSystemFont(20)
                    .foregroundStyle(selected ? Color.accent : Color.ink3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentWash : Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentBorder : Color.lineStrong, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    private func playSample() {
        let output = speaker ?? SpeechOutput()
        speaker = output
        output.stop()
        output.voiceIdentifier = settings.voiceId
        output.speak(Self.sampleLine)
    }

    /// Installed voices in the device language, best quality first. Novelty
    /// and Personal Voice entries are left out, matching `SpeechVoicePicker`.
    static func installedVoices(
        language: String = AVSpeechSynthesisVoice.currentLanguageCode()
    ) -> [VoiceOption] {
        let base = language.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let candidate = SpeechVoiceCandidate(voice)
                return !candidate.isNovelty && !candidate.isPersonal
                    && voice.language.replacingOccurrences(of: "_", with: "-")
                        .split(separator: "-").first.map(String.init)?.lowercased() == base
            }
            .sorted { a, b in
                a.quality.rawValue != b.quality.rawValue
                    ? a.quality.rawValue > b.quality.rawValue
                    : (a.name, a.identifier) < (b.name, b.identifier)
            }
            .map { voice in
                let quality: String
                switch voice.quality {
                case .premium: quality = "Premium"
                case .enhanced: quality = "Enhanced"
                default: quality = "Standard"
                }
                return VoiceOption(id: voice.identifier, name: voice.name,
                                   detail: "\(voice.language) · \(quality)")
            }
    }
}
