import XCTest
@testable import PhaseTraining

/// A hand-made match for an unmatched imported name fills its rows, persists
/// past clearing imports, and resolves re-imports and ImportMaintenance.
final class ImportNameMapTests: XCTestCase {

    private func set(_ n: Int, raw: String, id: Int?) -> ImportedSet {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        return ImportedSet(id: ImportedSet.makeId(source: .fitbodCSV, performedAt: at, exerciseNameRaw: raw, setNum: n),
                           source: .fitbodCSV, exerciseId: id, exerciseNameRaw: raw, performedAt: at,
                           setNum: n, weight: 50, reps: 8, rir: nil, rpe: nil)
    }

    func test_matchFillsOnlyUnmatchedRows_andListsWhatsLeft() {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets([set(1, raw: "Mystery", id: nil), set(2, raw: "Mystery", id: nil),
                               set(1, raw: "Other", id: nil), set(1, raw: "Known", id: 7)])
        XCTAssertEqual(db.unmatchedImportNames().map(\.name), ["Mystery", "Other"])
        XCTAssertEqual(db.unmatchedImportNames().first?.sets, 2)

        db.setImportName("Mystery", exerciseId: 42)
        let byName = Dictionary(grouping: db.allImportedSets(), by: \.exerciseNameRaw)
        XCTAssertEqual(byName["Mystery"]?.map(\.exerciseId), [42, 42])
        XCTAssertEqual(byName["Known"]?.first?.exerciseId, 7)
        XCTAssertEqual(db.unmatchedImportNames().map(\.name), ["Other"])
    }

    func test_mapSurvivesClearingImports_butNotWipeAll() {
        let db = UserDatabase(path: ":memory:")
        db.setImportName("Mystery", exerciseId: 42)
        db.clearAllImports()
        XCTAssertEqual(db.importNameMap(), ["Mystery": 42])
        db.wipeAll()
        XCTAssertTrue(db.importNameMap().isEmpty)
    }

    func test_notALift_leavesTheList_undoBringsItBack_wipeClearsIt() {
        let db = UserDatabase(path: ":memory:")
        db.insertImportedSets([set(1, raw: "Foam Roll Upper Back", id: nil), set(2, raw: "Foam Roll Upper Back", id: nil),
                               set(1, raw: "Other", id: nil)])
        db.setImportNameIgnored("Foam Roll Upper Back", true)
        XCTAssertEqual(db.unmatchedImportNames().map(\.name), ["Other"])
        XCTAssertEqual(db.ignoredImportNames().first?.sets, 2)
        XCTAssertTrue(db.allImportedSets().allSatisfy { $0.exerciseId == nil }, "rows are not touched")

        db.clearAllImports()
        XCTAssertEqual(db.ignoredImportNames().map(\.name), ["Foam Roll Upper Back"], "survives clearing imports")
        db.setImportNameIgnored("Foam Roll Upper Back", false)
        XCTAssertTrue(db.ignoredImportNames().isEmpty)

        db.setImportNameIgnored("Butt Kick", true)
        db.wipeAll()
        XCTAssertTrue(db.ignoredImportNames().isEmpty)
    }

    /// Two from the real export where the search lands the right exercise.
    func test_suggestionsPutTheRightExerciseInTheTopThree() throws {
        let coach = CoachDatabase.shared
        for (name, want) in [("Single Leg Leg Extension", "Leg Extension"), ("Elliptical", "Elliptical Machine")] {
            guard let wantId = coach.exerciseId(forImportName: want) else { throw XCTSkip("catalog has no \(want)") }
            XCTAssertTrue(UnmatchedNamesSheet.suggestions(for: name).map(\.id).contains(wantId), name)
        }
        XCTAssertLessThanOrEqual(UnmatchedNamesSheet.suggestions(for: "Push").count, 3)
    }

    func test_resolverAndMaintenanceUseTheMap() {
        let db = UserDatabase(path: ":memory:")
        db.setImportName("Mystery", exerciseId: 42)
        XCTAssertEqual(db.importNameResolver(coach: .shared)("Mystery"), 42)

        db.insertImportedSets([set(1, raw: "Mystery", id: nil)])
        ImportMaintenance.run(db: db)
        XCTAssertEqual(db.allImportedSets().first?.exerciseId, 42)
    }
}
