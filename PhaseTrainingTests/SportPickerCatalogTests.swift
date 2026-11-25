import XCTest
@testable import PhaseTraining

final class SportPickerCatalogTests: XCTestCase {
    private var allSports: [Sport] { SportPickerCatalog.sections.flatMap(\.sports) }

    func testEverySectionedSportIsPlannable() {
        XCTAssertFalse(allSports.isEmpty)
        for sport in allSports {
            XCTAssertTrue(SportCatalog.isPlannable(sport.slug), sport.slug)
        }
    }

    func testOldPickerSetIsSubset() {
        let slugs = Set(allSports.map(\.slug))
        for sport in Sport.catalog where SportCatalog.isPlannable(sport.slug) {
            XCTAssertTrue(slugs.contains(sport.slug), sport.slug)
        }
    }

    func testFencingIsHiddenWhileUnderTheFloor() {
        // Fencing's one routine is 20 min, under the 25-minute floor. This
        // flips when fencing gets routines.
        XCTAssertFalse(SportCatalog.isPlannable("fencing"))
        XCTAssertTrue(SportPickerCatalog.sections(matching: "fencing").isEmpty)
    }

    func testSearchIsCaseAndWhitespaceInsensitive() {
        let a = SportPickerCatalog.sections(matching: "tennis")
        let b = SportPickerCatalog.sections(matching: "TENNIS ")
        XCTAssertTrue(a.flatMap(\.sports).contains { $0.slug == "tennis" })
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.flatMap(\.sports).map(\.slug), b.flatMap(\.sports).map(\.slug))
    }

    func testEmptyQueryReturnsAllSections() {
        XCTAssertEqual(SportPickerCatalog.sections(matching: "  ").map(\.id),
                       SportPickerCatalog.sections.map(\.id))
    }

    func testDisplayNames() {
        XCTAssertEqual(SportPickerCatalog.sport(slug: "bjj")?.name, "Brazilian Jiu-Jitsu")
        let outside = allSports.first { s in !Sport.catalog.contains { $0.slug == s.slug } }
        XCTAssertNotNil(outside, "expected a plannable sport outside Sport.catalog")
        if let outside {
            let dbName = CoachDatabase.shared.sportCategoryRows().first { $0.slug == outside.slug }?.name
            XCTAssertEqual(outside.name, dbName)
            XCTAssertEqual(Sport.resolve(slug: outside.slug).name, dbName)
        }
    }

    func testSectionIdsAndSlugsAreUnique() {
        let ids = SportPickerCatalog.sections.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        let slugs = allSports.map(\.slug)
        XCTAssertEqual(slugs.count, Set(slugs).count)
    }

    func testRootListedFirstInOwnSection() {
        for section in SportPickerCatalog.sections
        where section.sports.contains(where: { $0.slug == section.root.slug }) {
            XCTAssertEqual(section.sports.first?.slug, section.root.slug)
        }
    }

}
