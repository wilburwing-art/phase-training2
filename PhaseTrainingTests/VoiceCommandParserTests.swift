import XCTest
@testable import PhaseTraining

final class VoiceCommandParserTests: XCTestCase {

    private static let lift = VoiceContext()
    private static let bw = VoiceContext(isBodyweight: true)

    private static func set(_ w: Double?, _ r: Int, rpe: Double? = nil,
                            _ unit: VoiceUnit? = nil) -> VoiceCommand {
        .logSet(weight: w, reps: r, rpe: rpe, unit: unit)
    }

    private typealias Fixture = (String, VoiceContext, VoiceCommand?)

    // MARK: - Fixtures by rule

    private static let normalize: [Fixture] = [
        ("185x5", lift, set(185, 5)),
        ("185X5", lift, set(185, 5)),
        ("185 × 5", lift, set(185, 5)),
        ("60kg for 5reps", lift, set(60, 5, .kg)),
        ("62.5 for 8", lift, set(62.5, 8)),
        ("60,5 x 8", lift, set(60.5, 8)),
        ("1,250.5 for 1", lift, set(1250.5, 1)),
        ("185 for 8.5", lift, nil),
        ("eight and a half reps", lift, nil),
        ("  Done.  ", lift, .completeSet),
        ("Done!", lift, .completeSet),
        ("what's next", lift, .whatsNext),
        ("What\u{2019}s next?", lift, .whatsNext),
        ("I'm ready", lift, .skipRest),
        ("two twenty-five for five", lift, set(225, 5)),
        ("same, again", lift, .sameAgain),
        ("", lift, nil),
        ("   ", lift, nil),
        ("?!.", lift, nil),
    ]

    private static let refuse: [Fixture] = [
        ("finish workout", lift, nil),
        ("end rest", lift, nil),
        ("delete that set", lift, nil),
        ("remove set", lift, nil),
        ("cancel", lift, nil),
        ("stop timer", lift, nil),
        ("reset", lift, nil),
        ("185 for 5 then finish", lift, nil),
        ("skip and end", lift, nil),
        ("abandon workout", lift, nil),
        ("clear", lift, nil),
        ("restart rest", lift, nil),
    ]

    private static let fillers: [Fixture] = [
        ("uh done", lift, .completeSet),
        ("okay skip rest please", lift, .skipRest),
        ("um so like 185 for 5", lift, set(185, 5)),
        ("hey whats next", lift, .whatsNext),
        ("ok", lift, nil),
        ("yeah alright then", lift, nil),
    ]

    private static let fixedPhrases: [Fixture] = [
        ("same again", lift, .sameAgain),
        ("same", lift, .sameAgain),
        ("again", lift, .sameAgain),
        ("same as last time", lift, .sameAgain),
        ("same as before", lift, .sameAgain),
        ("repeat that", lift, .sameAgain),
        ("same thing", lift, .sameAgain),
        ("one more", lift, .sameAgain),
        ("done", lift, .completeSet),
        ("set done", lift, .completeSet),
        ("got it", lift, .completeSet),
        ("set complete", lift, .completeSet),
        ("check", lift, .completeSet),
        ("skip", lift, .skipRest),
        ("skip rest", lift, .skipRest),
        ("skip the timer", lift, .skipRest),
        ("ready", lift, .skipRest),
        ("next", lift, .whatsNext),
        ("what is next", lift, .whatsNext),
        ("whats up next", lift, .whatsNext),
        ("what now", lift, .whatsNext),
        ("next exercise", lift, .whatsNext),
        ("how many left", lift, .setsLeft),
        ("how many sets left", lift, .setsLeft),
        ("sets left", lift, .setsLeft),
        ("how many to go", lift, .setsLeft),
        ("how many remaining", lift, .setsLeft),
        ("undo", lift, .undo),
        ("scratch that", lift, .undo),
        ("take that back", lift, .undo),
        ("go back", lift, .undo),
        ("oops", lift, .undo),
        ("done done", lift, nil),
        ("hello", lift, nil),
        ("go to next", bw, nil),
    ]

    private static let addRest: [Fixture] = [
        ("add fifteen", lift, .addRest(seconds: 15)),
        ("add 30", lift, .addRest(seconds: 30)),
        ("add 30 seconds", lift, .addRest(seconds: 30)),
        ("plus 15", lift, .addRest(seconds: 15)),
        ("20 more seconds", lift, .addRest(seconds: 20)),
        ("give me thirty more", lift, .addRest(seconds: 30)),
        ("give me 30 more seconds", lift, .addRest(seconds: 30)),
        ("add a minute", lift, .addRest(seconds: 60)),
        ("add 2 minutes", lift, .addRest(seconds: 120)),
        ("add one minute", lift, .addRest(seconds: 60)),
        ("add half a minute", lift, .addRest(seconds: 30)),
        ("add ninety", lift, .addRest(seconds: 90)),
        ("add one twenty", lift, .addRest(seconds: 120)),
        ("add 600", lift, .addRest(seconds: 600)),
        ("add 900", lift, nil),
        ("add 11 minutes", lift, nil),
        ("add 0", lift, nil),
        ("add", lift, nil),
        ("add some", lift, nil),
        ("give me five", lift, nil),
        ("add 15.5", lift, nil),
        ("30 seconds", bw, nil),
    ]

    private static let numbers: [Fixture] = [
        ("one eighty five for five", lift, set(185, 5)),
        ("two twenty five for five", lift, set(225, 5)),
        ("three fifteen for three", lift, set(315, 3)),
        ("one oh five for eight", lift, set(105, 8)),
        ("one twenty for ten", lift, set(120, 10)),
        ("ninety five for twelve", lift, set(95, 12)),
        ("forty five for fifteen", lift, set(45, 15)),
        ("a hundred and five for eight", lift, set(105, 8)),
        ("a hundred for five", lift, set(100, 5)),
        ("two hundred for three", lift, set(200, 3)),
        ("one hundred twenty five for six", lift, set(125, 6)),
        ("sixty point five for ten", lift, set(60.5, 10)),
        ("sixty two point five for eight", lift, set(62.5, 8)),
        ("eight and a half for twelve", lift, set(8.5, 12)),
        ("won twenty for ate", lift, set(120, 8)),
        ("to twenty five for five", lift, set(225, 5)),
        ("185 for to", lift, set(185, 2)),
        ("185 to 5", lift, nil),
        ("one eighty five five", lift, nil),
        ("185 five", lift, nil),
        ("twelve twenty five for five", lift, nil),
    ]

    private static let logSet: [Fixture] = [
        ("185 for 5", lift, set(185, 5)),
        ("185 by 5", lift, set(185, 5)),
        ("185 times 5", lift, set(185, 5)),
        ("185 x 5", lift, set(185, 5)),
        ("185 four 5", lift, set(185, 5)),
        ("185 fore 5", lift, set(185, 5)),
        ("one eighty five four five", lift, set(185, 5)),
        ("185 for four", lift, set(185, 4)),
        ("one eighty five by five at RPE 8", lift, set(185, 5, rpe: 8)),
        ("185 for 5 rpe 7.5", lift, set(185, 5, rpe: 7.5)),
        ("185 for 5 r p e 9", lift, set(185, 5, rpe: 9)),
        ("185 for 5 rp eight", lift, set(185, 5, rpe: 8)),
        ("185 for 5 at rpe eight and a half", lift, set(185, 5, rpe: 8.5)),
        ("185 for 5 reps at rpe 6", lift, set(185, 5, rpe: 6)),
        ("100 kilos for 5", lift, set(100, 5, .kg)),
        ("185 pounds for 5", lift, set(185, 5, .lb)),
        ("185 for 5 pounds", lift, set(185, 5, .lb)),
        ("80 kg for 5 reps", lift, set(80, 5, .kg)),
        ("185 lbs x 5 at rpe 8", lift, set(185, 5, rpe: 8, .lb)),
        ("bench 185 for 5", lift, set(185, 5)),
        ("squat one eighty five for five", lift, set(185, 5)),
        ("12 reps", lift, set(nil, 12)),
        ("twelve reps rpe 9", lift, set(nil, 12, rpe: 9)),
        ("wait for 5", lift, set(nil, 5)),
        ("weight for 5", lift, set(nil, 5)),
        ("same weight for 5", lift, set(nil, 5)),
        ("same weight for five reps", lift, set(nil, 5)),
        ("twelve", bw, set(nil, 12)),
        ("twelve", lift, nil),
        ("12 at rpe 8", bw, set(nil, 12, rpe: 8)),
        ("185 for 5", bw, set(185, 5)),
        ("185 5", lift, nil),
        ("185 4 5", lift, nil),
        ("185 for 5 for 3", lift, nil),
        ("185 for 5 at rpe 12", lift, nil),
        ("185 for 5 at rpe 0", lift, nil),
        ("185 for 5 at rpe 7.3", lift, nil),
        ("185 for 5 rpe", lift, nil),
        ("5000 for 5", lift, nil),
        ("0 for 5", lift, nil),
        ("2000 for 1", lift, set(2000, 1)),
        ("185 for 500", lift, nil),
        ("185 for 0", lift, nil),
        ("185 kg for 5 pounds", lift, nil),
        ("12 kg", bw, nil),
        ("same for 5", lift, nil),
        ("for 5", lift, nil),
        ("185 for", lift, nil),
        ("one arm row 50 for 10", lift, nil),
    ]

    private static var all: [Fixture] {
        normalize + refuse + fillers + fixedPhrases + addRest + numbers + logSet
    }

    // MARK: - Tests

    func testFixtureCountMeetsFloor() {
        XCTAssertGreaterThanOrEqual(Self.all.count, 80)
    }

    func testNormalize() { run(Self.normalize) }
    func testRefuseWordsAreNil() { run(Self.refuse) }
    func testFillersDropped() { run(Self.fillers) }
    func testFixedPhrases() { run(Self.fixedPhrases) }
    func testAddRest() { run(Self.addRest) }
    func testNumberWords() { run(Self.numbers) }
    func testLogSetForms() { run(Self.logSet) }

    func testEveryCommandCaseIsReachable() {
        let produced = Self.all.compactMap { $0.2 }.map(Self.caseName)
        XCTAssertEqual(Set(produced), ["logSet", "sameAgain", "completeSet", "skipRest",
                                       "addRest", "whatsNext", "setsLeft", "undo"])
    }

    func testEveryRefusedWordReturnsNilInsideAnyCommand() {
        let refused = ["delete", "remove", "erase", "clear", "end", "ending", "finish", "finished",
                       "cancel", "discard", "quit", "stop", "reset", "restart", "abandon"]
        let carriers = ["185 for 5", "done", "skip rest", "add 30", "undo", "whats next"]
        for word in refused {
            for carrier in carriers {
                XCTAssertNil(VoiceCommand.parse("\(carrier) \(word)", context: Self.lift),
                             "\(carrier) \(word)")
                XCTAssertNil(VoiceCommand.parse("\(word) \(carrier)", context: Self.bw),
                             "\(word) \(carrier)")
            }
        }
    }

    func testLoggedSetsStayInsideBounds() {
        for (text, ctx, _) in Self.all {
            guard case .logSet(let w, let r, let rpe, _) = VoiceCommand.parse(text, context: ctx) else { continue }
            if let w { XCTAssertTrue(w > 0 && w <= 2000, text) }
            XCTAssertTrue((1...100).contains(r), text)
            if let rpe {
                XCTAssertTrue((1...10).contains(rpe), text)
                XCTAssertEqual(rpe * 2, (rpe * 2).rounded(), text)
            }
        }
    }

    func testAddRestStaysInsideBounds() {
        for n in [0, 1, 59, 600, 601, 1000] {
            let parsed = VoiceCommand.parse("add \(n)", context: Self.lift)
            if (1...600).contains(n) {
                XCTAssertEqual(parsed, .addRest(seconds: n), "add \(n)")
            } else {
                XCTAssertNil(parsed, "add \(n)")
            }
        }
    }

    // MARK: - Helpers

    private func run(_ fixtures: [Fixture], file: StaticString = #filePath, line: UInt = #line) {
        for (text, ctx, expected) in fixtures {
            XCTAssertEqual(VoiceCommand.parse(text, context: ctx), expected,
                           "\"\(text)\" bodyweight=\(ctx.isBodyweight)", file: file, line: line)
        }
    }

    private static func caseName(_ c: VoiceCommand) -> String {
        switch c {
        case .logSet: return "logSet"
        case .sameAgain: return "sameAgain"
        case .completeSet: return "completeSet"
        case .skipRest: return "skipRest"
        case .addRest: return "addRest"
        case .whatsNext: return "whatsNext"
        case .setsLeft: return "setsLeft"
        case .undo: return "undo"
        }
    }
}
