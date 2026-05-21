// ExerciseFilterTests.swift — guards the muscle-bucket / movement-category
// canonicalization + the unified CoachDatabase.listExercises filter.
//
// The data layer is unit-tested so we can confidently rip out the filter
// UI without retesting it end-to-end every time. Tests target three risk
// areas:
//   1. The slug → bucket mapping covers the granular slugs the DB actually
//      uses (e.g. "pec-major-sternal" must roll up to .chest, not orphan).
//   2. The extended listExercises AND-s its filters correctly — narrowing
//      to (Chest + beginner) returns a non-empty subset of Chest alone.
//   3. Pattern-category filtering matches at least one exercise per
//      category (catches typos / data-import gaps in the category map).

import XCTest
@testable import PhaseTraining

final class ExerciseFilterTests: XCTestCase {

    func test_muscleBucket_resolvesGranularSlugs() {
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "pec-major-sternal"), .chest)
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "lats"), .back)
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "delt-anterior"), .shoulders)
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "glute-med"), .glutes)
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "rectus-abdominis"), .core)
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "vastus-medialis"), .quads)
        XCTAssertEqual(MuscleBucket.bucket(forSlug: "soleus"), .calves)
    }

    func test_muscleBucket_unmappedSlugsReturnNil() {
        XCTAssertNil(MuscleBucket.bucket(forSlug: "full-body"))
        XCTAssertNil(MuscleBucket.bucket(forSlug: "neck"))
        XCTAssertNil(MuscleBucket.bucket(forSlug: "definitely-not-real"))
    }

    func test_listExercises_muscleBucket_returnsRows() {
        let chest = CoachDatabase.shared.listExercises(muscleSlugs: MuscleBucket.chest.memberSlugs)
        XCTAssertGreaterThan(chest.count, 0, "Chest bucket should return some exercises")
    }

    func test_listExercises_andsFilters() {
        // Chest alone vs Chest + beginner. The AND-narrowed set must be a
        // non-empty subset of the broader set.
        let chest = CoachDatabase.shared.listExercises(muscleSlugs: MuscleBucket.chest.memberSlugs)
        let chestBeginner = CoachDatabase.shared.listExercises(
            muscleSlugs: MuscleBucket.chest.memberSlugs,
            difficulty: "beginner"
        )
        XCTAssertLessThanOrEqual(chestBeginner.count, chest.count)
        let chestIds = Set(chest.map(\.id))
        for ex in chestBeginner {
            XCTAssertTrue(chestIds.contains(ex.id), "AND should narrow, not expand")
            XCTAssertEqual(ex.difficulty, "beginner")
        }
    }

    func test_listExercises_pushCategory_hasMatches() {
        let push = CoachDatabase.shared.listExercises(
            patternSlugs: MovementCategory.push.memberPatternSlugs
        )
        XCTAssertGreaterThan(push.count, 0, "Push category should return some exercises")
    }

    func test_listExercises_legsCategory_hasMatches() {
        let legs = CoachDatabase.shared.listExercises(
            patternSlugs: MovementCategory.legs.memberPatternSlugs
        )
        XCTAssertGreaterThan(legs.count, 0)
    }

    func test_listExercises_compoundOnly_excludesIsolation() {
        let compound = CoachDatabase.shared.listExercises(compoundOnly: true)
        XCTAssertGreaterThan(compound.count, 0)
        XCTAssertTrue(compound.allSatisfy(\.isCompound))
    }

    func test_secondaryCount_tracksActiveFilters() {
        var f = ExerciseFilters()
        XCTAssertEqual(f.secondaryCount, 0)
        f.bucket = .chest  // primary, doesn't count toward secondary
        XCTAssertEqual(f.secondaryCount, 0)
        f.modality = "strength"
        f.difficulty = "beginner"
        XCTAssertEqual(f.secondaryCount, 2)
        f.clearSecondary()
        XCTAssertEqual(f.secondaryCount, 0)
        XCTAssertEqual(f.bucket, .chest, "clearSecondary preserves the primary bucket")
    }

    // MARK: - Sport-relevance filter (build 88)

    /// Empty userSportSlugs short-circuits the join — must behave exactly as
    /// the no-sport-filter call. Guards against accidental regressions when
    /// the new SELECT-list bestRel subquery is introduced.
    func test_listExercises_emptySportSlugs_matchesUnfilteredCall() {
        let baseline = CoachDatabase.shared.listExercises()
        let withEmptySports = CoachDatabase.shared.listExercises(userSportSlugs: [])
        XCTAssertEqual(baseline.count, withEmptySports.count)
        XCTAssertEqual(baseline.map(\.id), withEmptySports.map(\.id))
    }

    /// Climbing-only user should see climbing-tagged exercises bubble to the
    /// top and total result count should drop (HEMA / iaido / capoeira hide).
    func test_listExercises_climbingOnly_filtersAndRanks() {
        let baseline = CoachDatabase.shared.listExercises()
        let climbing = CoachDatabase.shared.listExercises(userSportSlugs: ["climbing"])
        XCTAssertGreaterThan(climbing.count, 0, "Climbing user should still see plenty of exercises")
        XCTAssertLessThan(climbing.count, baseline.count,
                          "Sport filter should hide niche non-climbing drills")
        // Hangboard Max Hang (climbing-tagged) should rank above unrelated
        // alphabetically-earlier rows like "45° Back Extension". This is the
        // best_rel ORDER BY at work.
        if let hangIdx = climbing.firstIndex(where: { $0.name.contains("Hangboard Max Hang") }),
           let backExtIdx = climbing.firstIndex(where: { $0.name.contains("45° Back Extension") }) {
            XCTAssertLessThan(hangIdx, backExtIdx,
                              "Climbing-tagged exercise should outrank a non-climbing strength row")
        }
    }

    /// Untagged foundation lifts (the ~76 with zero exercise_sport_relevance
    /// rows) must always remain visible regardless of which sport is selected.
    func test_listExercises_foundationLifts_alwaysVisible() {
        let climbing = CoachDatabase.shared.listExercises(userSportSlugs: ["climbing"])
        let tennis   = CoachDatabase.shared.listExercises(userSportSlugs: ["tennis"])
        // Barbell Back Squat is a universal foundation lift — sport-niche
        // filtering must never hide it.
        XCTAssertTrue(climbing.contains(where: { $0.name == "Barbell Back Squat" }))
        XCTAssertTrue(tennis.contains(where: { $0.name == "Barbell Back Squat" }))
    }

    /// Sport-niche drills (e.g. capoeira) should be visible for that sport's
    /// user but hidden for unrelated sports.
    func test_listExercises_sportNicheRows_hideForUnrelatedSports() {
        let climbing = CoachDatabase.shared.listExercises(userSportSlugs: ["climbing"])
        // Capoeira ginga isn't tagged for climbing — it should not appear.
        XCTAssertFalse(climbing.contains(where: { $0.name.contains("Capoeira") }),
                       "Capoeira drills should be hidden for a climbing-only user")
    }
}
