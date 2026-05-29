// FitbodCSVParserTests.swift — Phase 3 v1 parser smoke + edge cases.
//
// Drives the parser against a hand-written fixture mirroring the real
// 5,441-row export's quirks: leading-space-padded fields, mixed warmup
// rows, a cardio (Running) row, and an unmatched exercise name. Date
// format is the literal `+0000` offset Fitbod emits.

import XCTest
@testable import PhaseTraining

final class FitbodCSVParserTests: XCTestCase {

    // MARK: - Helpers

    /// Stub resolver: knows three names from the fixture, returns nil for
    /// the rest. Mirrors what CoachDatabase would do in production
    /// without coupling the test to coach.db state.
    private let stubResolver: (String) -> Int? = { name in
        switch name.lowercased() {
        case "barbell bench press": return 100
        case "pull up": return 101
        case "back squat": return 102
        default: return nil
        }
    }

    private func loadFixture() throws -> String {
        guard let url = Bundle(for: Self.self).url(forResource: "fitbod-sample", withExtension: "csv") else {
            // Fallback for environments where Resources/ wasn't bundled
            // into the test target — read from disk.
            let here = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/fitbod-sample.csv")
            return try String(contentsOf: here, encoding: .utf8)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Tests

    func testHeaderMismatchSurfacesError() {
        let bad = "Wrong,Header,Layout\n2026-01-01,Foo, 5,50,0,0,0,0,false,, 1"
        let result = FitbodCSVParser.parse(bad, nameResolver: stubResolver)
        XCTAssertEqual(result.sets.count, 0)
        XCTAssertEqual(result.workouts.count, 0)
        XCTAssertEqual(result.totalRows, 0)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].reason.contains("header"))
    }

    func testGoldenFixtureParsesExpectedCounts() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)

        // 11 data rows total. 1 warmup (skipped from sets but counted in
        // totalRows). 1 cardio (Running). So 9 strength sets expected.
        XCTAssertEqual(result.totalRows, 11)
        XCTAssertEqual(result.sets.count, 9)
        XCTAssertEqual(result.workouts.count, 1)
        XCTAssertTrue(result.errors.isEmpty, "unexpected parse errors: \(result.errors)")
    }

    func testSetNumberingWithinWorkoutAndExercise() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)

        // Bench Press: 1 warmup (skipped), then 3 working sets.
        let bench = result.sets.filter { $0.exerciseNameRaw == "Barbell Bench Press" }
        XCTAssertEqual(bench.count, 3)
        XCTAssertEqual(bench.map(\.setNum), [1, 2, 3])
        XCTAssertEqual(bench.map(\.reps), [8, 8, 6])
        XCTAssertEqual(bench.map(\.weight), [80.0, 80.0, 82.5])

        // Back Squat: 3 working sets, no warmups in fixture.
        let squat = result.sets.filter { $0.exerciseNameRaw == "Back Squat" }
        XCTAssertEqual(squat.count, 3)
        XCTAssertEqual(squat.map(\.setNum), [1, 2, 3])
    }

    func testBodyweightSetsHaveNilWeight() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        let pullups = result.sets.filter { $0.exerciseNameRaw == "Pull Up" }
        XCTAssertEqual(pullups.count, 2)
        for set in pullups {
            XCTAssertNil(set.weight, "bodyweight rows should land with weight=nil")
            XCTAssertNotNil(set.reps)
        }
    }

    func testCardioRowEmitsWorkoutNotSet() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        XCTAssertEqual(result.workouts.count, 1)
        let cardio = result.workouts[0]
        XCTAssertEqual(cardio.kind, .cardio)
        XCTAssertEqual(cardio.duration, 1200.0)
        XCTAssertEqual(cardio.source, .fitbodCSV)
    }

    func testUnmatchedNamePreservedWithNilExerciseId() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        let unmatched = result.sets.first { $0.exerciseNameRaw == "Unmatched Exercise Name" }
        XCTAssertNotNil(unmatched, "unmatched-name row should still produce an ImportedSet")
        XCTAssertNil(unmatched?.exerciseId, "unmatched name should leave exerciseId=nil")
    }

    func testNameMatchRateReflectsResolver() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        // 4 distinct strength names: Barbell Bench Press, Pull Up, Back
        // Squat (3 resolved) + Unmatched Exercise Name (not resolved).
        // Cardio row (Running) doesn't add a strength name. Warmup row
        // doesn't introduce a new name since Bench Press is already
        // counted.
        XCTAssertEqual(result.nameMatchRate, 0.75, accuracy: 0.001)
    }

    func testStableIdsAreDeterministic() throws {
        let csv = try loadFixture()
        let a = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        let b = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        XCTAssertEqual(a.sets.map(\.id), b.sets.map(\.id),
                       "re-parsing the same CSV must yield identical row ids so re-imports are idempotent")
    }

    func testWarmupRowsDoNotAppearInSets() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        // The fixture has 1 warmup row. All set rows must be non-warmup;
        // we don't store an isWarmup flag on ImportedSet (warmups are
        // simply skipped at parse time).
        XCTAssertEqual(result.sets.count, 9)
    }

    func testDateParsedAtUTC() throws {
        let csv = try loadFixture()
        let result = FitbodCSVParser.parse(csv, nameResolver: stubResolver)
        let first = result.sets.first!
        // 2026-01-15 18:30:00 +0000 → check via UTC components.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: first.performedAt)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 18)
    }
}
