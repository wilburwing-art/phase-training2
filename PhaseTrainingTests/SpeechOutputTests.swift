import AVFoundation
import XCTest
@testable import PhaseTraining

@MainActor
final class SpeechOutputTests: XCTestCase {

    private typealias V = SpeechVoiceCandidate

    private let fixedVoices: [V] = [
        V(identifier: "com.apple.voice.compact.en-US.Samantha", language: "en-US", quality: .standard),
        V(identifier: "com.apple.voice.enhanced.en-US.Evan", language: "en-US", quality: .enhanced),
        V(identifier: "com.apple.voice.premium.en-GB.Malcolm", language: "en-GB", quality: .premium),
        V(identifier: "com.apple.speech.synthesis.voice.Bubbles", language: "en-US", quality: .premium, isNovelty: true),
        V(identifier: "personal.voice.me", language: "en-US", quality: .premium, isPersonal: true),
        V(identifier: "com.apple.voice.compact.de-DE.Anna", language: "de-DE", quality: .standard),
        V(identifier: "com.apple.voice.enhanced.de-DE.Helena", language: "de-DE", quality: .enhanced),
    ]

    func testPicksHighestQualityExactRegionMatch() {
        XCTAssertEqual(SpeechVoicePicker.best(from: fixedVoices, language: "en-US")?.identifier,
                       "com.apple.voice.enhanced.en-US.Evan")
    }

    func testSkipsNoveltyAndPersonalVoices() {
        let picked = SpeechVoicePicker.best(from: fixedVoices, language: "en-US")
        XCTAssertEqual(picked?.isNovelty, false)
        XCTAssertEqual(picked?.isPersonal, false)
    }

    func testPremiumWinsWithinRegion() {
        XCTAssertEqual(SpeechVoicePicker.best(from: fixedVoices, language: "en-GB")?.identifier,
                       "com.apple.voice.premium.en-GB.Malcolm")
    }

    func testFallsBackToSameLanguageOtherRegion() {
        XCTAssertEqual(SpeechVoicePicker.best(from: fixedVoices, language: "en-AU")?.quality, .premium)
        XCTAssertEqual(SpeechVoicePicker.best(from: fixedVoices, language: "de-AT")?.identifier,
                       "com.apple.voice.enhanced.de-DE.Helena")
    }

    func testLanguageCodeFormsMatch() {
        XCTAssertEqual(SpeechVoicePicker.best(from: fixedVoices, language: "en_us")?.identifier,
                       "com.apple.voice.enhanced.en-US.Evan")
    }

    func testNoVoiceForUnknownLanguage() {
        XCTAssertNil(SpeechVoicePicker.best(from: fixedVoices, language: "ja-JP"))
        XCTAssertNil(SpeechVoicePicker.best(from: [], language: "en-US"))
    }

    func testTieBreakIsStable() {
        let a = V(identifier: "a", language: "en-US", quality: .enhanced)
        let b = V(identifier: "b", language: "en-US", quality: .enhanced)
        XCTAssertEqual(SpeechVoicePicker.best(from: [a, b], language: "en-US")?.identifier, "a")
        XCTAssertEqual(SpeechVoicePicker.best(from: [b, a], language: "en-US")?.identifier, "a")
    }

    func testStableHashIsDeterministic() {
        XCTAssertEqual(SpeechOutput.stableHash("Rest over"), SpeechOutput.stableHash("Rest over"))
        XCTAssertNotEqual(SpeechOutput.stableHash("Rest over"), SpeechOutput.stableHash("Rest over."))
    }

    func testRenderToFileWritesPlayableCafUnder30Seconds() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechOutputTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = SpeechOutput(language: "en-US", soundsDirectory: dir)

        let url = try await output.renderToFile("Rest over. Bench press, set 3 of 4: 185 for 5.")

        XCTAssertEqual(url.pathExtension, "caf")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL)
        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertGreaterThan(seconds, 0.5)
        XCTAssertLessThan(seconds, 30)
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 0)
    }

    func testFakeRecordsCalls() async throws {
        let fake = FakeSpeechOutput()
        fake.speak("What's next")
        fake.stop()
        let url = URL(fileURLWithPath: "/tmp/x.caf")
        fake.renderResult = .success(url)
        let rendered = try await fake.renderToFile("Rest over")
        XCTAssertEqual(fake.spoken, ["What's next"])
        XCTAssertEqual(fake.stopCount, 1)
        XCTAssertEqual(fake.rendered, ["Rest over"])
        XCTAssertEqual(rendered, url)
    }
}
