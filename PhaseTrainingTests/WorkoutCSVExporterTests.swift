import XCTest
@testable import PhaseTraining

/// The Strong-format export: exact header, one row per done set, warm-ups
/// as "W", the lifter's unit, RFC 4180 quoting, and a round trip through
/// our own Strong importer.
final class WorkoutCSVExporterTests: XCTestCase {

    private let t = Date(timeIntervalSince1970: 1_750_000_000)

    private func s(_ n: Int, _ w: String, _ r: String, done: Bool = true, warm: Bool = false, rpe: String = "") -> LoggedSet {
        LoggedSet(num: n, weight: w, reps: r, rpe: rpe, done: done, setType: warm ? .warmup : .normal)
    }

    private func session(_ exercises: [LoggedExercise], note: String? = nil, start: Date? = nil) -> SavedSession {
        let start = start ?? t
        return SavedSession(templateId: "t", name: "Legs", category: "lift", startTime: start, exercises: exercises,
                            feel: nil, note: note, endTime: start.addingTimeInterval(3120), duration: 3120)
    }

    private func ex(_ name: String, unit: String = "lbs", note: String? = nil, _ sets: [LoggedSet]) -> LoggedExercise {
        LoggedExercise(id: name, name: name, type: nil, unit: unit, targetSets: sets.count, targetReps: 5,
                       rest: 120, sets: sets, prevSets: [], note: note)
    }

    private func rows(_ csv: String) -> [[String]] {
        CSVRows.parse(csv, delimiter: ",").map(\.fields)
    }

    func test_headerAndOneRowPerDoneSet_withWarmupsAsW() {
        let csv = WorkoutCSVExporter.csv(sessions: [session([
            ex("Back Squat", [s(1, "135", "8", warm: true), s(2, "225", "5", rpe: "8"), s(3, "225", "5"),
                              s(4, "225", "5", done: false)])
        ])], usesImperial: true)
        let r = rows(csv)
        XCTAssertEqual(r[0].joined(separator: ","), WorkoutCSVExporter.header)
        XCTAssertEqual(r.count, 4, "header plus three done sets; the undone set is left out")
        XCTAssertEqual(r[1][4], "W")
        XCTAssertEqual(r[2][4], "1")
        XCTAssertEqual(r[3][4], "2", "working sets number from 1 after the warm-up")
        XCTAssertEqual(r[2][5], "225")
        XCTAssertEqual(r[2][11], "8")
        XCTAssertEqual(r[1][2], "52m")
    }

    func test_dropAndFailure_setOrderIsDAndF() {
        func typed(_ n: Int, _ t: SetType) -> LoggedSet {
            LoggedSet(num: n, weight: "100", reps: "5", rpe: "", done: true, setType: t)
        }
        let csv = WorkoutCSVExporter.csv(sessions: [session([
            ex("Bench Press", [typed(1, .normal), typed(2, .drop), typed(3, .failure), typed(4, .normal)])
        ])], usesImperial: true)
        let r = rows(csv)
        XCTAssertEqual(r.dropFirst().map { $0[4] }, ["1", "D", "F", "2"], "D and F rows do not consume a number")
    }

    func test_bodyweightWeightIsBlank_andKgConvertsForAPoundUser() {
        let csv = WorkoutCSVExporter.csv(sessions: [session([
            ex("Push-Up", unit: LoggedExercise.bodyweightUnit, [s(1, "", "20")]),
            ex("Deadlift", unit: "kg", [s(1, "100", "5")]),
        ])], usesImperial: true)
        let r = rows(csv)
        XCTAssertEqual(r[1][5], "")
        XCTAssertEqual(r[2][5], "220.5", "100 kg written in the lifter's pounds")
    }

    func test_notesQuoteAndLandOnTheFirstRowOnly() {
        let note = "seat 4, \"slow\"\nleft knee fine"
        let csv = WorkoutCSVExporter.csv(sessions: [session([
            ex("Leg Press", note: note, [s(1, "300", "10"), s(2, "300", "10")]),
        ], note: "felt good")], usesImperial: true)
        let r = rows(csv)
        XCTAssertEqual(r.count, 3, "the quoted newline does not split a row")
        XCTAssertEqual(r[1][9], note)
        XCTAssertEqual(r[1][10], "felt good")
        XCTAssertEqual(r[2][9], "")
        XCTAssertEqual(r[2][10], "")
    }

    func test_roundTripsThroughTheStrongImporter() {
        let sessions = [
            session([ex("Back Squat", [s(1, "135", "8", warm: true), s(2, "225", "5", rpe: "8")])],
                    start: t),
            session([ex("Bench Press", [s(1, "185", "5"), s(2, "185", "4")])], start: t.addingTimeInterval(86_400)),
        ]
        let csv = WorkoutCSVExporter.csv(sessions: sessions, usesImperial: true)
        let back = StrongCSVParser.parse(csv, fallbackImperial: true, nameResolver: { _ in nil })
        XCTAssertTrue(back.result.errors.isEmpty, "\(back.result.errors)")
        XCTAssertEqual(back.result.warmupsSkipped, 1)
        XCTAssertEqual(back.result.sets.map(\.exerciseNameRaw), ["Back Squat", "Bench Press", "Bench Press"])
        XCTAssertEqual(back.result.sets.map(\.reps), [5, 5, 4])
        let lbs = back.result.sets.compactMap(\.weight).map { ($0 / ImportUnitCorrection.kgPerLb).rounded() }
        XCTAssertEqual(lbs, [225, 185, 185])
        XCTAssertEqual(back.result.sets.first?.rpe, 8)
        XCTAssertEqual(Set(back.result.sets.map(\.performedAt)).count, 2, "two workouts come back as two")
    }

    func test_oldestSessionFirst() {
        let csv = WorkoutCSVExporter.csv(sessions: [
            session([ex("B", [s(1, "100", "5")])], start: t.addingTimeInterval(86_400)),
            session([ex("A", [s(1, "100", "5")])], start: t),
        ], usesImperial: true)
        XCTAssertEqual(rows(csv).dropFirst().map { $0[3] }, ["A", "B"])
    }
}
