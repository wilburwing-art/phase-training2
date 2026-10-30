import XCTest
@testable import PhaseTraining

/// The log's weight boxes match the suggestion pill: history fills an
/// exercise never logged here, and a big rep change remaps the load.
final class SessionPrefillFromHistoryTests: XCTestCase {

    private func store(imported: [ImportedSet] = [], saved: [SavedSession] = []) -> SessionStore {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets(imported)
        let s = SessionStore(defaults: UserDefaults(suiteName: "prefill-\(UUID().uuidString)")!, userDB: db)
        if !saved.isEmpty { s.saveAll(saved) }
        return s
    }

    private func template(_ name: String, unit: String = "lbs", reps: Int) -> WorkoutTemplate {
        WorkoutTemplate(id: "t-\(UUID().uuidString)", name: "Today", category: "Generated", exercises: [
            ExerciseTemplate(id: "gex-1", name: name, type: nil, unit: unit, targetSets: 3, targetReps: reps, rest: 120)
        ])
    }

    private func squatImports() throws -> [ImportedSet] {
        guard let id = CoachDatabase.shared.exerciseId(forImportName: "Back Squat") else { throw XCTSkip("no Back Squat") }
        let at = Date().addingTimeInterval(-3 * 86_400)
        return (1...3).map {
            ImportedSet(id: "s\($0)", source: .fitbodCSV, exerciseId: id, exerciseNameRaw: "Back Squat",
                        performedAt: at, setNum: $0, weight: 100, reps: 5, rir: nil, rpe: nil)
        }
    }

    private func savedSquat(_ weight: String, reps: String) -> SavedSession {
        let start = Date().addingTimeInterval(-3 * 86_400)
        let sets = (1...3).map { LoggedSet(num: $0, weight: weight, reps: reps, rpe: "", done: true) }
        return SavedSession(templateId: "old", name: "Legs", category: "lift", startTime: start,
                            exercises: [LoggedExercise(id: "sq", name: "Back Squat", type: nil, unit: "lbs",
                                                       targetSets: 3, targetReps: Int(reps) ?? 5, rest: 120,
                                                       sets: sets, prevSets: [])],
                            feel: nil, note: nil, endTime: start.addingTimeInterval(3000), duration: 3000)
    }

    func test_importedOnly_fillsTheHistoryLoad() throws {
        let s = store(imported: try squatImports())
        let session = s.createSession(from: template("Back Squat", reps: 5))
        // 100 kg x 5 = 220.46 lb; mapped to 5 reps and snapped down -> 220.
        XCTAssertEqual(session.exercises[0].sets.map(\.weight), ["220", "220", "220"])
        XCTAssertEqual(session.exercises[0].sets.map(\.reps), ["5", "5", "5"])
    }

    func test_bigRepChange_remapsTheLoad_andUsesTodaysReps() {
        let s = store(saved: [savedSquat("185", reps: "10")])
        let session = s.createSession(from: template("Back Squat", reps: 5))
        // 185 x 10 -> e1RM 246.7 -> 211.4 at 5 reps -> 210.
        XCTAssertEqual(session.exercises[0].sets.first?.weight, "210")
        XCTAssertEqual(session.exercises[0].sets.first?.reps, "5")
    }

    func test_similarReps_keepLastSessionsSets() {
        let s = store(saved: [savedSquat("185", reps: "6")])
        let session = s.createSession(from: template("Back Squat", reps: 5))
        XCTAssertEqual(session.exercises[0].sets.first?.weight, "185")
        XCTAssertEqual(session.exercises[0].sets.first?.reps, "6")
    }

    func test_noHistory_staysEmpty_andBodyweightIsNeverFilled() throws {
        XCTAssertEqual(store().createSession(from: template("Back Squat", reps: 5)).exercises[0].sets.first?.weight, "")
        let s = store(imported: try squatImports())
        let bw = s.createSession(from: template("Back Squat", unit: LoggedExercise.bodyweightUnit, reps: 5))
        XCTAssertEqual(bw.exercises[0].sets.first?.weight, "")
    }
}
