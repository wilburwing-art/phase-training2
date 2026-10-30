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

    func test_resolverAndMaintenanceUseTheMap() {
        let db = UserDatabase(path: ":memory:")
        db.setImportName("Mystery", exerciseId: 42)
        XCTAssertEqual(db.importNameResolver(coach: .shared)("Mystery"), 42)

        db.insertImportedSets([set(1, raw: "Mystery", id: nil)])
        ImportMaintenance.run(db: db)
        XCTAssertEqual(db.allImportedSets().first?.exerciseId, 42)
    }
}
