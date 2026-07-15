// EraAffinityTests — cohort boundary + style-table coverage for the
// Phase 1 era-affinity engine.

import XCTest
@testable import PhaseTraining

final class EraAffinityTests: XCTestCase {

    // MARK: - Boundary cases on the cohort table

    func testNilAgeReturnsNilCohort() {
        XCTAssertNil(EraAffinity.derivedCohort(forAge: nil))
    }

    func testCurrentMetaUnder20() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 19), .currentMeta)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 13), .currentMeta)
    }

    func testScienceBased20Through27() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 20), .scienceBased)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 24), .scienceBased)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 27), .scienceBased)
    }

    func testRedditFitness28Through39() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 28), .redditFitness)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 33), .redditFitness)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 39), .redditFitness)
    }

    func testTNationForum40Through54() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 40), .tNationForum)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 47), .tNationForum)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 54), .tNationForum)
    }

    func testMagazineBodybuilding55Through69() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 55), .magazineBodybuilding)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 62), .magazineBodybuilding)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 69), .magazineBodybuilding)
    }

    func testVeteranStrength70Plus() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 70), .veteranStrength)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 80), .veteranStrength)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 99), .veteranStrength)
    }

    // Spot-check the exact boundaries called out in the plan.

    func testBoundary27To28() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 27), .scienceBased)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 28), .redditFitness)
    }

    func testBoundary54To55() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 54), .tNationForum)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 55), .magazineBodybuilding)
    }

    func testBoundary69To70() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 69), .magazineBodybuilding)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 70), .veteranStrength)
    }

    func testBoundary19To20() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 19), .currentMeta)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 20), .scienceBased)
    }

    func testBoundary39To40() {
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 39), .redditFitness)
        XCTAssertEqual(EraAffinity.derivedCohort(forAge: 40), .tNationForum)
    }

    // MARK: - Style-table totality

    func testStyleTableCoversAllCohorts() {
        for cohort in EraCohort.allCases {
            let style = EraAffinity.style(for: cohort)
            XCTAssertEqual(style.cohort, cohort)
            XCTAssertFalse(style.displayName.isEmpty,
                           "cohort \(cohort) has empty displayName")
            XCTAssertFalse(style.narrativeBlurb.isEmpty,
                           "cohort \(cohort) has empty narrativeBlurb")
            XCTAssertFalse(style.plainDescriptor.isEmpty,
                           "cohort \(cohort) has empty plainDescriptor")
            XCTAssertFalse(style.splitPreference.isEmpty,
                           "cohort \(cohort) has empty splitPreference")
            XCTAssertFalse(style.terminologyHints.isEmpty,
                           "cohort \(cohort) has empty terminologyHints")
            XCTAssertFalse(style.aestheticTags.isEmpty,
                           "cohort \(cohort) has empty aestheticTags")
        }
    }

    func testAllSixCohortsExist() {
        XCTAssertEqual(EraCohort.allCases.count, 6)
    }

    // MARK: - Override resolution sanity check
    //
    // The override resolution itself lives at the consumer
    // (DemographicProfile picks up `m.eraOverride ?? derived`), but
    // confirm the string round-trip via rawValue works for the
    // persistence path.

    func testEraCohortRawValueRoundTrip() {
        for cohort in EraCohort.allCases {
            let raw = cohort.rawValue
            XCTAssertEqual(EraCohort(rawValue: raw), cohort)
        }
    }

    func testUnknownRawValueReturnsNil() {
        XCTAssertNil(EraCohort(rawValue: "ghost_era"))
    }
}
