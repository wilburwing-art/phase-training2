import XCTest
@testable import PhaseTraining

/// Import-name resolution with punctuation folding, and the launch pass that
/// brings rows from an older import up to the current catalog and unit rule.
final class ImportMaintenanceTests: XCTestCase {

    func test_foldImportName() {
        XCTAssertEqual(CoachDatabase.foldImportName("Push-Up"), "push up")
        XCTAssertEqual(CoachDatabase.foldImportName("  Cable Pull-Through. "), "cable pull through")
        XCTAssertEqual(CoachDatabase.foldImportName("45° Back Extension"), "45 back extension")
    }

    func test_resolver_foldsPunctuation_andExactMatchesStillWin() throws {
        let coach = CoachDatabase.shared
        guard let pushUp = coach.exerciseId(forImportName: "Push-Up") else {
            throw XCTSkip("catalog has no Push-Up")
        }
        XCTAssertEqual(coach.exerciseId(forImportName: "Push Up"), pushUp, "Fitbod writes it without the hyphen")
        XCTAssertEqual(coach.exerciseId(forImportName: "push up"), pushUp)
        XCTAssertNil(coach.exerciseId(forImportName: "Zz Not An Exercise"))
    }

    func test_fitbodAliases_resolveTheStaples() throws {
        let coach = CoachDatabase.shared
        for name in ["Back Squat", "Deadlift", "Lat Pulldown", "Dumbbell Row", "Dumbbell Fly"] {
            XCTAssertNotNil(coach.exerciseId(forImportName: name), "\(name) should resolve")
        }
    }

    private func row(_ name: String, kg: Double, week: Int, id: Int? = nil) -> ImportedSet {
        let at = Date(timeIntervalSince1970: 1_500_000_000 + Double(week) * 7 * 86_400)
        return ImportedSet(id: "\(name)-\(week)", source: .fitbodCSV, exerciseId: id, exerciseNameRaw: name,
                           performedAt: at, setNum: 1, weight: kg, reps: 5, rir: nil, rpe: nil)
    }

    func test_run_rematchesNullIds_andIsANoOpTheSecondTime() throws {
        let coach = CoachDatabase.shared
        guard let squatId = coach.exerciseId(forImportName: "Back Squat") else { throw XCTSkip("no Back Squat") }
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets([row("Back Squat", kg: 225 * ImportUnitCorrection.kgPerLb, week: 1)])

        XCTAssertEqual(ImportMaintenance.run(db: db, coach: coach), 1)
        XCTAssertEqual(db.allImportedSets().first?.exerciseId, squatId)
        XCTAssertEqual(ImportMaintenance.run(db: db, coach: coach), 0)
    }

    func test_run_convertsAStoredPoundsInKgEra() {
        let kgPerLb = ImportUnitCorrection.kgPerLb
        let lifts: [String: Double] = ["Zz Bench": 180, "Zz Squat": 225, "Zz Row": 135]
        var rows: [ImportedSet] = []
        for w in 0..<5 { for (n, lb) in lifts { rows.append(row(n, kg: lb, week: w)) } }             // typed lb, stored as kg
        for w in 10..<15 { for (n, lb) in lifts { rows.append(row(n, kg: lb * kgPerLb, week: w)) } }  // stored properly
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets(rows)

        XCTAssertEqual(ImportMaintenance.run(db: db), 15)
        let early = db.allImportedSets().filter { $0.exerciseNameRaw == "Zz Bench" }.first
        XCTAssertEqual((early?.weight ?? 0) / kgPerLb, 180, accuracy: 0.01)
        XCTAssertEqual(ImportMaintenance.run(db: db), 0)
    }
}
