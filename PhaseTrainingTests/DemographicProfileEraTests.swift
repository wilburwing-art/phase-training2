// DemographicProfileEraTests — smoke tests for the Phase-1 era-affinity
// thread through DemographicProfile. The interesting per-cohort
// behavior is exercised end-to-end by the eval-rig batches; these
// tests just confirm the field is populated correctly and the
// override-vs-derived resolution behaves as advertised.

import XCTest
@testable import PhaseTraining

final class DemographicProfileEraTests: XCTestCase {

    // MARK: - Derived (no override)

    func testAge58ResolvesToMagazineBodybuilding() {
        var m = TrainingMemory()
        m.age = 58
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.eraCohort, .magazineBodybuilding)
        XCTAssertEqual(p.eraStyle?.cohort, .magazineBodybuilding)
    }

    func testAge22ResolvesToScienceBased() {
        var m = TrainingMemory()
        m.age = 22
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.eraCohort, .scienceBased)
        XCTAssertEqual(p.eraStyle?.cohort, .scienceBased)
    }

    func testNilAgeNoOverrideYieldsNilEra() {
        let m = TrainingMemory()
        let p = DemographicProfile.from(m)
        XCTAssertNil(p.eraCohort)
        XCTAssertNil(p.eraStyle)
    }

    // MARK: - Override

    func testOverrideBeatsDerived() {
        var m = TrainingMemory()
        m.age = 58                                          // derived: magazineBodybuilding
        m.eraOverride = EraCohort.scienceBased.rawValue     // override
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.eraCohort, .scienceBased)
        XCTAssertEqual(p.eraStyle?.cohort, .scienceBased)
    }

    func testUnknownOverrideFallsThroughToDerived() {
        var m = TrainingMemory()
        m.age = 33                                  // derived: redditFitness
        m.eraOverride = "ghost_cohort_2099"         // unknown rawValue
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.eraCohort, .redditFitness)
    }

    func testOverrideWithoutAgeStillResolves() {
        var m = TrainingMemory()
        m.age = nil
        m.eraOverride = EraCohort.tNationForum.rawValue
        let p = DemographicProfile.from(m)
        XCTAssertEqual(p.eraCohort, .tNationForum)
    }

    // MARK: - Rationale

    func testRationaleMentionsEraWhenPresent() {
        var m = TrainingMemory()
        m.age = 58
        let p = DemographicProfile.from(m)
        XCTAssertTrue(p.rationale.contains(where: { $0.contains("Era affinity") }))
    }

    func testRationaleSkipsEraWhenAbsent() {
        let m = TrainingMemory()      // no age, no override
        let p = DemographicProfile.from(m)
        XCTAssertFalse(p.rationale.contains(where: { $0.contains("Era affinity") }))
    }
}
