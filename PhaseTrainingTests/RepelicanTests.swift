import XCTest
@testable import PhaseTraining

/// The Repelican mascot's build tracks the user's training phase. The
/// phase → `bulk` mapping is the source of truth for that, so the boundaries
/// (off-season ramp, lean peaking, endurance scaling) matter — a marathoner
/// must never render Swole.
final class RepelicanTests: XCTestCase {

    private let acc = 0.0001

    // MARK: - Named builds

    func test_buildPresets() {
        XCTAssertEqual(RepelicanBuild.lean.bulk, 0.0, accuracy: acc)
        XCTAssertEqual(RepelicanBuild.athletic.bulk, 0.55, accuracy: acc)
        XCTAssertEqual(RepelicanBuild.swole.bulk, 1.0, accuracy: acc)
    }

    // MARK: - Endurance classification

    func test_isEndurance() {
        XCTAssertTrue(RepelicanPhysique.isEndurance(Sport(slug: "running", name: "Running")))
        XCTAssertTrue(RepelicanPhysique.isEndurance(Sport(slug: "cycling", name: "Cycling")))
        XCTAssertFalse(RepelicanPhysique.isEndurance(Sport(slug: "bodybuilding", name: "Bodybuilding")))
        XCTAssertFalse(RepelicanPhysique.isEndurance(nil))
    }

    // MARK: - Phase → bulk (strength-primary)

    func test_offSeasonRampsUpOverWeeks() {
        XCTAssertEqual(bulk(.offSeason, week: 1), 0.40, accuracy: acc)
        XCTAssertEqual(bulk(.offSeason, week: 3), 0.60, accuracy: acc)
        XCTAssertEqual(bulk(.offSeason, week: 5), 0.80, accuracy: acc)
    }

    func test_offSeasonCapsAtPointEight() {
        // Long off-seasons don't keep inflating past the cap.
        XCTAssertEqual(bulk(.offSeason, week: 12), 0.80, accuracy: acc)
    }

    func test_offSeasonNilWeekTreatedAsWeekOne() {
        XCTAssertEqual(bulk(.offSeason, week: nil), 0.40, accuracy: acc)
    }

    func test_balancedPhases() {
        XCTAssertEqual(bulk(.preSeason, week: 2), 0.55, accuracy: acc)
        XCTAssertEqual(bulk(.maintenance, week: 2), 0.55, accuracy: acc)
    }

    func test_competitionPhasesTrendLean() {
        XCTAssertEqual(bulk(.inSeason, week: 2), 0.35, accuracy: acc)
        XCTAssertEqual(bulk(.eventPrep, week: 2), 0.25, accuracy: acc)
    }

    // MARK: - Endurance scaling

    func test_enduranceStaysLeaner() {
        // Same phase, scaled down for an endurance-primary athlete.
        XCTAssertEqual(bulkEndurance(.offSeason, week: 5), 0.48, accuracy: acc) // 0.80 × 0.6
        XCTAssertEqual(bulkEndurance(.preSeason, week: 2), 0.33, accuracy: acc) // 0.55 × 0.6
        XCTAssertEqual(bulkEndurance(.eventPrep, week: 2), 0.15, accuracy: acc) // 0.25 × 0.6
    }

    func test_allValuesStayInUnitRange() {
        for phase in SeasonPhase.allCases {
            for week in [nil, 1, 3, 6, 20] as [Int?] {
                for endurance in [true, false] {
                    let v = RepelicanPhysique.bulk(phase: phase, weekInPhase: week, primaryIsEndurance: endurance)
                    XCTAssertGreaterThanOrEqual(v, 0)
                    XCTAssertLessThanOrEqual(v, 1)
                }
            }
        }
    }

    // MARK: - Helpers

    private func bulk(_ phase: SeasonPhase, week: Int?) -> Double {
        RepelicanPhysique.bulk(phase: phase, weekInPhase: week, primaryIsEndurance: false)
    }
    private func bulkEndurance(_ phase: SeasonPhase, week: Int?) -> Double {
        RepelicanPhysique.bulk(phase: phase, weekInPhase: week, primaryIsEndurance: true)
    }
}
