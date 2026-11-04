import XCTest
@testable import PhaseTraining

/// Stopwatch mode records whole seconds held, clamped to the test's cap.
final class HoldTimerStopwatchTests: XCTestCase {

    func test_floorsToWholeSeconds() {
        XCTAssertEqual(HoldTimerSheet.recordedSeconds(elapsed: 41.9, cap: nil), 41)
        XCTAssertEqual(HoldTimerSheet.recordedSeconds(elapsed: 0.4, cap: nil), 0)
    }

    func test_clampsToCap() {
        XCTAssertEqual(HoldTimerSheet.recordedSeconds(elapsed: 75, cap: SkiReadinessTest.balanceCapSeconds), 60)
        XCTAssertEqual(HoldTimerSheet.recordedSeconds(elapsed: 59.99, cap: 60), 59)
    }

    func test_neverNegative() {
        XCTAssertEqual(HoldTimerSheet.recordedSeconds(elapsed: -3, cap: 60), 0)
    }
}
