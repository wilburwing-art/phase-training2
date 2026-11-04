import XCTest
@testable import PhaseTraining

/// Per-exercise notes: saved with the session, carried to the next session
/// as "Last time", and imported from Hevy's exercise_notes.
final class ExerciseNoteTests: XCTestCase {

    private let hevyHeader = #""title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe""#

    private func session(_ note: String?, start: Date, name: String = "Back Squat") -> SavedSession {
        let ex = LoggedExercise(id: "sq", name: name, type: nil, unit: "lbs", targetSets: 1, targetReps: 5, rest: 120,
                                sets: [LoggedSet(num: 1, weight: "225", reps: "5", rpe: "", done: true)],
                                prevSets: [], note: note)
        return SavedSession(templateId: "old", name: "Legs", category: "lift", startTime: start, exercises: [ex],
                            feel: nil, note: nil, endTime: start.addingTimeInterval(3000), duration: 3000)
    }

    func test_noteRoundTripsThroughSQLite_andBlankStaysNil() throws {
        let db = UserDatabase(path: ":memory:")
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertTrue(db.saveSession(session("seat 4", start: t)))
        XCTAssertTrue(db.saveSession(session("   ", start: t.addingTimeInterval(86_400))))
        let notes = db.listSavedSessions().sorted { $0.startTime < $1.startTime }.map { $0.exercises[0].note }
        XCTAssertEqual(notes, ["seat 4", nil])
        XCTAssertEqual(UserDatabase.latestSchemaVersion, 6)
    }

    func test_oldPayloadWithoutNoteDecodes() throws {
        let json = #"{"id":"e","name":"Row","unit":"lbs","targetSets":3,"targetReps":8,"rest":90,"sets":[],"prevSets":[]}"#
        let ex = try JSONDecoder().decode(LoggedExercise.self, from: Data(json.utf8))
        XCTAssertNil(ex.note)
        XCTAssertNil(ex.lastNote)
    }

    func test_nextSessionCarriesTheNewestNote() {
        let db = UserDatabase(path: ":memory:")
        let store = SessionStore(defaults: UserDefaults(suiteName: "note-\(UUID().uuidString)")!, userDB: db)
        store.saveAll([session("seat 3", start: Date().addingTimeInterval(-9 * 86_400)),
                       session("seat 4", start: Date().addingTimeInterval(-2 * 86_400))])
        let next = store.createSession(from: WorkoutTemplate(id: "new", name: "Today", category: "Generated", exercises: [
            ExerciseTemplate(id: "gex-1", name: "Back Squat", type: nil, unit: "lbs", targetSets: 3, targetReps: 5, rest: 120)
        ]))
        XCTAssertEqual(next.exercises[0].lastNote, "seat 4")
        XCTAssertNil(next.exercises[0].note, "this session starts without a note of its own")
    }

    func test_hevyNotesImport_andFeedLastTimeForAnExerciseNeverLoggedHere() {
        let csv = hevyHeader + "\n"
            + #""Legs","8 Feb 2024, 12:16","8 Feb 2024, 13:00","","Goblet Squat","","heel wedge, slow down","0","normal","24","10","","","""#
        let r = HevyCSVParser.parse(csv, nameResolver: { _ in nil })
        XCTAssertEqual(r.sets.first?.note, "heel wedge, slow down", "a quoted comma stays in the note")

        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets(r.sets)
        XCTAssertEqual(db.lastExerciseNote(name: "Goblet Squat", exerciseId: nil), "heel wedge, slow down")
        XCTAssertNil(db.lastExerciseNote(name: "Bench Press", exerciseId: nil))
    }

    func test_inAppNoteWinsOverAnImportedOne() {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets([ImportedSet(id: "h1", source: .hevyCSV, exerciseId: nil, exerciseNameRaw: "Back Squat",
                                           performedAt: Date(), setNum: 1, weight: 100, reps: 5, rir: nil, rpe: nil,
                                           note: "imported")])
        XCTAssertTrue(db.saveSession(session("logged here", start: Date().addingTimeInterval(-86_400))))
        XCTAssertEqual(db.lastExerciseNote(name: "Back Squat", exerciseId: nil), "logged here")
    }
}
