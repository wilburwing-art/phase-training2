import XCTest
@testable import PhaseTraining

final class TodayStartReasonTests: XCTestCase {
    func test_noPlan_hasNoReason() {
        XCTAssertNil(TodayScreen.startDisabledReason(
            hasPlan: false, kind: .lift, hasTemplate: true, hasActive: false))
    }

    func test_liftDayWithTemplate_hasNoReason() {
        XCTAssertNil(TodayScreen.startDisabledReason(
            hasPlan: true, kind: .lift, hasTemplate: true, hasActive: false))
    }

    func test_liftDayWithoutTemplate_hasReason() {
        XCTAssertNotNil(TodayScreen.startDisabledReason(
            hasPlan: true, kind: .lift, hasTemplate: false, hasActive: false))
    }

    func test_nonLiftDay_hasNoReason() {
        XCTAssertNil(TodayScreen.startDisabledReason(
            hasPlan: true, kind: .rest, hasTemplate: false, hasActive: false))
    }

    func test_activeSession_hasNoReason() {
        XCTAssertNil(TodayScreen.startDisabledReason(
            hasPlan: true, kind: .lift, hasTemplate: false, hasActive: true))
    }
}
