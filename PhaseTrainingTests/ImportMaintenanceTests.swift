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

    func test_tokenSetImportName_ignoresOrderAndPlurals() {
        XCTAssertEqual(CoachDatabase.tokenSetImportName("Machine Hip Adductor"),
                       CoachDatabase.tokenSetImportName("Hip Adductor (Machine)"))
        XCTAssertEqual(CoachDatabase.tokenSetImportName("Cable Rope Hammer Curls"), "cable curl hammer rope")
        XCTAssertEqual(CoachDatabase.tokenSetImportName("Bench Press"), "bench press", "a double s is not a plural")
    }

    /// Fitbod's word order, measured against a real 2016-2025 export: each of
    /// these was listed as unmatched before the word-set tier existed.
    func test_resolver_matchesFitbodWordOrder() throws {
        let coach = CoachDatabase.shared
        let pairs = [
            ("Machine Hip Adductor", "Hip Adductor (Machine)"),
            ("Machine Hip Abductor", "Hip Abductor (Machine)"),
            ("Machine Shoulder Press", "Shoulder Press (Machine)"),
            ("Machine Squat", "Squat (Machine)"),
            ("Single Arm Lat Pulldown", "Lat Pulldown (Single Arm)"),
        ]
        for (fitbod, catalog) in pairs {
            guard let want = coach.exerciseId(forImportName: catalog) else {
                throw XCTSkip("catalog has no \(catalog)")
            }
            XCTAssertEqual(coach.exerciseId(forImportName: fitbod), want, "\(fitbod) -> \(catalog)")
        }
        XCTAssertNil(coach.exerciseId(forImportName: "Machine Zz Press"), "extra words still miss")
    }

    /// Fitbod names with a same-movement, same-equipment catalog row under a
    /// different name. Variants (Decline Push Up, Wide Grip Pull Up, Incline
    /// Hammer Curl) are deliberately left unmatched for the user to pick.
    func test_fitbodAliases_resolveRenamedMovements() {
        let coach = CoachDatabase.shared
        let expected = [
            ("Air Squats", 1088), ("Floor Press", 903), ("Side Lunge", 227),
            ("Dumbbell Bent Over Reverse Fly", 344), ("Cable Rope Hammer Curls", 1133),
            ("Machine Bench Press", 1004), ("Seated Machine Calf Press", 942),
            ("Alternating Dumbbell Bench Press", 14),
        ]
        for (name, id) in expected {
            XCTAssertEqual(coach.exerciseId(forImportName: name), id, name)
        }
        XCTAssertNil(coach.exerciseId(forImportName: "Decline Push Up"), "a harder variant is not Push-Up")
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
