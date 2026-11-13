import SwiftUI
import XCTest
@testable import PhaseTraining

final class MotionTests: XCTestCase {
    private let sample = Animation.easeInOut(duration: 0.2)

    func test_fadeKeepsTheAnimationEitherWay() {
        XCTAssertEqual(Motion.animation(sample, .fade, reduced: true), sample)
        XCTAssertEqual(Motion.animation(sample, .fade, reduced: false), sample)
    }

    func test_movementIsDroppedWhenReduced() {
        XCTAssertNil(Motion.animation(sample, .movement, reduced: true))
        XCTAssertEqual(Motion.animation(sample, .movement, reduced: false), sample)
    }

    func test_isReducedFollowsTheEnvironmentValueOrTheLaunchArgument() {
        XCTAssertTrue(Motion.isReduced(true))
        XCTAssertEqual(Motion.isReduced(false), Motion.forcedByLaunchArgument)
    }
}
