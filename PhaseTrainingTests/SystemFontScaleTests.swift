import XCTest
@testable import PhaseTraining

final class SystemFontScaleTests: XCTestCase {
    func test_noBox_returnsScaled() {
        XCTAssertEqual(SystemFontScale.pointSize(design: 14, scaled: 14, within: nil), 14)
        XCTAssertEqual(SystemFontScale.pointSize(design: 14, scaled: 30, within: nil), 30)
    }

    func test_defaultSizeInsideBox_isUnchanged() {
        XCTAssertEqual(SystemFontScale.pointSize(design: 14, scaled: 14, within: 28), 14)
    }

    func test_growthStopsAtSeventyPercentOfBox() {
        XCTAssertEqual(SystemFontScale.pointSize(design: 14, scaled: 40, within: 28), 19.6, accuracy: 0.001)
    }

    func test_designSizeOverTheCapIsKept() {
        XCTAssertEqual(SystemFontScale.pointSize(design: 7, scaled: 20, within: 8), 7)
    }

    func test_smallerTextSizeStillShrinksInsideBox() {
        XCTAssertEqual(SystemFontScale.pointSize(design: 14, scaled: 12, within: 28), 12)
    }
}
