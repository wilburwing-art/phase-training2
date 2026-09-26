// SportCatalogSlugTests.swift — every onboarding slug must be a real
// sport_categories.slug. Every sport join in the app (authored routines, the
// exercise search boost, discipline-foundation visibility, the sport icon)
// matches the slug exactly, so a drifted slug silently joins nothing.
//
// Caught nothing until 2026-09-26: "stand-up-paddleboarding" shipped while
// the row is "sup", and SeasonFidelityTest only covers season-engine sports.

import XCTest
import SQLite3
@testable import PhaseTraining

final class SportCatalogSlugTests: XCTestCase {

    private func dbSlugs() throws -> Set<String> {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "coach", ofType: "db"))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT slug FROM sport_categories", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var out = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.insert(String(cString: c)) }
        }
        return out
    }

    func test_everyCatalogSlug_isARealSportCategory() throws {
        let slugs = try dbSlugs()
        XCTAssertGreaterThan(slugs.count, 100, "fixture: bundled coach.db must load")
        let missing = Sport.catalog.map(\.slug).filter { !slugs.contains($0) }
        XCTAssertEqual(missing, [], "catalog slugs with no sport_categories row join nothing")
    }

    func test_renamedSlugTargets_areCatalogSlugs() {
        let catalog = Set(Sport.catalog.map(\.slug))
        for (old, new) in Sport.renamedSlugs {
            XCTAssertTrue(catalog.contains(new), "\(old) maps to \(new), which is not in the catalog")
            XCTAssertFalse(catalog.contains(old), "\(old) is still in the catalog")
        }
    }

    func test_oldSUPSlug_decodesToTheRealOne() throws {
        let decoded = try JSONDecoder().decode([Sport].self, from: Data(#"["stand-up-paddleboarding","stand_up_paddleboarding"]"#.utf8))
        XCTAssertEqual(decoded.map(\.slug), ["sup", "sup"])
        XCTAssertEqual(decoded.first?.name, "Stand-Up Paddleboarding")
    }

    func test_sup_nowReachesItsTaggedExercises() {
        let boosted = CoachDatabase.shared.searchExercises(search: nil, userSportSlugs: ["sup"]).exercises
        let unboosted = CoachDatabase.shared.searchExercises(search: nil, userSportSlugs: ["stand-up-paddleboarding"]).exercises
        XCTAssertNotEqual(boosted.map(\.id), unboosted.map(\.id),
                          "the real slug should change what the sport filter returns; the old one matched nothing")
    }
}
