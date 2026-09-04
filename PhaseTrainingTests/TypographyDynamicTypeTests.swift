import XCTest
import SwiftUI
@testable import PhaseTraining

/// T2-1 / T2-8. The whole type system is one `TypeSpec` table, and until
/// 2026-09-04 every entry was `Font.custom(_:size:)`: fixed-size, immune to
/// Dynamic Type. A grep for `relativeTo` across 134 `.custom(` call sites found
/// zero. These pin that every style now scales, and that the design sizes did
/// not move in the process.
final class TypographyDynamicTypeTests: XCTestCase {

    private let all: [TypeStyle] = [.displayL, .displayM, .displayS, .body,
                                    .monoL, .monoM, .monoS, .monoXS, .micro]

    func test_everyStyleScalesWithATextStyle() {
        // Compiles only if `relativeTo` is defined for every case; the
        // assertion is that the mapping is sane (a display style must not be
        // pinned to a caption curve and vice-versa).
        for style in all {
            let ts = style.relativeTo
            switch style {
            case .displayL: XCTAssertEqual(ts, .largeTitle)
            case .displayM: XCTAssertEqual(ts, .title)
            case .displayS: XCTAssertEqual(ts, .headline)
            case .body, .monoS: XCTAssertEqual(ts, .footnote)
            case .monoL: XCTAssertEqual(ts, .title2)
            case .monoM: XCTAssertEqual(ts, .body)
            case .monoXS, .micro: XCTAssertEqual(ts, .caption2)
            }
        }
    }

    func test_designSizesUnchanged() {
        XCTAssertEqual(TypeStyle.displayL.designSize, 34)
        XCTAssertEqual(TypeStyle.displayM.designSize, 26)
        XCTAssertEqual(TypeStyle.displayS.designSize, 16)
        XCTAssertEqual(TypeStyle.body.designSize, 13)
        XCTAssertEqual(TypeStyle.monoL.designSize, 22)
        XCTAssertEqual(TypeStyle.monoM.designSize, 17)
        XCTAssertEqual(TypeStyle.monoS.designSize, 13.5)
        XCTAssertEqual(TypeStyle.monoXS.designSize, 11)
        XCTAssertEqual(TypeStyle.micro.designSize, 10)
    }

    func test_relativeStyleDefaultSizeIsNearTheDesignSize() {
        // Keeps the scale curve proportional: if a 13pt design size were
        // pinned to .largeTitle (34), it would grow ~2.6x faster than intended.
        let defaults: [Font.TextStyle: CGFloat] = [
            .largeTitle: 34, .title: 28, .title2: 22, .headline: 17,
            .body: 17, .footnote: 13, .caption2: 11,
        ]
        for style in all {
            let base = defaults[style.relativeTo] ?? 0
            XCTAssertGreaterThan(base, 0)
            let ratio = style.designSize / base
            XCTAssertTrue((0.75...1.25).contains(ratio),
                          "\(style) design \(style.designSize) vs \(style.relativeTo) default \(base) — ratio \(ratio) will scale disproportionately")
        }
    }
}
