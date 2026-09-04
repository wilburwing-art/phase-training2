import XCTest
@testable import PhaseTraining

/// T1-47: the sanitizer used to keep only the LAST sentence of any reply over
/// 140 characters, so a well-formed "observation, then takeaway" insight was
/// reduced to the takeaway with its evidence stripped. Nothing pinned the fix.
@MainActor
final class InsightGeneratorSanitizeTests: XCTestCase {

    func test_twoSentenceInsightUnder280IsKeptWhole() {
        let raw = "You squatted three times this week, up from once last week. Add one back-off set next session."
        XCTAssertEqual(InsightGenerator.sanitize(raw), raw)
        XCTAssertTrue(InsightGenerator.sanitize(raw).contains("three times"), "the observation must survive")
    }

    func test_quotesAndWhitespaceAreStripped() {
        let raw = "  \u{201C}Nice consistency this week.\u{201D}  "
        XCTAssertEqual(InsightGenerator.sanitize(raw), "Nice consistency this week.")
        XCTAssertEqual(InsightGenerator.sanitize("\"Quoted.\""), "Quoted.")
    }

    func test_over280TrimsAtASentenceBoundaryNeverMidWord() {
        let s1 = String(repeating: "Observation ", count: 12).trimmingCharacters(in: .whitespaces) + "."   // ~143
        let s2 = String(repeating: "Takeaway ", count: 12).trimmingCharacters(in: .whitespaces) + "."      // ~119
        let s3 = String(repeating: "Overflow ", count: 12).trimmingCharacters(in: .whitespaces) + "."      // pushes past 280
        let raw = [s1, s2, s3].joined(separator: " ")
        XCTAssertGreaterThan(raw.count, 280, "fixture must exceed the budget")
        let out = InsightGenerator.sanitize(raw)
        XCTAssertLessThanOrEqual(out.count, 280)
        XCTAssertTrue(out.hasPrefix("Observation"), "the first sentence is the evidence and must be kept")
        XCTAssertFalse(out.contains("Overflow"), "the sentence that breaks the budget is dropped whole")
        XCTAssertFalse(out.hasSuffix(" "), "never ends mid-word / on whitespace")
    }

    func test_singleSentenceOver280FallsBackToPrefix() {
        let raw = String(repeating: "word ", count: 80)   // 400 chars, no terminator
        let out = InsightGenerator.sanitize(raw)
        XCTAssertEqual(out.count, 280)
    }
}
