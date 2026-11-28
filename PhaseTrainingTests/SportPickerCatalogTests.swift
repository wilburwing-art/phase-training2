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

    /// Backlog 2026-11e 3.3: the MTI triathlon and adventure race plans
    /// (`scripts/db/distill_multisport.py`). None of the three had routines
    /// before it.
    func testMultiSportFamilyIsInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["multi-sport-endurance", "triathlon", "adventure-racing"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2, slug)
        }
        XCTAssertEqual(
            CoachDatabase.shared.authoredRoutineIds(sportSlug: "triathlon", phaseLabels: ["maintenance"]).count, 2)
    }

    /// Backlog 2026-11e 3.4: the hiking and mountaineering children share the
    /// MTI objective-plan routines (`scripts/db/distill_hike_mountain.py`).
    /// Seven of the eight had no routines before it.
    func testHikeAndMountainChildrenAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in [
            "day-hiking", "backpacking", "fastpacking", "international-trekking",
            "non-tech-mountaineering", "technical-mountaineering",
            "expedition-mountaineering", "scrambling",
        ] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2, slug)
        }
    }

    func testRunningChildrenAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in [
            "mountain-running", "fell-running", "trail-ultra-100k", "trail-ultra-100mi",
            "obstacle-course-racing", "orienteering-foot",
        ] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2, slug)
        }
    }

    func testNordicAndBackcountrySkiAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["xc-skiing", "backcountry-touring", "telemark-skiing"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2, slug)
        }
    }

    func testGrapplingChildrenAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["bjj", "bjj-gi", "bjj-nogi", "judo", "wrestling", "sambo"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2, slug)
        }
    }

    func testFootballAndRollerDerbyAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let phases: [String: [String]] = [
            "flag-football": ["base", "build", "maintenance"],
            "roller-derby": ["build"],
        ]
        for (slug, labels) in phases {
            XCTAssertTrue(slugs.contains(slug), slug)
            for label in labels {
                XCTAssertGreaterThanOrEqual(
                    CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: [label]).count, 2,
                    "\(slug)/\(label)")
            }
        }
    }

    func testHuntingIsInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["fishing-hunting", "backcountry-hunting", "bow-hunting"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            for label in ["base", "build"] {
                XCTAssertGreaterThanOrEqual(
                    CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: [label]).count, 2,
                    "\(slug)/\(label)")
            }
        }
    }

    func testStrengthSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["bodybuilding", "kettlebell-sport"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2,
                "\(slug)/build")
        }
    }

    func testPaddleAndClimbingChildrenAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["canoeing", "rafting", "multi-pitch", "aid-climbing"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: ["build"]).count, 2,
                "\(slug)/build")
        }
    }

    func testParaglidingIsHiddenWhileUnderTheFloor() {
        // Paragliding's one routine is under the 25-minute floor. This flips
        // when 11e 4.5 distills paragliding routines.
        XCTAssertFalse(SportCatalog.isPlannable("paragliding"))
        XCTAssertTrue(SportPickerCatalog.sections(matching: "paragliding").isEmpty)
    }

    /// Backlog 2026-11e 4.1: the external-source pilot. Each sport has 2+
    /// qualifying routines from `scripts/db/distill_pilot_external.py`.
    func testExternalPilotSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["boxing", "fencing", "dressage", "dinghy-sailing", "table-tennis"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertFalse(SportPickerCatalog.sections(matching: slug.replacingOccurrences(of: "-", with: " ")).isEmpty, slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
    }

    /// Backlog 2026-11e 4.8: golf fitness and senior golf get the Lephart 2007
    /// and White 2026 routines (`scripts/db/distill_golf.py`). golf-fitness had
    /// none before it, and golf-senior's two were mobility and warm-up.
    func testGolfFitnessAndSeniorGolfAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        for slug in ["golf-fitness", "golf-senior"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertFalse(SportPickerCatalog.sections(matching: slug.replacingOccurrences(of: "-", with: " ")).isEmpty, slug)
            for phase in [["off_season", "base"], ["build"], ["maintenance"]] {
                XCTAssertFalse(
                    CoachDatabase.shared.authoredRoutineIds(sportSlug: slug, phaseLabels: phase).isEmpty,
                    "\(slug)/\(phase)")
            }
        }
    }

    /// Backlog 2026-11e 4.2: combat sports from `scripts/db/distill_combat.py`.
    /// Six reach 2+ qualifying routines; capoeira and kendo have one each and
    /// show in the picker on it. Krav maga, aikido and iaido moved to bucket D.
    func testCombatSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let covered = ["muay-thai", "kickboxing", "karate", "taekwondo", "kung-fu", "hema"]
        for slug in covered + ["capoeira", "kendo"] {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertTrue(SportCatalog.isPlannable(slug), slug)
        }
        for slug in covered {
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
    }

    /// Backlog 2026-11e 4.3. Seven racquet and team sports reach 2+ qualifying
    /// routines from external sources. Racquetball, disc golf and ultimate
    /// moved to bucket D.
    func testRacquetAndTeamSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let covered = ["padel", "badminton", "softball", "hockey", "lacrosse", "cricket", "team-handball"]
        for slug in covered {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertTrue(SportCatalog.isPlannable(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
    }

    /// Backlog 2026-11e 4.4. Five water and wind sports reach 2+ qualifying
    /// routines from external sources. Wing foiling, hydrofoiling, spearfishing
    /// and swimrun moved to bucket D; water polo and artistic swimming wait on 11e Phase 6.
    func testWaterAndWindSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let covered = ["windsurfing", "kitesurfing", "wakeboarding", "wakesurfing", "freediving"]
        for slug in covered {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertTrue(SportCatalog.isPlannable(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
    }

    func testSnowWheelsAndAirSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let covered = ["skateboarding", "inline-skating", "catamaran-sailing"]
        for slug in covered {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertTrue(SportCatalog.isPlannable(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
    }

    func testMovementStrengthAndDanceSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let covered = ["tai-chi-qigong", "movement-culture", "pole-fitness", "crossfit", "olympic-weightlifting",
                       "dance-fitness", "contemporary-dance", "hip-hop-dance"]
        for slug in covered {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertTrue(SportCatalog.isPlannable(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
    }

    func testEquestrianArcheryAndRestSportsAreInThePicker() {
        let slugs = Set(allSports.map(\.slug))
        let covered = ["equestrian-trail", "equestrian-endurance", "equestrian-eventing", "show-jumping", "polo",
                       "archery"]
        for slug in covered {
            XCTAssertTrue(slugs.contains(slug), slug)
            XCTAssertTrue(SportCatalog.isPlannable(slug), slug)
            XCTAssertGreaterThanOrEqual(
                CoachDatabase.shared.authoredRoutineIds(
                    sportSlug: slug, phaseLabels: AuthoredRoutineSelector.allPhaseLabels).count, 2,
                slug)
        }
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
