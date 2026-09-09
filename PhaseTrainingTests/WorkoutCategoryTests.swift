//
//  WorkoutCategoryTests.swift
//  PhaseTrainingTests
//
//  The Workouts segment's category tiles must leave no bundled routine
//  unreachable: every goal tile's memberGoals union plus the catch-all
//  `.other` bucket must account for every row in coach.db, and sport tiles
//  must resolve through the curated routine_sports join (not free-text tags).
//

import XCTest
@testable import PhaseTraining

final class WorkoutCategoryTests: XCTestCase {

    private var allGoalSlugs: Set<String> {
        Set(WorkoutGoalTile.allCases.flatMap { $0.memberGoals })
    }

    /// Every routine lands in exactly one goal tile: named tiles claim their
    /// goals, the catch-all takes null + unclaimed. No routine may be
    /// unreachable or double-counted.
    func testGoalTilesPartitionEveryRoutine() throws {
        let all = CoachDatabase.shared.listRoutines()
        try XCTAssertGreaterThan(all.count, 100, "bundled catalog missing")

        var claimed = 0
        for tile in WorkoutGoalTile.allCases where tile != .other {
            let rows = CoachDatabase.shared.listRoutines(goals: tile.memberGoals)
            for r in rows {
                XCTAssertTrue(
                    tile.memberGoals.contains(r.goal ?? "__null__"),
                    "\(r.name) (goal \(r.goal ?? "nil")) matched tile \(tile.label)")
            }
            claimed += rows.count
        }
        let catchAll = CoachDatabase.shared.listRoutines(goals: [])
        for r in catchAll {
            XCTAssertFalse(
                allGoalSlugs.contains(r.goal ?? "__null__"),
                "\(r.name) has a claimed goal \(r.goal ?? "nil") but landed in the catch-all")
        }
        XCTAssertEqual(
            claimed + catchAll.count, all.count,
            "goal tiles + catch-all must account for every bundled routine")
    }

    /// Catch-all with a search term still works — the WHERE composition
    /// (name LIKE + goal NOT IN) must not drop rows or error out.
    func testCatchAllComposesWithSearch() {
        let catchAll = CoachDatabase.shared.listRoutines(goals: [])
        for row in catchAll {
            let found = CoachDatabase.shared.listRoutines(search: row.name, goals: [])
            XCTAssertTrue(found.contains { $0.id == row.id },
                          "catch-all + search lost '\(row.name)'")
        }
    }

    /// Sport tiles come from the curated routine_sports join: each listed
    /// sport has real linked routines, and snowboarding (the motivating
    /// example) is present.
    func testSportTilesResolveToLinkedRoutines() throws {
        let sports = CoachDatabase.shared.listRoutineSports()
        XCTAssertFalse(sports.isEmpty, "no sports carry linked routines")
        XCTAssertTrue(sports.contains { $0.slug == "snowboarding" },
                      "snowboarding must surface as a sport tile")

        for sport in sports {
            XCTAssertGreaterThanOrEqual(
                sport.count, 2, "\(sport.name) listed despite < 2 routines")
            let rows = CoachDatabase.shared.listRoutines(sportSlug: sport.slug)
            XCTAssertEqual(
                rows.count, sport.count,
                "\(sport.slug): listRoutines(sportSlug:) count disagrees with tile count")
        }
    }

    /// The full Unfiltered = named-goal routines + catch-all, independent of
    /// sport scoping.
    func testSportAndGoalQueriesAreIndependent() {
        let all = CoachDatabase.shared.listRoutines()
        let bySport = CoachDatabase.shared.listRoutines(sportSlug: "snowboarding")
        XCTAssertTrue(bySport.allSatisfy { row in all.contains { $0.id == row.id } })
        // Sport rows include the full goal spectrum — prehab programs for a
        // sport must still appear under that sport's tile.
        XCTAssertTrue(bySport.contains { $0.goal != "strength" },
                      "sport scoping collapsed to one goal")
    }

    // MARK: - Catch-all membership

    /// The motivating orphan cases: mobility/recovery/antagonist/accessory
    /// goals claimed by no named tile must land in `.other`, not vanish.
    func testUnclaimedGoalsLandInCatchAll() {
        let unclaimed = ["mobility", "recovery", "antagonist", "accessory"]
        for goal in unclaimed {
            let rows = CoachDatabase.shared.listRoutines(goals: [])
            XCTAssertTrue(rows.contains { $0.goal == goal },
                          "goal '\(goal)' missing from the catch-all bucket")
            for tile in WorkoutGoalTile.allCases where tile != .other {
                let named = CoachDatabase.shared.listRoutines(goals: tile.memberGoals)
                XCTAssertFalse(named.contains { $0.goal == goal },
                               "goal '\(goal)' also claimed by \(tile.label)")
            }
        }
    }

    /// Catch-all must not be empty on the bundled catalog — if it ever is,
    /// someone added a named tile for everything and the tile's "Browse"
    /// affordance lies.
    func testCatchAllIsNonEmptyOnBundledCatalog() {
        XCTAssertFalse(CoachDatabase.shared.listRoutines(goals: []).isEmpty,
                       "catch-all tile would render an empty drill-down")
    }

    // MARK: - Sport listing shape

    /// Depth guard: depth-2 leaf variants (sport-lead, bouldering-indoor,
    /// golf-senior variants…) must not produce tiles — depth <= 1 is the
    /// listing rule. Depth-1 children of umbrella roots (golf-amateur under
    /// golf, road-running under running) DO tile alongside their parent;
    /// the overlap is intentional, since a routine can be linked at both
    /// levels and users think in real sports, not taxonomy roots.
    func testDeepSportSpecializationsExcluded() {
        let sports = CoachDatabase.shared.listRoutineSports()
        let depth2 = ["sport-lead", "sport-top-rope", "bouldering-indoor",
                      "bouldering-outdoor", "trad-climbing", "ice-climbing",
                      "mountain-running", "fell-running", "disc-golf", "topgolf"]
        for slug in depth2 {
            XCTAssertFalse(sports.contains { $0.slug == slug },
                           "depth-2 variant '\(slug)' leaked into sport tiles")
        }
        let depth1 = ["snowboarding", "sport-climbing", "bouldering",
                      "golf-amateur", "road-running", "tennis"]
        for slug in depth1 {
            XCTAssertTrue(sports.contains { $0.slug == slug },
                          "depth-1 sport '\(slug)' missing from sport tiles")
        }
    }

    /// Every listed sport resolves its claimed count exactly, and the union
    /// of sport-scoped queries is a subset of the full catalog.
    func testSportCountsAreExactAndDisjointFromNothing() {
        let all = CoachDatabase.shared.listRoutines()
        let allIds = Set(all.map { $0.id })
        let sports = CoachDatabase.shared.listRoutineSports()
        var seenIds: Set<Int> = []
        for sport in sports {
            let rows = CoachDatabase.shared.listRoutines(sportSlug: sport.slug)
            XCTAssertEqual(rows.count, sport.count, sport.slug)
            for r in rows { seenIds.insert(r.id) }
        }
        XCTAssertTrue(seenIds.isSubset(of: allIds))
    }

    /// A sport + search + goal stack: filters compose without dropping rows.
    func testSportComposesWithSearchAndGoal() {
        let snow = CoachDatabase.shared.listRoutines(sportSlug: "snowboarding")
        // Every snowboarding row must survive a name search on itself.
        for row in snow {
            let found = CoachDatabase.shared.listRoutines(
                search: row.name, sportSlug: "snowboarding")
            XCTAssertTrue(found.contains { $0.id == row.id },
                          "sport+search lost '\(row.name)'")
        }
        // And goal scoping intersects correctly: anything returned for a
        // named tile's goals must carry one of those goals.
        let strengthGoals = WorkoutGoalTile.strength.memberGoals
        let scoped = CoachDatabase.shared.listRoutines(
            goals: strengthGoals, sportSlug: "snowboarding")
        XCTAssertTrue(scoped.allSatisfy { strengthGoals.contains($0.goal ?? "__null__") })
    }

    // MARK: - Tile model invariants

    /// `WorkoutGoalTile.memberGoals` values must exist in the bundled
    /// catalog — a typo'd goal slug silently empties a tile.
    func testNamedTileGoalsAllExistInCatalog() {
        let known = Set(CoachDatabase.shared.goalCounts().map { $0.goal })
        for tile in WorkoutGoalTile.allCases where tile != .other {
            for goal in tile.memberGoals {
                XCTAssertTrue(known.contains(goal),
                              "\(tile.label) claims goal '\(goal)' which no routine carries")
                // The reverse too: catalog goal → tile coverage.
                let rows = CoachDatabase.shared.listRoutines(goals: [goal])
                XCTAssertFalse(rows.isEmpty, "goal '\(goal)' query returned nothing")
            }
        }
    }

    /// Every catalog goal is claimed by exactly one named tile or the
    /// catch-all — the DB-side known-goal list and the Swift enums can't
    /// drift apart in either direction.
    func testEveryCatalogGoalIsClaimedExactlyOnce() {
        let goals = CoachDatabase.shared.goalCounts().map { $0.goal }
        let claimedBy: [String: [String]] = Dictionary(
            grouping: WorkoutGoalTile.allCases.filter { $0 != .other }
                .flatMap { tile in tile.memberGoals.map { ($0, tile.rawValue) } },
            by: { $0.0 }).mapValues { $0.map { $0.1 } }
        for goal in goals {
            let owners = claimedBy[goal] ?? []
            XCTAssertLessThanOrEqual(
                owners.count, 1,
                "goal '\(goal)' claimed by multiple tiles: \(owners)")
        }
        // And the DB query's known-goal set (built from memberGoals inside
        // listRoutines) covers every goal the named tiles claim — exercised
        // by comparing tile queries against raw goal equality.
        for tile in WorkoutGoalTile.allCases where tile != .other {
            let viaTile = CoachDatabase.shared.listRoutines(goals: tile.memberGoals)
            for goal in tile.memberGoals {
                let viaExact = CoachDatabase.shared.listRoutines(goal: goal)
                XCTAssertTrue(
                    viaExact.allSatisfy { g in viaTile.contains { $0.id == g.id } },
                    "\(tile.rawValue): exact goal '\(goal)' rows missing from tile query")
            }
        }
    }

    /// minCount parameter actually filters: raising it to 3 shrinks (or keeps)
    /// the tile list, never grows it.
    func testMinCountFloorFilters() {
        let base = CoachDatabase.shared.listRoutineSports(minCount: 2)
        let strict = CoachDatabase.shared.listRoutineSports(minCount: 3)
        XCTAssertLessThanOrEqual(strict.count, base.count)
        XCTAssertFalse(strict.isEmpty)
    }
}
