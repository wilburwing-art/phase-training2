import XCTest
@testable import PhaseTraining

/// Loads the device accuracy gate script (`Fixtures/voice-gate.txt`, voice
/// backlog 2.7) and checks every scripted utterance parses to the command the
/// script says it means. A device miss then points at the recognizer, since
/// the parser is known to read the clean transcript right.
final class VoiceGateScriptTests: XCTestCase {

    private struct Line {
        let number: Int
        let transcript: String
        let intended: VoiceCommand
    }

    private func loadScript() throws -> [Line] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "voice-gate", withExtension: "txt"),
            "voice-gate.txt missing from the test bundle; run xcodegen generate"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines: [Line] = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            if raw.isEmpty || raw.hasPrefix("#") { continue }
            let columns = raw.components(separatedBy: "\t")
            XCTAssertEqual(columns.count, 2, "line \(index + 1) needs transcript<TAB>command: \(raw)")
            guard columns.count == 2 else { continue }
            let intended = try XCTUnwrap(Self.command(columns[1]),
                                         "line \(index + 1) has an unknown command: \(columns[1])")
            lines.append(Line(number: index + 1, transcript: columns[0], intended: intended))
        }
        return lines
    }

    /// `logSet <weight|-> <reps> [rpe=<n>] [lb|kg]`, `addRest <seconds>`, or a bare case name.
    private static func command(_ spec: String) -> VoiceCommand? {
        let parts = spec.split(separator: " ").map(String.init)
        guard let head = parts.first else { return nil }
        switch (head, parts.count) {
        case ("sameAgain", 1): return .sameAgain
        case ("completeSet", 1): return .completeSet
        case ("skipRest", 1): return .skipRest
        case ("whatsNext", 1): return .whatsNext
        case ("setsLeft", 1): return .setsLeft
        case ("undo", 1): return .undo
        case ("addRest", 2): return Int(parts[1]).map { .addRest(seconds: $0) }
        case ("logSet", 3...5):
            let weight: Double?
            if parts[1] == "-" { weight = nil } else {
                guard let w = Double(parts[1]) else { return nil }
                weight = w
            }
            guard let reps = Int(parts[2]) else { return nil }
            var rpe: Double?
            var unit: VoiceUnit?
            for extra in parts.dropFirst(3) {
                if extra.hasPrefix("rpe="), let v = Double(extra.dropFirst(4)), rpe == nil { rpe = v }
                else if extra == "lb", unit == nil { unit = .lb }
                else if extra == "kg", unit == nil { unit = .kg }
                else { return nil }
            }
            return .logSet(weight: weight, reps: reps, rpe: rpe, unit: unit)
        default:
            return nil
        }
    }

    func testEveryScriptedUtteranceParsesToItsIntendedCommand() throws {
        for line in try loadScript() {
            XCTAssertEqual(VoiceCommand.parse(line.transcript, context: VoiceContext()), line.intended,
                           "line \(line.number): \"\(line.transcript)\"")
        }
    }

    func testScriptHasOneHundredLinesOverEveryCommand() throws {
        let lines = try loadScript()
        XCTAssertEqual(lines.count, 100)

        var cases = Set<String>()
        for line in lines {
            switch line.intended {
            case .logSet: cases.insert("logSet")
            case .sameAgain: cases.insert("sameAgain")
            case .completeSet: cases.insert("completeSet")
            case .skipRest: cases.insert("skipRest")
            case .addRest: cases.insert("addRest")
            case .whatsNext: cases.insert("whatsNext")
            case .setsLeft: cases.insert("setsLeft")
            case .undo: cases.insert("undo")
            }
        }
        XCTAssertEqual(cases.count, 8, "cases covered: \(cases.sorted())")
    }

    func testAtLeastThirtyLoadsAreSpokenAsWords() throws {
        let spokenLoads = try loadScript().filter { line in
            guard case .logSet(.some, _, _, _) = line.intended else { return false }
            return !line.transcript.contains(where: \.isNumber)
        }
        XCTAssertGreaterThanOrEqual(spokenLoads.count, 30)
    }
}
