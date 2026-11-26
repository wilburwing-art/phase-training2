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

    /// Backlog 2026-11e bucket A: the 36 sports that already had 2+ qualifying
    /// routines at b128f61. Item 2.1 spot-checked their routines; each one is
    /// offered in the onboarding and profile picker.
    func testBucketASportsAreInThePicker() {
        let bucketA = [
            "baseball-adult", "basketball", "bjj", "bjj-gi", "calisthenics",
            "comp-climbing", "cyclocross", "dragon-boat", "equestrian", "golf",
            "golf-amateur", "golf-traditional", "gravel-cycling", "gymnastics-adult",
            "judo", "kayaking", "marathon", "martial-arts", "mma", "parkour",
            "pickleball", "pilates", "powerlifting", "racquet-sports", "road-cycling",
            "road-running", "rowing", "rugby", "soccer", "squash",
            "strength-fitness-sports", "strongman", "tennis", "volleyball", "yoga",
            "yoga-movement",
        ]
        XCTAssertEqual(bucketA.count, 36)
        let slugs = Set(allSports.map(\.slug))
        for slug in bucketA {
            XCTAssertTrue(slugs.contains(slug), slug)
        }
    }

    /// Backlog 2026-11e 3.1: the surf family shares the MTI Surf Pre-Season V2
    /// routines (`scripts/db/distill_surf.py`). Bodysurfing and skimboarding
    /// had no routines before it.
    func testSurfFamilyIsInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["surf-wave-sports", "surfing", "bodyboarding", "bodysurfing", "skimboarding"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2, slug)
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
