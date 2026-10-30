import XCTest
@testable import PhaseTraining

/// Hevy and Strong exports parse to kilogram sets, skip warm-ups, and are
/// detected by header. Fixtures follow the headers other apps' importers read
/// (see HevyStrongCSVParsers.swift).
final class HevyStrongCSVTests: XCTestCase {

    private let hevyKgHeader = #""title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe""#
    private let lb = ImportUnitCorrection.kgPerLb
    private func none(_: String) -> Int? { nil }

    // MARK: - Hevy

    func test_hevyKg_quotedCommas_warmupSkipped_rpeKept() {
        let csv = hevyKgHeader + "\n"
            + #""Push","8 Feb 2024, 12:16","8 Feb 2024, 13:00","","Bench Press (Barbell)","","felt good, solid","0","warmup","40","10","","","""# + "\n"
            + #""Push","8 Feb 2024, 12:16","8 Feb 2024, 13:00","","Bench Press (Barbell)","","felt good, solid","1","normal","80","5","","","8""# + "\n"
            + #""Push","8 Feb 2024, 12:16","8 Feb 2024, 13:00","","Bench Press (Barbell)","","","2","normal","82.5","5","","","""#
        let r = HevyCSVParser.parse(csv, nameResolver: none)
        XCTAssertEqual(r.errors.count, 0, "\(r.errors)")
        XCTAssertEqual(r.warmupsSkipped, 1)
        XCTAssertEqual(r.sets.map(\.weight), [80, 82.5])
        XCTAssertEqual(r.sets.map(\.setNum), [1, 2])
        XCTAssertEqual(r.sets.first?.rpe, 8)
        XCTAssertEqual(r.sets.first?.source, .hevyCSV)
    }

    func test_hevyPounds_andTwelveHourDates() throws {
        let csv = hevyKgHeader.replacingOccurrences(of: "weight_kg", with: "weight_lbs") + "\n"
            + #""Legs","Oct 17, 2026, 8:30 AM","Oct 17, 2026, 9:30 AM","","Squat (Barbell)","","","0","normal","225","5","","","""#
        let r = HevyCSVParser.parse(csv, nameResolver: none)
        let set = try XCTUnwrap(r.sets.first)
        XCTAssertEqual(set.weight ?? 0, 225 * lb, accuracy: 1e-9)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: set.performedAt)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 10, 17, 8, 30])
    }

    func test_hevyBodyweightAndBadDate() {
        let csv = hevyKgHeader + "\n"
            + #""Pull","8 Feb 2024, 12:16","","","Pull Up","","","0","normal","","8","","","""# + "\n"
            + #""Pull","sometime","","","Pull Up","","","1","normal","","8","","","""#
        let r = HevyCSVParser.parse(csv, nameResolver: none)
        XCTAssertEqual(r.sets.count, 1)
        XCTAssertNil(r.sets.first?.weight)
        XCTAssertEqual(r.errors.count, 1)
    }

    // MARK: - Strong

    func test_strongComma_noUnit_usesFallback_andSkipsW() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2024-08-01 18:23:30,Evening,45m,Deadlift (Barbell),W,135,5,0,0,,,
        2024-08-01 18:23:30,Evening,45m,Deadlift (Barbell),1,315,3,0,0,,,8
        """
        let imperial = StrongCSVParser.parse(csv, fallbackImperial: true, nameResolver: none)
        XCTAssertEqual(imperial.unitSource, .assumed)
        XCTAssertEqual(imperial.result.warmupsSkipped, 1)
        XCTAssertEqual(imperial.result.sets.first?.weight ?? 0, 315 * lb, accuracy: 1e-9)
        XCTAssertEqual(imperial.result.sets.first?.rpe, 8)

        let metric = StrongCSVParser.parse(csv, fallbackImperial: false, nameResolver: none)
        XCTAssertEqual(metric.result.sets.first?.weight, 315)
    }

    func test_strongSemicolon_withWeightUnitColumn() {
        let csv = """
        Date;Workout Name;Exercise Name;Set Order;Weight;Reps;Distance;Seconds;Notes;Workout Notes;RPE;Weight Unit
        2024-08-01 18:23:30;Evening;Bench Press (Barbell);1;100;5;0;0;;;;kg
        2024-08-02 18:00:00;Morning;Bench Press (Barbell);1;225;5;0;0;;;;lbs
        """
        let r = StrongCSVParser.parse(csv, fallbackImperial: true, nameResolver: none)
        XCTAssertEqual(r.unitSource, .column)
        XCTAssertEqual(r.result.errors.count, 0, "\(r.result.errors)")
        XCTAssertEqual(r.result.sets[0].weight, 100)
        XCTAssertEqual(r.result.sets[1].weight ?? 0, 225 * lb, accuracy: 1e-9)
    }

    func test_strongKgSuffixHeader() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight (kg),Reps,Distance (m),Seconds,Notes,Workout Notes,RPE
        2024-08-01 18:23:30,Evening,45m,Squat (Barbell),1,140,5,0,0,,,
        """
        let r = StrongCSVParser.parse(csv, fallbackImperial: true, nameResolver: none)
        XCTAssertEqual(r.unitSource, .header)
        XCTAssertEqual(r.result.sets.first?.weight, 140)
    }

    // MARK: - Detection and import

    func test_detectsEachFormat() {
        XCTAssertEqual(WorkoutCSVImporter.detectSource(headerLine: FitbodCSVParser.expectedHeader), .fitbodCSV)
        XCTAssertEqual(WorkoutCSVImporter.detectSource(headerLine: hevyKgHeader), .hevyCSV)
        XCTAssertEqual(WorkoutCSVImporter.detectSource(headerLine: "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE"), .strongCSV)
        XCTAssertEqual(WorkoutCSVImporter.detectSource(headerLine: "Date;Workout Name;Exercise Name;Set Order;Weight;Reps;Distance;Seconds;Notes;Workout Notes;RPE;Weight Unit"), .strongCSV)
        XCTAssertNil(WorkoutCSVImporter.detectSource(headerLine: "Exercise,Date,Reps,Weight"))
    }

    func test_hevyImport_reachesTheHistoryProfile() throws {
        let db = UserDatabase(path: ":memory:")
        let day = { (d: Int) -> String in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM yyyy, HH:mm"
            return f.string(from: Date().addingTimeInterval(-Double(d) * 86_400))
        }
        let rows = (1...3).map { #""Legs","\#(day($0 * 3))","","","Squat (Barbell)","","","0","normal","100","5","","","""# }
        let result = try WorkoutCSVImporter.run(csv: ([hevyKgHeader] + rows).joined(separator: "\n"), source: .hevyCSV, db: db)
        XCTAssertEqual(result.setsInserted, 3)
        XCTAssertEqual(result.source, .hevyCSV)
        let store = SessionStore(defaults: UserDefaults(suiteName: "hevy-\(UUID().uuidString)")!, userDB: db)
        XCTAssertNotNil(store.historyProfile.profile(forExerciseNamed: "Squat (Barbell)")?.estimate)
        XCTAssertEqual(store.importedSessions(usesImperial: false).first?.name, "Hevy workout")
    }
}
