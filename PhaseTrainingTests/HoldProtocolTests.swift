import XCTest
@testable import PhaseTraining

/// Timed prescriptions read into what the hold timer runs, and the text
/// survives from the prescription to Log.
final class HoldProtocolTests: XCTestCase {

    func test_shapes() {
        XCTAssertEqual(HoldProtocol.parse("8s hold"), HoldProtocol(onSeconds: 8))
        XCTAssertEqual(HoldProtocol.parse("45-90s hold"), HoldProtocol(onSeconds: 45), "a range takes its low end")
        XCTAssertEqual(HoldProtocol.parse("7-10 sec"), HoldProtocol(onSeconds: 7))
        XCTAssertEqual(HoldProtocol.parse("45 sec hold"), HoldProtocol(onSeconds: 45))
        XCTAssertEqual(HoldProtocol.parse("30-60s"), HoldProtocol(onSeconds: 30))
        XCTAssertEqual(HoldProtocol.parse("20-45 sec per side"), HoldProtocol(onSeconds: 20, perSide: true))
        XCTAssertEqual(HoldProtocol.parse("5-10 sec per arm")?.hangsPerSet, 2)
        XCTAssertEqual(HoldProtocol.parse("6 hangs (7s on / 3s off)"),
                       HoldProtocol(onSeconds: 7, offSeconds: 3, reps: 6))
        XCTAssertEqual(HoldProtocol.parse("30s on / 30s off"), HoldProtocol(onSeconds: 30, offSeconds: 30))
        XCTAssertEqual(HoldProtocol.parse("8-10 x 5 sec"), HoldProtocol(onSeconds: 5, reps: 8))
        XCTAssertEqual(HoldProtocol.parse("8-6-4 x 10 sec holds per side"),
                       HoldProtocol(onSeconds: 10, reps: 8, perSide: true))
    }

    func test_notTimed() {
        for s in ["8", "8-10", "AMRAP", "3-4 pulls per hand", "3 min", "30-90 min", "5 reps", ""] {
            XCTAssertNil(HoldProtocol.parse(s), s)
        }
        XCTAssertNil(HoldProtocol.parse(nil))
    }

    /// Every timed rep string the catalog ships parses, except durations in
    /// minutes (cardio blocks, not holds).
    func test_everyTimedCatalogStringParses() {
        let timed = Set(CoachDatabase.shared.listExercises().compactMap(\.defaultReps)).filter { s in
            let l = s.lowercased()
            // A time unit right after a number: "30 sec", "8s hold", "60s".
            // Plurals like "15 swings" or "3-5 reps" are counts, not time.
            let timeUnit = l.range(of: #"\d\s*(s|sec|secs|seconds)\b"#, options: .regularExpression) != nil
            return timeUnit && !l.contains("min") && l.first?.isNumber == true
        }
        XCTAssertGreaterThan(timed.count, 20, "catalog sweep found too few timed strings: \(timed.count)")
        for s in timed.sorted() {
            XCTAssertNotNil(HoldProtocol.parse(s), "'\(s)' is timed in the catalog but did not parse")
        }
    }

    func test_labelSurvivesToLog_andPlainCountsCarryNothing() {
        XCTAssertEqual(ExerciseTemplate(id: "a", name: "Max Hang", type: nil, unit: "bw", targetSets: 5, targetReps: 8,
                                        rest: 120, repsLabel: "8s hold").repsLabel, "8s hold")
        XCTAssertNil(ExerciseTemplate(id: "b", name: "Squat", type: nil, unit: "lbs", targetSets: 3, targetReps: 5,
                                      rest: 120, repsLabel: "4-6").repsLabel)
        let db = UserDatabase(path: ":memory:")
        let store = SessionStore(defaults: UserDefaults(suiteName: "hold-\(UUID().uuidString)")!, userDB: db)
        let session = store.createSession(from: WorkoutTemplate(id: "t", name: "Fingers", category: "Generated", exercises: [
            ExerciseTemplate(id: "h", name: "Hangboard Max Hang (20mm Edge)", type: nil, unit: "bw",
                             targetSets: 5, targetReps: 8, rest: 120, repsLabel: "8s hold")
        ]))
        XCTAssertEqual(session.exercises[0].repsLabel, "8s hold")
    }

    func test_oldPayloadsDecodeWithoutTheLabel() throws {
        let t = #"{"id":"a","name":"Row","unit":"lbs","targetSets":3,"targetReps":8,"rest":90}"#
        XCTAssertNil(try JSONDecoder().decode(ExerciseTemplate.self, from: Data(t.utf8)).repsLabel)
    }
}
