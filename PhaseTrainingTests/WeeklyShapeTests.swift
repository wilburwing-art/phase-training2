import XCTest
@testable import PhaseTraining

/// `WeeklyShape.resolve` sets the 7-day kind sequence for every plan
/// (`Planner.swift` reads it before placing sport and rest days). Pins the
/// four resolution steps: exact (sport, season), the season-engine slug
/// alias, the (sport, maintenance) fallback, and the default shape.
final class WeeklyShapeTests: XCTestCase {

    private let defaultKinds: [DayKind] = [.lift, .rest, .lift, .rest, .lift, .rest, .rest]

    private func sport(_ slug: String) -> Sport { Sport(slug: slug, name: slug) }

    private func kinds(_ slug: String?, _ season: SeasonPhase) -> [DayKind] {
        WeeklyShape.resolve(primarySport: slug.map(sport), season: season).kinds
    }

    // MARK: - Exact match

    func testExactSportAndSeasonMatch() {
        XCTAssertEqual(kinds("climbing", .inSeason),
                       [.sport, .rest, .lift, .sport, .rest, .rest, .rest])
        XCTAssertEqual(kinds("climbing", .offSeason),
                       [.lift, .sport, .rest, .lift, .lift, .rest, .rest])
        XCTAssertEqual(kinds("alpine-skiing", .eventPrep),
                       [.lift, .rest, .sport, .rest, .lift, .sport, .rest])
    }

    func testSeasonChangesTheShapeForOneSport() {
        XCTAssertNotEqual(kinds("running", .inSeason), kinds("running", .offSeason))
    }

    // MARK: - Ski alias

    /// ski-mountaineering has no rows of its own; it must borrow the
    /// alpine-skiing rows through `SportSeasonGenerator.poolSlug` in every
    /// season instead of falling to the default (which has no sport days).
    func testSkiMountaineeringBorrowsAlpineSkiingInEverySeason() {
        for season in SeasonPhase.allCases {
            XCTAssertEqual(kinds("ski-mountaineering", season),
                           kinds("alpine-skiing", season),
                           "ski-mountaineering \(season) should alias alpine-skiing")
        }
        XCTAssertTrue(kinds("ski-mountaineering", .inSeason).contains(.sport))
    }

    /// bouldering aliases to climbing, which has no eventPrep row: the alias
    /// maintenance step (the last one before the default) must serve it.
    func testAliasFallsBackToAliasMaintenance() {
        XCTAssertEqual(kinds("bouldering", .eventPrep), kinds("climbing", .maintenance))
        XCTAssertNotEqual(kinds("bouldering", .eventPrep), defaultKinds)
    }

    // MARK: - Maintenance fallback

    /// trail-running has only a maintenance row, and its pool slug is itself.
    func testSportWithoutSeasonRowFallsBackToItsMaintenanceRow() {
        let maintenance = kinds("trail-running", .maintenance)
        XCTAssertNotEqual(maintenance, defaultKinds)
        for season in SeasonPhase.allCases {
            XCTAssertEqual(kinds("trail-running", season), maintenance, "\(season)")
        }
        XCTAssertEqual(kinds("bjj", .inSeason), kinds("bjj", .maintenance))
    }

    // MARK: - Default

    func testNoSportGivesDefaultShapeInEverySeason() {
        for season in SeasonPhase.allCases {
            let shape = WeeklyShape.resolve(primarySport: nil, season: season)
            XCTAssertEqual(shape.kinds, defaultKinds, "\(season)")
            XCTAssertEqual(shape.description, "3-day full body strength, a flexible fallback")
        }
    }

    func testUnknownSportGivesDefaultShape() {
        XCTAssertEqual(kinds("underwater-basket-weaving", .inSeason), defaultKinds)
        XCTAssertEqual(kinds("underwater-basket-weaving", .maintenance), defaultKinds)
    }

    // MARK: - Shape invariant

    func testEveryResolvedShapeHasSevenDays() {
        let slugs = ["climbing", "running", "trail-running", "cycling", "snow-sports",
                     "alpine-skiing", "ski-mountaineering", "snowboarding", "bouldering",
                     "bjj", "boxing", "muay-thai", "tennis", "pickleball", "powerlifting",
                     "olympic-weightlifting", "bodybuilding", "crossfit", "yoga", "pilates",
                     "obstacle-course-racing"]
        for slug in slugs {
            for season in SeasonPhase.allCases {
                XCTAssertEqual(kinds(slug, season).count, 7, "\(slug) \(season)")
            }
        }
    }
}
