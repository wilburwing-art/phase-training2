import XCTest
@testable import PhaseTraining

/// Kettle (mascot #2) is an animation-driven mascot: its variation axis is
/// motion, not physique. The pose metadata and the sport → loop mapping are the
/// testable surface (the drawing itself is visual).
final class KettleTests: XCTestCase {

    func test_fiveDistinctPoses() {
        XCTAssertEqual(KettlePose.allCases.count, 5)
        XCTAssertEqual(Set(KettlePose.allCases.map(\.rawValue)).count, 5)
    }

    func test_everyPoseHasLabelAndLoopPeriod() {
        for pose in KettlePose.allCases {
            XCTAssertFalse(pose.label.isEmpty)
            // Loops are short, seamless cycles — a positive, human-scale period.
            XCTAssertGreaterThan(pose.period, 0)
            XCTAssertLessThanOrEqual(pose.period, 5)
        }
    }

    func test_sportMapping() {
        XCTAssertEqual(KettlePose.forSport("climbing"), .climb)
        XCTAssertEqual(KettlePose.forSport("cycling"), .bike)
        // Sports without a dedicated loop fall back to the flex idle.
        XCTAssertEqual(KettlePose.forSport("running"), .flex)
        XCTAssertEqual(KettlePose.forSport(nil), .flex)
    }
}
