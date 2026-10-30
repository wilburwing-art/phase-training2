import XCTest
@testable import PhaseTraining

/// Imported sets show up in History, Progress and PR detection as read-only
/// sessions, without entering savedSessions.
final class ImportedHistorySessionsTests: XCTestCase {

    private let kgPerLb = ImportUnitCorrection.kgPerLb

    private func squat() throws -> (id: Int, name: String) {
        guard let id = CoachDatabase.shared.exerciseId(forImportName: "Back Squat"),
              let name = CoachDatabase.shared.exercise(id: id)?.name else { throw XCTSkip("no Back Squat") }
        return (id, name)
    }

    private func set(_ n: Int, id: Int?, raw: String = "Back Squat", at: Date, kg: Double?, reps: Int?) -> ImportedSet {
        ImportedSet(id: "fitbodCSV:\(Int(at.timeIntervalSince1970)):\(raw):\(n)", source: .fitbodCSV,
                    exerciseId: id, exerciseNameRaw: raw, performedAt: at, setNum: n,
                    weight: kg, reps: reps, rir: nil, rpe: nil)
    }

    private func store(imported: [ImportedSet] = [], saved: [SavedSession] = []) -> SessionStore {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets(imported)
        let s = SessionStore(defaults: UserDefaults(suiteName: "imported-history-\(UUID().uuidString)")!, userDB: db)
        if !saved.isEmpty { s.saveAll(saved) }
        return s
    }

    private func native(_ name: String, weight: String, reps: String, at: Date) -> SavedSession {
        SavedSession(templateId: "t", name: "Legs", category: "lift", startTime: at,
                     exercises: [LoggedExercise(id: "sq", name: name, type: nil, unit: "lbs",
                                                targetSets: 1, targetReps: Int(reps) ?? 5, rest: 120,
                                                sets: [LoggedSet(num: 1, weight: weight, reps: reps, rpe: "", done: true)],
                                                prevSets: [])],
                     feel: nil, note: nil, endTime: at.addingTimeInterval(1800), duration: 1800)
    }

    // MARK: - Builder

    func test_groupsByWorkout_convertsToPounds_andMarksTheSource() throws {
        let sq = try squat()
        let a = Date(timeIntervalSince1970: 1_700_000_000), b = a.addingTimeInterval(86_400)
        let rows = [
            set(1, id: sq.id, at: a, kg: 185 * kgPerLb, reps: 5),
            set(2, id: sq.id, at: a, kg: 185 * kgPerLb, reps: 5),
            set(1, id: nil, raw: "Mystery Machine", at: a, kg: 40, reps: 10),
            set(1, id: sq.id, at: b, kg: 190 * kgPerLb, reps: 5),
        ]
        let sessions = ImportedHistorySessions.build(imported: rows, excluded: [], usesImperial: true)
        XCTAssertEqual(sessions.map(\.startTime), [b, a], "newest first")
        XCTAssertEqual(sessions[1].exercises.map(\.name).sorted(), [sq.name, "Mystery Machine"].sorted())
        let squatEx = try XCTUnwrap(sessions[1].exercises.first { $0.name == sq.name })
        XCTAssertEqual(squatEx.sets.map(\.weight), ["185", "185"])
        XCTAssertEqual(squatEx.unit, "lbs")
        XCTAssertTrue(squatEx.sets.allSatisfy { $0.done && !$0.isWarmup })
        XCTAssertEqual(sessions[1].importSource, .fitbodCSV)
        XCTAssertEqual(sessions[1].name, "Fitbod workout")
        XCTAssertNil(native(sq.name, weight: "1", reps: "1", at: a).importSource)
    }

    func test_metric_keepsKilograms_andBodyweightRowsKeepReps() throws {
        let sq = try squat()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let rows = [set(1, id: sq.id, at: at, kg: 102.5, reps: 3),
                    set(1, id: nil, raw: "Pull Up", at: at, kg: nil, reps: 8),
                    set(1, id: nil, raw: "Rowing", at: at, kg: nil, reps: nil)]
        let s = ImportedHistorySessions.build(imported: rows, excluded: [], usesImperial: false)[0]
        XCTAssertEqual(s.exercises.first { $0.name == sq.name }?.sets.first?.weight, "102.5")
        let pullUp = try XCTUnwrap(s.exercises.first { $0.name == "Pull Up" })
        XCTAssertEqual(pullUp.unit, LoggedExercise.bodyweightUnit)
        XCTAssertEqual(pullUp.sets.first?.reps, "8")
        XCTAssertNil(s.exercises.first { $0.name == "Rowing" }, "a row with no reps has nothing to show")
    }

    func test_excludedSetsAreLeftOut() throws {
        let sq = try squat()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let keep = set(1, id: sq.id, at: at, kg: 100, reps: 5), typo = set(2, id: sq.id, at: at, kg: 400, reps: 5)
        let s = ImportedHistorySessions.build(imported: [keep, typo], excluded: [typo.id], usesImperial: false)
        XCTAssertEqual(s[0].exercises[0].sets.map(\.weight), ["100"])
    }

    // MARK: - Store

    func test_displaySessions_mixesImported_butSavedSessionsStayNative() throws {
        let sq = try squat()
        let old = Date().addingTimeInterval(-30 * 86_400)
        let s = store(imported: [set(1, id: sq.id, at: old, kg: 100, reps: 5)],
                      saved: [native(sq.name, weight: "225", reps: "5", at: Date().addingTimeInterval(-86_400))])
        XCTAssertEqual(s.savedSessions.count, 1)
        let shown = s.displaySessions(usesImperial: true)
        XCTAssertEqual(shown.count, 2)
        XCTAssertNil(shown[0].importSource)
        XCTAssertEqual(shown[1].importSource, .fitbodCSV)
    }

    func test_importedBestIsThePRBaseline() throws {
        let sq = try squat()
        let old = Date().addingTimeInterval(-60 * 86_400)
        let s = store(imported: [set(1, id: sq.id, at: old, kg: 185 * kgPerLb, reps: 5)])
        func ex(_ w: String) -> LoggedExercise {
            LoggedExercise(id: "sq", name: sq.name, type: nil, unit: "lbs", targetSets: 1, targetReps: 5, rest: 120,
                           sets: [LoggedSet(num: 1, weight: w, reps: "5", rpe: "", done: true)], prevSets: [])
        }
        XCTAssertTrue(s.personalRecords(in: [ex("185")]).isEmpty, "matching a Fitbod best is no PR")
        let pr = s.personalRecords(in: [ex("190")])
        XCTAssertEqual(pr.first?.weight, 190)
        XCTAssertEqual(pr.first?.previousBest, 185)
    }

    func test_prFeed_includesImported_andNativeMustBeatIt() throws {
        let sq = try squat()
        let old = Date().addingTimeInterval(-60 * 86_400)
        let s = store(imported: [set(1, id: sq.id, at: old, kg: 185 * kgPerLb, reps: 5)],
                      saved: [native(sq.name, weight: "185", reps: "5", at: Date().addingTimeInterval(-86_400))])
        let events = s.allPersonalRecords(usesImperial: true)
        XCTAssertEqual(events.count, 1, "the native 185 ties the imported best")
        XCTAssertEqual(events.first?.date.timeIntervalSince1970 ?? 0, old.timeIntervalSince1970, accuracy: 1)
    }

    func test_flaggedTypoIsNeverAPR() throws {
        let sq = try squat()
        // Three normal sets and one 1.6x outlier in the same workout.
        let at = Date().addingTimeInterval(-10 * 86_400)
        let rows = (1...3).map { set($0, id: sq.id, at: at, kg: 100, reps: 5) }
            + [set(4, id: sq.id, at: at, kg: 180, reps: 4)]
        let s = store(imported: rows)
        XCTAssertFalse(s.historyProfile.audit.flags.isEmpty)
        let weights = s.allPersonalRecords(usesImperial: false).map(\.weight)
        XCTAssertEqual(weights, [100])
    }
}
